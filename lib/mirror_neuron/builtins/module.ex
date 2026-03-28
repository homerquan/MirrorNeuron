defmodule MirrorNeuron.Builtins.Module do
  use MirrorNeuron.AgentTemplate

  @impl true
  def init(node) do
    with {:ok, delegate} <- resolve_delegate(node.config),
         {:ok, delegate_state} <- delegate.init(node) do
      {:ok, %{delegate: delegate, delegate_state: delegate_state, config: node.config}}
    end
  end

  @impl true
  def handle_message(message, state, context) do
    case state.delegate.handle_message(message, state.delegate_state, context) do
      {:ok, next_delegate_state, actions} ->
        {:ok, %{state | delegate_state: next_delegate_state}, actions}

      {:error, reason, next_delegate_state} ->
        {:error, reason, %{state | delegate_state: next_delegate_state}}
    end
  end

  @impl true
  def recover(state, context) do
    case state.delegate.recover(state.delegate_state, context) do
      {:ok, next_delegate_state, actions} ->
        {:ok, %{state | delegate_state: next_delegate_state}, actions}

      {:error, reason, next_delegate_state} ->
        {:error, reason, %{state | delegate_state: next_delegate_state}}
    end
  end

  @impl true
  def snapshot_state(%{delegate: delegate, delegate_state: delegate_state} = state) do
    %{
      "delegate" => Atom.to_string(delegate),
      "delegate_state" => delegate.snapshot_state(delegate_state),
      "config" => state.config
    }
  end

  @impl true
  def restore_state(%{"delegate" => delegate_name, "delegate_state" => snapshot, "config" => config}) do
    with {:ok, delegate} <- resolve_delegate(%{"module" => delegate_name}),
         {:ok, delegate_state} <- delegate.restore_state(snapshot) do
      {:ok, %{delegate: delegate, delegate_state: delegate_state, config: config}}
    end
  end

  def restore_state(snapshot), do: {:error, {:invalid_module_snapshot, snapshot}}

  @impl true
  def inspect_state(%{delegate: delegate, delegate_state: delegate_state, config: config}) do
    %{
      "delegate" => Atom.to_string(delegate),
      "delegate_state" => delegate.inspect_state(delegate_state),
      "config" => config
    }
  end

  defp resolve_delegate(config) do
    case Map.get(config, "module") || Map.get(config, :module) do
      nil ->
        {:error, "module agent requires config.module"}

      module when is_atom(module) ->
        {:ok, module}

      module_name when is_binary(module_name) ->
        try do
          {:ok,
           module_name
           |> String.split(".", trim: true)
           |> Enum.map(&String.to_atom/1)
           |> Module.concat()}
        rescue
          _ -> {:error, "invalid module agent #{inspect(module_name)}"}
        end

      other ->
        {:error, "invalid module agent #{inspect(other)}"}
    end
  end
end
