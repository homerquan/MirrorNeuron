defmodule MirrorNeuron.AgentRegistry do
  alias MirrorNeuron.Agents

  @agent_types %{
    "planner" => Agents.Planner,
    "relay" => Agents.Relay,
    "collector" => Agents.Collector,
    "sandbox_worker" => Agents.SandboxWorker,
    "conversation" => Agents.Conversation,
    "visitor" => Agents.Visitor,
    "helper" => Agents.Helper,
    "policy" => Agents.Policy,
    "knowledge" => Agents.Knowledge,
    "user" => Agents.User,
    "intention" => Agents.Intention,
    "language" => Agents.Language
  }

  def supported_types, do: Map.keys(@agent_types)
  def supported_type?(type), do: Map.has_key?(@agent_types, type)

  def fetch(type), do: Map.fetch(@agent_types, type)

  def fetch!(type) do
    case fetch(type) do
      {:ok, module} -> module
      :error -> raise ArgumentError, "unsupported agent_type #{inspect(type)}"
    end
  end
end
