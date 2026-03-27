defmodule MirrorNeuron.Agents.Policy do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(node) do
    {:ok, %{approval_mode: Map.get(node.config, "approval_mode", "auto"), waiting: false}}
  end

  @impl true
  def handle_message(%{type: "policy_request", payload: payload}, state, _context) do
    {:ok, %{state | waiting: true}, [{:emit, "knowledge_request", payload}]}
  end

  def handle_message(%{type: "knowledge_response", payload: payload}, state, _context) do
    response = Map.put(payload, "approved", state.approval_mode == "auto")
    {:ok, %{state | waiting: false}, [{:emit, "policy_response", response}]}
  end

  def handle_message(_message, state, _context), do: {:ok, state, []}
end
