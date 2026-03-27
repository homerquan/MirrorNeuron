defmodule MirrorNeuron.Runtime.AgentWorker do
  use GenServer

  alias MirrorNeuron.AgentRegistry
  alias MirrorNeuron.Persistence.RedisStore
  alias MirrorNeuron.Runtime
  alias MirrorNeuron.Runtime.Naming

  def child_spec({job_id, node, edges, coordinator}) do
    %{
      id: {:agent_worker, job_id, node.node_id},
      start: {__MODULE__, :start_link, [{job_id, node, edges, coordinator}]},
      restart: :transient,
      type: :worker
    }
  end

  def start_link({job_id, node, edges, coordinator}) do
    GenServer.start_link(__MODULE__, {job_id, node, edges, coordinator}, name: Naming.via_agent(job_id, node.node_id))
  end

  @impl true
  def init({job_id, node, edges, coordinator}) do
    module = AgentRegistry.fetch!(node.agent_type)
    outbound_edges = Enum.filter(edges, &(&1.from_node == node.node_id))
    inbound_edges = Enum.filter(edges, &(&1.to_node == node.node_id))

    case module.init(node) do
      {:ok, local_state} ->
        state = %{
          job_id: job_id,
          node: node,
          module: module,
          local_state: local_state,
          outbound_edges: outbound_edges,
          inbound_edges: inbound_edges,
          coordinator: coordinator,
          paused?: false,
          pending: :queue.new(),
          mailbox_depth: 0,
          processed_messages: 0
        }

        persist_snapshot(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast(:pause, state), do: {:noreply, %{state | paused?: true}}

  def handle_cast(:resume, state) do
    next_state = %{state | paused?: false}
    {:noreply, drain_pending(next_state)}
  end

  def handle_cast(:cancel, state), do: {:stop, :normal, state}

  def handle_cast({:deliver, message}, %{paused?: true} = state) do
    queued = :queue.in(message, state.pending)
    next_state = %{state | pending: queued, mailbox_depth: state.mailbox_depth + 1}
    persist_snapshot(next_state)
    {:noreply, next_state}
  end

  def handle_cast({:deliver, message}, state) do
    {:noreply, process_message(message, state)}
  end

  defp drain_pending(%{paused?: true} = state), do: state

  defp drain_pending(state) do
    case :queue.out(state.pending) do
      {{:value, message}, remaining} ->
        drained_state =
          state
          |> Map.put(:pending, remaining)
          |> Map.put(:mailbox_depth, max(state.mailbox_depth - 1, 0))
          |> process_message(message)

        drain_pending(drained_state)

      {:empty, _queue} ->
        persist_snapshot(state)
        state
    end
  end

  defp process_message(message, state) do
    context = %{
      job_id: state.job_id,
      node: state.node,
      outbound_edges: state.outbound_edges,
      inbound_edges: state.inbound_edges
    }

    send(state.coordinator, {:agent_event, state.node.node_id, :agent_message_received, summarize_message(message)})

    case state.module.handle_message(message, state.local_state, context) do
      {:ok, new_local_state, actions} ->
        next_state = %{
          state
          | local_state: new_local_state,
            processed_messages: state.processed_messages + 1
        }

        Enum.each(actions, &execute_action(&1, message, next_state))
        persist_snapshot(next_state)
        next_state

      {:error, reason, new_local_state} ->
        failed_state = %{state | local_state: new_local_state}
        persist_snapshot(failed_state)
        send(state.coordinator, {:agent_failed, state.node.node_id, reason})
        failed_state
    end
  end

  defp execute_action({:emit, message_type, payload}, incoming, state) do
    matching_edges =
      Enum.filter(state.outbound_edges, fn edge ->
        edge.message_type == message_type or edge.message_type == "*"
      end)

    Enum.each(matching_edges, fn edge ->
      envelope = %{
        message_id: unique_id(),
        from: state.node.node_id,
        to: edge.to_node,
        type: message_type,
        payload: payload,
        correlation_id: Map.get(incoming, :correlation_id) || Map.get(incoming, "correlation_id") || unique_id(),
        causation_id: Map.get(incoming, :message_id) || Map.get(incoming, "message_id"),
        timestamp: Runtime.timestamp()
      }

      Runtime.deliver(state.job_id, edge.to_node, envelope)
    end)
  end

  defp execute_action({:emit_to, to_node, message_type, payload}, incoming, state) do
    envelope = %{
      message_id: unique_id(),
      from: state.node.node_id,
      to: to_node,
      type: message_type,
      payload: payload,
      correlation_id: Map.get(incoming, :correlation_id) || Map.get(incoming, "correlation_id") || unique_id(),
      causation_id: Map.get(incoming, :message_id) || Map.get(incoming, "message_id"),
      timestamp: Runtime.timestamp()
    }

    Runtime.deliver(state.job_id, to_node, envelope)
  end

  defp execute_action({:event, event_type, payload}, _incoming, state) do
    send(state.coordinator, {:agent_event, state.node.node_id, event_type, payload})
  end

  defp execute_action({:checkpoint, snapshot}, _incoming, state) do
    send(state.coordinator, {:agent_checkpoint, state.node.node_id, snapshot})
  end

  defp execute_action({:complete_job, result}, _incoming, state) do
    send(state.coordinator, {:agent_completed_job, state.node.node_id, result})
  end

  defp persist_snapshot(state) do
    snapshot = %{
      agent_id: state.node.node_id,
      node_id: state.node.node_id,
      agent_type: state.node.agent_type,
      role: state.node.role,
      current_state: stringify_local_state(state.local_state),
      mailbox_depth: state.mailbox_depth,
      processed_messages: state.processed_messages,
      assigned_node: to_string(Node.self()),
      parent_job_id: state.job_id,
      metadata: %{
        paused: state.paused?,
        outbound_edges: Enum.map(state.outbound_edges, & &1.to_node)
      }
    }

    RedisStore.persist_agent(state.job_id, state.node.node_id, snapshot)
    send(state.coordinator, {:agent_checkpoint, state.node.node_id, snapshot})
  end

  defp summarize_message(message) do
    %{
      from: Map.get(message, :from) || Map.get(message, "from"),
      to: Map.get(message, :to) || Map.get(message, "to"),
      type: Map.get(message, :type) || Map.get(message, "type")
    }
  end

  defp stringify_local_state(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key
      {key, stringify_local_state(value)}
    end)
  end

  defp stringify_local_state(list) when is_list(list), do: Enum.map(list, &stringify_local_state/1)
  defp stringify_local_state(value), do: value

  defp unique_id do
    6
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
