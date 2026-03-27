defmodule MirrorNeuron.Agents.Conversation do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(_node), do: {:ok, %{turns: []}}

  @impl true
  def handle_message(message, state, _context) do
    type = Map.get(message, :type) || Map.get(message, "type")
    payload = Map.get(message, :payload) || Map.get(message, "payload")
    turns = state.turns ++ [%{type: type, payload: payload}]

    actions =
      case type do
        "visitor_message" -> [{:emit, "helper_message_request", payload}]
        "helper_message" -> [{:emit, "conversation_reply", payload}]
        _ -> [{:event, :conversation_ignored, %{type: type}}]
      end

    {:ok, %{state | turns: turns}, actions}
  end
end
