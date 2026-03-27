defmodule MirrorNeuron.CLI do
  alias MirrorNeuron.Manifest

  def main(args) do
    maybe_start_distribution()
    Application.ensure_all_started(:mirror_neuron)

    case args do
      ["server"] ->
        IO.puts("MirrorNeuron runtime node is running on #{Node.self()}")
        receive do
        end

      ["validate", manifest_path] ->
        manifest_path
        |> MirrorNeuron.validate_manifest()
        |> print_manifest_validation()

      ["run", manifest_path | rest] ->
        opts = parse_run_options(rest)

        with {:ok, _manifest} <- Manifest.load(manifest_path),
             {:ok, job_id, job} <- MirrorNeuron.run_manifest(manifest_path, opts) do
          output(%{
            ok: true,
            job_id: job_id,
            status: job["status"],
            result: Map.get(job, "result")
          }, opts)
        else
          {:ok, job_id} ->
            output(%{ok: true, job_id: job_id}, opts)

          {:error, reason} ->
            abort(reason)
        end

      ["inspect", "job", job_id] ->
        print_result(MirrorNeuron.inspect_job(job_id))

      ["inspect", "agents", job_id] ->
        print_result(MirrorNeuron.inspect_agents(job_id))

      ["inspect", "nodes"] ->
        output(MirrorNeuron.inspect_nodes())

      ["events", job_id] ->
        print_result(MirrorNeuron.events(job_id))

      ["pause", job_id] ->
        print_result(MirrorNeuron.pause(job_id))

      ["resume", job_id] ->
        print_result(MirrorNeuron.resume(job_id))

      ["cancel", job_id] ->
        print_result(MirrorNeuron.cancel(job_id))

      ["send", job_id, agent_id, message_json] ->
        case Jason.decode(message_json) do
          {:ok, payload} -> print_result(MirrorNeuron.send_message(job_id, agent_id, payload))
          {:error, error} -> abort("invalid JSON payload: #{Exception.message(error)}")
        end

      _ ->
        usage()
    end
  end

  defp parse_run_options(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [json: :boolean, timeout: :integer, no_await: :boolean]
      )

    [
      await: not Keyword.get(opts, :no_await, false),
      timeout: Keyword.get(opts, :timeout, :infinity),
      json: Keyword.get(opts, :json, false)
    ]
  end

  defp print_manifest_validation({:ok, manifest}) do
    output(%{
      ok: true,
      graph_id: manifest.graph_id,
      nodes: Enum.map(manifest.nodes, & &1.node_id),
      entrypoints: manifest.entrypoints
    })
  end

  defp print_manifest_validation({:error, reason}), do: abort(reason)

  defp print_result({:ok, value}), do: output(value)
  defp print_result({:error, reason}), do: abort(reason)

  defp output(value, opts \\ []) do
    if Keyword.get(opts, :json, false) do
      IO.puts(Jason.encode!(value, pretty: true))
    else
      IO.puts(format_human(value))
    end
  end

  defp format_human(value) when is_binary(value), do: value
  defp format_human(value), do: inspect(value, pretty: true, limit: :infinity)

  defp abort(reason) do
    IO.puts(:stderr, "error: #{format_reason(reason)}")
    System.halt(1)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_list(reason), do: Enum.join(reason, "; ")
  defp format_reason(reason), do: inspect(reason, pretty: true)

  defp usage do
    IO.puts("""
    mirror_neuron server
    mirror_neuron validate <manifest.json>
    mirror_neuron run <manifest.json> [--json] [--timeout <ms>] [--no-await]
    mirror_neuron inspect job <job_id>
    mirror_neuron inspect agents <job_id>
    mirror_neuron inspect nodes
    mirror_neuron events <job_id>
    mirror_neuron pause <job_id>
    mirror_neuron resume <job_id>
    mirror_neuron cancel <job_id>
    mirror_neuron send <job_id> <agent_id> <message.json>
    """)
  end

  defp maybe_start_distribution do
    node_name = System.get_env("MIRROR_NEURON_NODE_NAME")
    cookie = System.get_env("MIRROR_NEURON_COOKIE")

    cond do
      Node.alive?() ->
        :ok

      is_nil(node_name) or node_name == "" ->
        :ok

      true ->
        {:ok, _pid} = Node.start(String.to_atom(node_name), :longnames)

        if cookie && cookie != "" do
          Node.set_cookie(String.to_atom(cookie))
        end

        :ok
    end
  end
end
