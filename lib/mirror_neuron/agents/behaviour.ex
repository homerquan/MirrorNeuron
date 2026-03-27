defmodule MirrorNeuron.Agents.Behaviour do
  @type action ::
          {:emit, String.t(), map()}
          | {:emit_to, String.t(), String.t(), map()}
          | {:event, atom(), map()}
          | {:checkpoint, map()}
          | {:complete_job, map()}

  @callback init(node :: map()) :: {:ok, map()} | {:error, term()}
  @callback handle_message(message :: map(), state :: map(), context :: map()) ::
              {:ok, map(), [action()]} | {:error, term(), map()}
end
