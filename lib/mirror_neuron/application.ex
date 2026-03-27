defmodule MirrorNeuron.Application do
  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      {Registry, keys: :duplicate, name: MirrorNeuron.Runtime.EventRegistry},
      %{
        id: MirrorNeuron.ClusterSupervisor,
        start: {Cluster.Supervisor, :start_link, [topologies, [name: MirrorNeuron.ClusterSupervisor]]}
      },
      MirrorNeuron.Redis,
      MirrorNeuron.DistributedRegistry,
      MirrorNeuron.Runtime.JobSupervisor,
      MirrorNeuron.Runtime.AgentSupervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MirrorNeuron.Supervisor)
  end
end
