defmodule MirrorNeuron.CLI do
  require Logger

  alias MirrorNeuron.CLI.Commands.Control
  alias MirrorNeuron.CLI.Commands.Inspect
  alias MirrorNeuron.CLI.Commands.Run
  alias MirrorNeuron.CLI.Commands.Server
  alias MirrorNeuron.CLI.Commands.Validate
  alias MirrorNeuron.CLI.Output
  alias MirrorNeuron.MonitorCLI

  def main(args) do
    prepared_args = prepare_environment(args)
    configure_logger(prepared_args)
    maybe_start_distribution()
    Application.ensure_all_started(:mirror_neuron)
    dispatch(prepared_args)
  end

  defp prepare_environment(["monitor" | rest]),
    do: ["monitor" | MonitorCLI.prepare_environment(rest)]

  defp prepare_environment(args), do: args

  defp dispatch(["server"]), do: Server.run()
  defp dispatch(["validate", job_path]), do: Validate.run(job_path)
  defp dispatch(["run", job_path | rest]), do: Run.run(job_path, Run.parse_options(rest))
  defp dispatch(["monitor" | rest]), do: MonitorCLI.main(rest)
  defp dispatch(["inspect", "job", job_id]), do: Inspect.job(job_id)
  defp dispatch(["inspect", "agents", job_id]), do: Inspect.agents(job_id)
  defp dispatch(["inspect", "nodes"]), do: Inspect.nodes()
  defp dispatch(["events", job_id]), do: Inspect.events(job_id)
  defp dispatch(["pause", job_id]), do: Control.pause(job_id)
  defp dispatch(["resume", job_id]), do: Control.resume(job_id)
  defp dispatch(["cancel", job_id]), do: Control.cancel(job_id)

  defp dispatch(["send", job_id, agent_id, message_json]),
    do: Control.send_message(job_id, agent_id, message_json)

  defp dispatch(_args), do: Output.usage()

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
