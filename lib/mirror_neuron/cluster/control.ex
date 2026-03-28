defmodule MirrorNeuron.Cluster.Control do
  alias MirrorNeuron.Execution.LeaseManager

  @rpc_timeout 15_000
  @probe_timeout 5_000

  def call(module, function, args, timeout \\ @rpc_timeout, connected_nodes \\ Node.list()) do
    case runtime_nodes(connected_nodes) do
      [node | _rest] ->
        rpc_adapter().call(node, module, function, args, timeout)

      [] ->
        {:error, "no runtime nodes available in the connected cluster"}
    end
  end

  def runtime_nodes(connected_nodes \\ Node.list()) do
    configured_nodes()
    |> Enum.filter(&(&1 in connected_nodes))
    |> Enum.filter(&runtime_node?/1)
  end

  defp configured_nodes do
    "MIRROR_NEURON_CLUSTER_NODES"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_atom/1)
    |> Enum.reject(&(&1 == Node.self()))
  end

  defp runtime_node?(node) do
    case rpc_adapter().call(node, LeaseManager, :stats, [], @probe_timeout) do
      {:badrpc, _reason} -> false
      stats when is_map(stats) -> true
      _other -> false
    end
  end

  defp rpc_adapter do
    Application.get_env(:mirror_neuron, :rpc_adapter, MirrorNeuron.RPC)
  end
end
