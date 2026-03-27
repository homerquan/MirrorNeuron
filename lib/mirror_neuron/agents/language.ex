defmodule MirrorNeuron.Agents.Language do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(_node), do: {:ok, %{memory: %{}}}

  @impl true
  def handle_message(message, state, _context) do
    payload = Map.get(message, :payload) || Map.get(message, "payload")
    {:ok, %{state | memory: Map.put(state.memory, inspect(payload), payload)}, []}
  end
end
