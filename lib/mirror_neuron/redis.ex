defmodule MirrorNeuron.Redis do
  use Supervisor

  def start_link(_arg) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    redis_url = Application.fetch_env!(:mirror_neuron, :redis_url)

    children = [
      %{
        id: :redix,
        start: {Redix, :start_link, [redis_url, [name: __MODULE__.Connection]]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
