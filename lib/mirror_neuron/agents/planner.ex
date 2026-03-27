defmodule MirrorNeuron.Agents.Planner do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(node), do: {:ok, %{node_id: node.node_id, role: node.role}}

  @impl true
  def handle_message(%{type: "init", payload: payload}, state, _context) do
    actions = [
      {:event, :planner_initialized, %{payload: payload}},
      {:emit, "research_request", payload}
    ]

    {:ok, Map.put(state, :last_payload, payload), actions}
  end

  def handle_message(message, state, _context) do
    actions = [
      {:event, :planner_forwarded, %{message_type: message_type(message)}},
      {:emit, "research_request", payload(message)}
    ]

    {:ok, Map.put(state, :last_payload, payload(message)), actions}
  end

  defp payload(message), do: Map.get(message, :payload) || Map.get(message, "payload")
  defp message_type(message), do: Map.get(message, :type) || Map.get(message, "type")
end
