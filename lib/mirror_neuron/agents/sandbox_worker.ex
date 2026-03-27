defmodule MirrorNeuron.Agents.SandboxWorker do
  @behaviour MirrorNeuron.Agents.Behaviour

  alias MirrorNeuron.Sandbox.OpenShell

  @impl true
  def init(node) do
    {:ok,
     %{
       config: node.config,
       runs: 0,
       last_result: nil,
       last_error: nil
     }}
  end

  @impl true
  def handle_message(message, state, context) do
    payload = Map.get(message, :payload) || Map.get(message, "payload") || %{}

    case OpenShell.run(payload, state.config, job_id: context.job_id, agent_id: context.node.node_id) do
      {:ok, result} ->
        output_message_type = Map.get(state.config, "output_message_type", "sandbox_result")

        output_payload = %{
          "agent_id" => context.node.node_id,
          "sandbox" => result,
          "input" => payload
        }

        actions =
          [
            {:event, :sandbox_job_completed, %{"sandbox_name" => result["sandbox_name"], "exit_code" => result["exit_code"]}},
            {:emit, output_message_type, output_payload}
          ] ++ maybe_complete(state.config, output_payload)

        {:ok, %{state | runs: state.runs + 1, last_result: result, last_error: nil}, actions}

      {:error, reason} ->
        {:error, reason, %{state | runs: state.runs + 1, last_error: inspect(reason)}}
    end
  end

  defp maybe_complete(config, payload) do
    if Map.get(config, "complete_job", false) do
      [{:complete_job, payload}]
    else
      []
    end
  end
end
