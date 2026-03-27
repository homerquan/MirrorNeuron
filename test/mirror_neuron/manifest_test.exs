defmodule MirrorNeuron.ManifestTest do
  use ExUnit.Case, async: true

  alias MirrorNeuron.Manifest

  test "validates a well-formed manifest" do
    manifest = %{
      "manifest_version" => "1.0",
      "graph_id" => "simple",
      "entrypoints" => ["planner"],
      "nodes" => [
        %{"node_id" => "planner", "agent_type" => "planner", "role" => "root_coordinator"},
        %{"node_id" => "sink", "agent_type" => "collector"}
      ],
      "edges" => [
        %{"from_node" => "planner", "to_node" => "sink", "message_type" => "research_request"}
      ],
      "policies" => %{"recovery_mode" => "local_restart"}
    }

    assert {:ok, normalized} = Manifest.load(manifest)
    assert normalized.graph_id == "simple"
    assert normalized.entrypoints == ["planner"]
  end

  test "rejects duplicate nodes and missing edge references" do
    manifest = %{
      "manifest_version" => "1.0",
      "graph_id" => "invalid",
      "entrypoints" => ["planner"],
      "nodes" => [
        %{"node_id" => "planner", "agent_type" => "planner", "role" => "root_coordinator"},
        %{"node_id" => "planner", "agent_type" => "collector"}
      ],
      "edges" => [
        %{"from_node" => "planner", "to_node" => "missing", "message_type" => "research_request"}
      ],
      "policies" => %{"recovery_mode" => "local_restart"}
    }

    assert {:error, errors} = Manifest.load(manifest)
    assert Enum.any?(errors, &String.contains?(&1, "duplicate node_id planner"))
    assert Enum.any?(errors, &String.contains?(&1, "missing to_node missing"))
  end
end
