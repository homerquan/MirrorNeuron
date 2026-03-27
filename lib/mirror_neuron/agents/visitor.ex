defmodule MirrorNeuron.Agents.Visitor do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(node), do: {:ok, %{conversation: node.role, last_reply: nil}}

  @impl true
  def handle_message(%{type: "init", payload: payload}, state, _context) do
    {:ok, state, [{:emit, "visitor_message", payload}]}
  end

  def handle_message(%{type: "helper_message", payload: payload}, state, _context) do
    {:ok, %{state | last_reply: payload}, [{:event, :visitor_received_reply, payload}]}
  end

  def handle_message(message, state, _context) do
    {:ok, state, [{:event, :visitor_received_message, %{type: Map.get(message, :type) || Map.get(message, "type")}}]}
  end
end
