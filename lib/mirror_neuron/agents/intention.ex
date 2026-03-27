defmodule MirrorNeuron.Agents.Intention do
  @behaviour MirrorNeuron.Agents.Behaviour

  @window_size 3

  @impl true
  def init(_node), do: {:ok, %{window: []}}

  @impl true
  def handle_message(message, state, _context) do
    payload = Map.get(message, :payload) || Map.get(message, "payload") || %{}
    intention = Map.get(payload, "intention") || Map.get(payload, :intention)

    if is_binary(intention) and intention != "" do
      window = Enum.take(state.window ++ [intention], -@window_size)
      {:ok, %{state | window: window}, [{:event, :intention_updated, %{intentions: window}}]}
    else
      {:ok, state, []}
    end
  end
end
