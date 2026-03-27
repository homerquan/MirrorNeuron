defmodule MirrorNeuron.Cluster.Manager do
  def nodes do
    connected = Node.list()

    [Node.self() | connected]
    |> Enum.uniq()
    |> Enum.map(fn node ->
      %{
        name: to_string(node),
        connected_nodes: Enum.map(connected, &to_string/1),
        self?: node == Node.self(),
        scheduler_hint: if(node == Node.self(), do: "cluster_member", else: "remote_member")
      }
    end)
  end
end
