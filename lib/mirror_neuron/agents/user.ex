defmodule MirrorNeuron.Agents.User do
  @behaviour MirrorNeuron.Agents.Behaviour

  @impl true
  def init(_node), do: {:ok, %{status: "offline"}}

  @impl true
  def handle_message(%{type: "init"}, state, _context), do: {:ok, %{state | status: "online"}, []}
  def handle_message(_message, state, _context), do: {:ok, state, []}
end
