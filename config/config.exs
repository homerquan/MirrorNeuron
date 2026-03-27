import Config

cluster_hosts =
  "MN_CLUSTER_NODES"
  |> System.get_env("")
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_atom/1)

topologies =
  if cluster_hosts == [] do
    []
  else
    [
      mirror_neuron: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: cluster_hosts]
      ]
    ]
  end

config :libcluster, topologies: topologies

config :mirror_neuron,
  supported_recovery_modes: ["local_restart", "cluster_recover", "manual_recover"],
  redis_url: System.get_env("MIRROR_NEURON_REDIS_URL", "redis://127.0.0.1:6379/0"),
  redis_namespace: System.get_env("MIRROR_NEURON_REDIS_NAMESPACE", "mirror_neuron")
