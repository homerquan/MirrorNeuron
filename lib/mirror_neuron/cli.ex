defmodule MirrorNeuron.CLI do
  require Logger

  alias MirrorNeuron.AgentRegistry
  alias MirrorNeuron.CLI.UI

  def main(args) do
    configure_logger(args)
    maybe_start_distribution()
    Application.ensure_all_started(:mirror_neuron)

    case args do
      ["server"] ->
        maybe_print_banner(:server, "Runtime node #{Node.self()}")
        UI.puts(UI.server_ready(to_string(Node.self())))

        receive do
        end

      ["validate", job_path] ->
        maybe_print_banner(:validate, job_path)

        job_path
        |> MirrorNeuron.validate_manifest()
        |> print_manifest_validation()

      ["run", job_path | rest] ->
        maybe_print_banner(:run, job_path)
        run_job(job_path, parse_run_options(rest))

      ["inspect", "job", job_id] ->
        maybe_print_section("Inspect job", job_id)
        print_job_result(MirrorNeuron.inspect_job(job_id))

      ["inspect", "agents", job_id] ->
        maybe_print_section("Inspect agents", job_id)
        print_agents_result(MirrorNeuron.inspect_agents(job_id))

      ["inspect", "nodes"] ->
        maybe_print_section("Inspect nodes")
        print_nodes(MirrorNeuron.inspect_nodes())

      ["events", job_id] ->
        maybe_print_section("Inspect events", job_id)
        print_events_result(MirrorNeuron.events(job_id))

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

  defp run_job(job_path, opts) do
    with {:ok, bundle} <- MirrorNeuron.validate_manifest(job_path),
         {:ok, job_id} <- MirrorNeuron.run_manifest(job_path, Keyword.put(opts, :await, false)) do
      maybe_print_run_submission(job_id, bundle.manifest, opts)

      cond do
        not Keyword.get(opts, :await, false) ->
          print_detached_run(job_id, opts)

        Keyword.get(opts, :json, false) ->
          case MirrorNeuron.wait_for_job(job_id, Keyword.get(opts, :timeout, :infinity)) do
            {:ok, job} ->
              output(
                %{
                  ok: true,
                  job_id: job_id,
                  status: job["status"],
                  result: Map.get(job, "result")
                },
                opts
              )

            {:error, reason} ->
              abort(reason)
          end

        true ->
          case track_job_progress(job_id, bundle.manifest, Keyword.get(opts, :timeout, :infinity)) do
            {:ok, job} ->
              print_human_run_summary(job_id, job, opts)

            {:error, reason} ->
              abort(reason)
          end
      end
    else
      {:error, reason} ->
        abort(reason)
    end
  end

  defp track_job_progress(job_id, manifest, timeout) do
    started_at = System.monotonic_time(:millisecond)

    UI.start_progress_screen(%{
      job_id: job_id,
      job: %{"status" => "starting"},
      metrics: %{
        collected: 0,
        expected_results: expected_results(manifest, 0),
        sandbox_done: 0,
        sandbox_total: 0,
        leases_running: 0,
        leases_waiting: 0,
        total_events: 0,
        last_event: nil
      },
      started_at: started_at,
      tick: 0
    })

    loop_progress(job_id, manifest, timeout, started_at, 0)
  end

  defp loop_progress(job_id, manifest, timeout, started_at, tick) do
    job = fetch_job_snapshot(job_id)
    events = fetch_events(job_id)
    metrics = build_progress_metrics(events, manifest)

    render_progress_line(job_id, job, metrics, started_at, tick)

    case job do
      %{"status" => status} when status in ["completed", "failed", "cancelled"] ->
        clear_progress_line()
        {:ok, job}

      _ ->
        elapsed = System.monotonic_time(:millisecond) - started_at

        if timeout != :infinity and elapsed > timeout do
          clear_progress_line()
          {:error, "timed out waiting for job #{job_id}"}
        else
          Process.sleep(200)
          loop_progress(job_id, manifest, timeout, started_at, tick + 1)
        end
    end
  end

  defp fetch_job_snapshot(job_id) do
    case MirrorNeuron.inspect_job(job_id) do
      {:ok, job} -> job
      {:error, _reason} -> %{"status" => "starting"}
    end
  end

  defp fetch_events(job_id) do
    case MirrorNeuron.events(job_id) do
      {:ok, events} -> events
      {:error, _reason} -> []
    end
  end

  defp build_progress_metrics(events, manifest) do
    sandbox_total =
      Enum.count(manifest.nodes, &(AgentRegistry.canonical_type(&1.agent_type) == "executor"))

    collected = latest_aggregator_count(events)
    sandbox_done = Enum.count(events, &(&1["type"] == "sandbox_job_completed"))
    lease_requested = Enum.count(events, &(&1["type"] == "executor_lease_requested"))
    lease_acquired = Enum.count(events, &(&1["type"] == "executor_lease_acquired"))
    lease_released = Enum.count(events, &(&1["type"] == "executor_lease_released"))
    total_events = length(events)
    expected_results = expected_results(manifest, sandbox_total)

    %{
      sandbox_total: sandbox_total,
      sandbox_done: sandbox_done,
      leases_running: max(lease_acquired - lease_released, 0),
      leases_waiting: max(lease_requested - lease_acquired, 0),
      collected: collected,
      total_events: total_events,
      expected_results: expected_results,
      last_event: last_notable_event(events)
    }
  end

  defp latest_aggregator_count(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(0, fn event ->
      if event["type"] in ["aggregator_received", "collector_received"] do
        get_in(event, ["payload", "count"]) || 0
      end
    end)
  end

  defp expected_results(manifest, sandbox_total) do
    manifest.nodes
    |> Enum.find_value(sandbox_total, fn node ->
      if AgentRegistry.canonical_type(node.agent_type) == "aggregator" do
        Map.get(node.config, "complete_after")
      end
    end)
  end

  defp last_notable_event(events) do
    events
    |> Enum.reverse()
    |> Enum.find(fn event ->
      event["type"] not in ["agent_message_received", "aggregator_received", "collector_received"]
    end)
  end

  defp render_progress_line(job_id, job, metrics, started_at, tick) do
    if UI.interactive?() do
      UI.update_progress_screen(%{
        job_id: job_id,
        job: job,
        metrics: metrics,
        started_at: started_at,
        tick: tick
      })
    else
      spinner = Enum.at(["|", "/", "-", "\\"], rem(tick, 4))
      status = Map.get(job, "status", "starting")
      elapsed = format_elapsed(System.monotonic_time(:millisecond) - started_at)
      last_event = format_event(metrics.last_event)

      line =
        "#{spinner} job=#{job_id} status=#{status} elapsed=#{elapsed} " <>
          "events=#{metrics.total_events} collected=#{metrics.collected}/#{metrics.expected_results} " <>
          "leases=running:#{metrics.leases_running} waiting:#{metrics.leases_waiting} " <>
          "sandboxes=#{metrics.sandbox_done}/#{metrics.sandbox_total} last=#{last_event}"

      IO.write("\r" <> String.pad_trailing(line, 160))
    end
  end

  defp clear_progress_line do
    if UI.interactive?() do
      UI.clear_progress()
    else
      IO.write("\r" <> String.duplicate(" ", 160) <> "\r")
    end
  end

  defp format_elapsed(milliseconds) do
    total_seconds = div(milliseconds, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, seconds]) |> IO.iodata_to_binary()
  end

  defp format_event(nil), do: "waiting"

  defp format_event(event) do
    type = event["type"]
    agent_id = event["agent_id"]

    if agent_id do
      "#{type}(#{agent_id})"
    else
      to_string(type)
    end
  end

  defp print_human_run_summary(job_id, job, opts) do
    if interactive_output?(opts) do
      UI.puts(UI.job_summary(job_id, job))
    else
      IO.puts("Job #{job_id} finished with status #{job["status"]}")

      if result = Map.get(job, "result") do
        IO.puts(format_human(result))
      end
    end
  end

  defp print_manifest_validation({:ok, bundle}) do
    if interactive_output?([]) do
      UI.puts(UI.manifest_summary(bundle))
    else
      manifest = bundle.manifest

      output(%{
        ok: true,
        job_path: bundle.root_path,
        graph_id: manifest.graph_id,
        nodes: Enum.map(manifest.nodes, & &1.node_id),
        entrypoints: manifest.entrypoints
      })
    end
  end

  defp print_manifest_validation({:error, reason}), do: abort(reason)

  defp print_result({:ok, value}), do: output(value)
  defp print_result({:error, reason}), do: abort(reason)

  defp print_job_result({:ok, value}) do
    if UI.interactive?(), do: UI.puts(UI.job_details(value)), else: output(value)
  end

  defp print_job_result({:error, reason}), do: abort(reason)

  defp print_agents_result({:ok, agents}) do
    if UI.interactive?(), do: UI.puts(UI.agents_table(agents)), else: output(agents)
  end

  defp print_agents_result({:error, reason}), do: abort(reason)

  defp print_events_result({:ok, events}) do
    if UI.interactive?(), do: UI.puts(UI.events_table(events)), else: output(events)
  end

  defp print_events_result({:error, reason}), do: abort(reason)

  defp print_nodes(nodes) do
    if UI.interactive?(), do: UI.puts(UI.nodes_table(nodes)), else: output(nodes)
  end

  defp output(value, opts \\ []) do
    if Keyword.get(opts, :json, false) do
      IO.puts(Jason.encode!(value, pretty: true))
    else
      if UI.interactive?() and is_map(value) do
        UI.puts(UI.box("Output", inspect(value, pretty: true, limit: :infinity)))
      else
        IO.puts(format_human(value))
      end
    end
  end

  defp print_detached_run(job_id, opts) do
    if interactive_output?(opts) do
      UI.puts(UI.non_await_hint(job_id))
    else
      output(%{ok: true, job_id: job_id}, opts)
    end
  end

  defp format_human(value) when is_binary(value), do: value
  defp format_human(value), do: inspect(value, pretty: true, limit: :infinity)

  defp abort(reason) do
    if UI.interactive?() do
      UI.puts(UI.error_box(format_reason(reason)), :stderr)
    else
      IO.puts(:stderr, "error: #{format_reason(reason)}")
    end

    System.halt(1)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_list(reason), do: Enum.join(reason, "; ")
  defp format_reason(reason), do: inspect(reason, pretty: true)

  defp usage do
    maybe_print_banner(:inspect, "Command reference")

    if UI.interactive?() do
      UI.puts(UI.usage_screen())
    else
      IO.puts("""
      mirror_neuron server
      mirror_neuron validate <job-folder>
      mirror_neuron run <job-folder> [--json] [--timeout <ms>] [--no-await]
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
  end

  defp maybe_print_banner(command, subtitle) do
    if UI.interactive?() do
      UI.puts(UI.banner(command, subtitle))
    end
  end

  defp maybe_print_section(title, details \\ nil) do
    if UI.interactive?() do
      UI.puts(UI.section(title, details))
    end
  end

  defp maybe_print_run_submission(job_id, manifest, opts) do
    if interactive_output?(opts) do
      UI.puts(UI.run_started(job_id, manifest))
    end
  end

  defp interactive_output?(opts), do: not Keyword.get(opts, :json, false) and UI.interactive?()

  defp configure_logger(args) do
    if args != ["server"] do
      :logger.set_primary_config(:level, :warning)
      :logger.set_handler_config(:default, :level, :warning)
      Logger.configure(level: :warning)
      Logger.configure_backend(:default, level: :warning)
    end
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

        connect_configured_cluster_nodes(node_name)

        :ok
    end
  end

  defp connect_configured_cluster_nodes(self_node_name) do
    "MIRROR_NEURON_CLUSTER_NODES"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.reject(&(&1 == self_node_name))
    |> Enum.each(fn peer ->
      Node.connect(String.to_atom(peer))
    end)
  end
end
