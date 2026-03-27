defmodule MirrorNeuron.Agents.Helper do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(node), do: {:ok, %{mode: Map.get(node.config, "mode", "semi"), last_prompt: nil}}

  @impl true
  def handle_message(%{type: "helper_message_request", payload: payload}, state, _context) do
    actions = [
      {:event, :helper_consulting_policy, %{mode: state.mode}},
      {:emit, "policy_request", payload}
    ]

    {:ok, %{state | last_prompt: payload}, actions}
  end

  def handle_message(%{type: "policy_response", payload: payload}, state, _context) do
    {:ok, state, [{:emit, "helper_message", payload}]}
  end

  def handle_message(_message, state, _context), do: {:ok, state, []}
end
