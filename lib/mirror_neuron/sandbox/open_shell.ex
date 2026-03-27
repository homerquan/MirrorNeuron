defmodule MirrorNeuron.Sandbox.OpenShell do
  @result_start "__MIRROR_NEURON_RESULT_START__"
  @result_end "__MIRROR_NEURON_RESULT_END__"

  def run(payload, config, opts \\ []) do
    sandbox_name = build_sandbox_name(config, opts)
    executable = Map.get(config, "sandbox_cli", System.get_env("MIRROR_NEURON_OPENSHELL_BIN", "openshell"))
    remote_dir = Map.get(config, "sandbox_upload_path", "/sandbox/job")

    with {:ok, staged_dir} <- stage_workspace(payload, config, opts) do
      try do
        with {:ok, args} <- build_args(sandbox_name, staged_dir, remote_dir, config, opts),
             {:ok, output, exit_code} <- run_command(executable, args),
             {:ok, result} <- extract_result(output, sandbox_name, remote_dir, exit_code) do
          if exit_code == 0 do
            {:ok, result}
          else
            {:error, result}
          end
        end
      after
        File.rm_rf(staged_dir)
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_args(sandbox_name, staged_dir, remote_dir, config, opts) do
    command =
      config
      |> build_command(remote_dir, opts)
      |> List.wrap()

    args =
      ["sandbox", "create", "--name", sandbox_name, "--upload", "#{staged_dir}:#{remote_dir}", "--no-git-ignore"]
      |> maybe_put_flag("--no-keep", Map.get(config, "no_keep", true))
      |> maybe_put_flag("--no-auto-providers", Map.get(config, "no_auto_providers", true))
      |> maybe_put_flag("--gpu", Map.get(config, "gpu", false))
      |> maybe_put_value("--from", Map.get(config, "from"))
      |> maybe_put_value("--remote", Map.get(config, "remote"))
      |> maybe_put_value("--ssh-key", Map.get(config, "ssh_key"))
      |> maybe_put_value("--policy", Map.get(config, "policy"))
      |> maybe_put_many("--provider", Map.get(config, "providers", []))
      |> maybe_put_tty(Map.get(config, "tty"))
      |> Kernel.++(["--"])
      |> Kernel.++(command)

    {:ok, args}
  end

  defp build_command(config, remote_dir, opts) do
    workdir = Map.get(config, "workdir", remote_dir)
    input_file = Path.join(remote_dir, "mirror_neuron_input.json")
    context_file = Path.join(remote_dir, "mirror_neuron_context.json")

    substitutions = %{
      "input_file" => input_file,
      "context_file" => context_file,
      "workdir" => workdir,
      "job_id" => Keyword.get(opts, :job_id, ""),
      "agent_id" => Keyword.get(opts, :agent_id, "")
    }

    actual_command =
      case Map.get(config, "command") do
        nil ->
          "python - <<'PY'\nprint('No command configured for sandbox worker')\nPY"

        command when is_binary(command) ->
          substitute(command, substitutions)

        command when is_list(command) ->
          command
          |> Enum.map(&substitute(to_string(&1), substitutions))
          |> Enum.map(&shell_escape/1)
          |> Enum.join(" ")
      end

    wrapper = """
    set +e
    export MN_INPUT_FILE=#{shell_escape(input_file)}
    export MN_CONTEXT_FILE=#{shell_escape(context_file)}
    export MN_WORKDIR=#{shell_escape(workdir)}
    cd #{shell_escape(workdir)}
    #{actual_command} >/tmp/mirror_neuron_stdout 2>/tmp/mirror_neuron_stderr
    status=$?
    MN_EXIT_CODE="$status" python - <<'PY'
    import json
    import os
    import pathlib

    stdout = pathlib.Path("/tmp/mirror_neuron_stdout").read_text()
    stderr = pathlib.Path("/tmp/mirror_neuron_stderr").read_text()
    result = {
        "exit_code": int(os.environ["MN_EXIT_CODE"]),
        "stdout": stdout,
        "stderr": stderr,
    }
    print("#{ @result_start }")
    print(json.dumps(result))
    print("#{ @result_end }")
    PY
    exit "$status"
    """

    ["bash", "-lc", wrapper]
  end

  defp run_command(executable, args) do
    {output, exit_code} =
      System.cmd(executable, args,
        stderr_to_stdout: true,
        env: [
          {"NO_COLOR", "1"}
        ]
      )

    {:ok, output, exit_code}
  rescue
    error in ErlangError ->
      {:error, "failed to invoke #{executable}: #{Exception.message(error)}"}
  end

  defp extract_result(output, sandbox_name, remote_dir, exit_code) do
    pattern = ~r/#{@result_start}\s*(\{.*?\})\s*#{@result_end}/s

    case Regex.run(pattern, output, capture: :all_but_first) do
      [json_blob] ->
        with {:ok, parsed} <- Jason.decode(json_blob) do
          logs =
            output
            |> String.replace(pattern, "")
            |> String.trim()

          {:ok,
           %{
             "sandbox_name" => sandbox_name,
             "remote_dir" => remote_dir,
             "exit_code" => parsed["exit_code"],
             "stdout" => parsed["stdout"],
             "stderr" => parsed["stderr"],
             "logs" => logs,
             "raw_output" => output
           }}
        else
          {:error, error} -> {:error, Exception.message(error)}
        end

      _ ->
        {:ok,
         %{
           "sandbox_name" => sandbox_name,
           "remote_dir" => remote_dir,
           "exit_code" => exit_code,
           "stdout" => "",
           "stderr" => "",
           "logs" => String.trim(output),
           "raw_output" => output
         }}
    end
  end

  defp stage_workspace(payload, config, opts) do
    sandbox_name = build_sandbox_name(config, opts)
    base_dir = Path.join(System.tmp_dir!(), "mirror_neuron_#{sandbox_name}")
    _ = File.rm_rf(base_dir)
    File.mkdir_p!(base_dir)

    with :ok <- copy_uploads(base_dir, config),
         :ok <- File.write(Path.join(base_dir, "mirror_neuron_input.json"), Jason.encode!(payload, pretty: true)),
         :ok <-
           File.write(
             Path.join(base_dir, "mirror_neuron_context.json"),
             Jason.encode!(
               %{
                 job_id: Keyword.get(opts, :job_id),
                 agent_id: Keyword.get(opts, :agent_id),
                 timestamp: MirrorNeuron.Runtime.timestamp()
               },
               pretty: true
             )
           ) do
      {:ok, base_dir}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      {:error, Exception.message(error)}
  end

  defp copy_uploads(base_dir, config) do
    entries =
      case Map.get(config, "upload_paths") do
        paths when is_list(paths) and paths != [] ->
          Enum.map(paths, fn entry ->
            %{
              "source" => Map.fetch!(entry, "source"),
              "target" => Map.get(entry, "target", Path.basename(Map.fetch!(entry, "source")))
            }
          end)

        _ ->
          case Map.get(config, "upload_path") do
            nil -> []
            source -> [%{"source" => source, "target" => Map.get(config, "upload_as", Path.basename(source))}]
          end
      end

    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      source = entry["source"]
      target = Path.join(base_dir, entry["target"])

      cond do
        File.dir?(source) ->
          File.mkdir_p!(Path.dirname(target))

          case File.cp_r(source, target) do
            {:ok, _files} -> {:cont, :ok}
            {:error, reason, _file} -> {:halt, {:error, inspect(reason)}}
          end

        File.exists?(source) ->
          File.mkdir_p!(Path.dirname(target))

          case File.cp(source, target) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, inspect(reason)}}
          end

        true ->
          {:halt, {:error, "upload source does not exist: #{source}"}}
      end
    end)
  end

  defp build_sandbox_name(config, opts) do
    prefix = Map.get(config, "name_prefix", "mirror-neuron")
    job_id = Keyword.get(opts, :job_id, "job")
    agent_id = Keyword.get(opts, :agent_id, "agent")

    [prefix, job_id, agent_id]
    |> Enum.join("-")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.slice(0, 63)
    |> String.trim("-")
  end

  defp maybe_put_flag(args, _flag, false), do: args
  defp maybe_put_flag(args, flag, true), do: args ++ [flag]

  defp maybe_put_value(args, _flag, nil), do: args
  defp maybe_put_value(args, _flag, ""), do: args
  defp maybe_put_value(args, flag, value), do: args ++ [flag, to_string(value)]

  defp maybe_put_many(args, _flag, []), do: args

  defp maybe_put_many(args, flag, values) do
    args ++ Enum.flat_map(values, &[flag, to_string(&1)])
  end

  defp maybe_put_tty(args, nil), do: args ++ ["--no-tty"]
  defp maybe_put_tty(args, true), do: args ++ ["--tty"]
  defp maybe_put_tty(args, false), do: args ++ ["--no-tty"]

  defp substitute(command, substitutions) do
    Enum.reduce(substitutions, command, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end

  defp shell_escape(value) do
    "'#{String.replace(to_string(value), "'", "'\"'\"'")}'"
  end
end
