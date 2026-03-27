defmodule MirrorNeuron.Agents.Relay do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(node), do: {:ok, %{node_id: node.node_id, forwarded: 0, config: node.config}}

  @impl true
  def handle_message(message, state, _context) do
    emit_type = Map.get(state.config, "emit_type", Map.get(message, :type) || Map.get(message, "type"))
    payload = Map.get(message, :payload) || Map.get(message, "payload")

    {:ok, %{state | forwarded: state.forwarded + 1}, [{:emit, emit_type, payload}]}
  end
end
