defmodule MirrorNeuron.Agents.Knowledge do
  @behaviour MirrorNeuron.Agents.Behaviour

  alias MirrorNeuron.ToolAdapter

  @impl true
  def init(node) do
    {:ok,
     %{
       config: node.config,
       knowledge_base: Map.get(node.config, "knowledge_base", %{})
     }}
  end

  @impl true
  def handle_message(%{type: "knowledge_request", payload: payload}, state, _context) do
    text = Map.get(payload, "text") || Map.get(payload, :text) || inspect(payload)

    answer =
      Map.get(state.knowledge_base, text) ||
        case ToolAdapter.invoke(Map.get(state.config, "tool", "template"), state.config, payload) do
          {:ok, value} -> value
          {:error, _reason} -> "No configured answer for #{text}"
        end

    response = %{"text" => text, "answer" => answer}
    {:ok, state, [{:emit, "knowledge_response", response}]}
  end

  def handle_message(_message, state, _context), do: {:ok, state, []}
end
