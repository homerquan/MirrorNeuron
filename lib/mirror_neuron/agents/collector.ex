defmodule MirrorNeuron.Agents.Collector do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(node) do
    {:ok,
     %{
       messages: [],
       config: node.config,
       complete_on_message: Map.get(node.config, "complete_on_message", true)
     }}
  end

  @impl true
  def handle_message(message, state, _context) do
    payload = Map.get(message, :payload) || Map.get(message, "payload")
    messages = state.messages ++ [payload]
    next_state = %{state | messages: messages}
    actions = [{:event, :collector_received, %{count: length(messages)}}]

    if state.complete_on_message do
      {:ok, next_state, actions ++ [{:complete_job, %{messages: messages, last_message: payload}}]}
    else
      {:ok, next_state, actions}
    end
  end
end
