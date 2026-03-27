defmodule MirrorNeuron.RuntimeTest do
  use ExUnit.Case

  alias MirrorNeuron.Persistence.RedisStore

  setup do
    Application.ensure_all_started(:mirror_neuron)

    case Redix.command(MirrorNeuron.Redis.Connection, ["PING"]) do
      {:ok, "PONG"} ->
        :ok

      _ ->
        raise "Redis must be running for runtime tests"
    end
  end

  test "runs a manifest to completion and persists job state" do
    manifest = %{
      "manifest_version" => "1.0",
      "graph_id" => "research_test",
      "entrypoints" => ["planner"],
      "initial_inputs" => %{
        "planner" => [%{"text" => "Summarize charging adoption"}]
      },
      "nodes" => [
        %{"node_id" => "planner", "agent_type" => "planner", "role" => "root_coordinator"},
        %{"node_id" => "relay", "agent_type" => "relay"},
        %{"node_id" => "sink", "agent_type" => "collector", "config" => %{"complete_on_message" => true}}
      ],
      "edges" => [
        %{"from_node" => "planner", "to_node" => "relay", "message_type" => "research_request"},
        %{"from_node" => "relay", "to_node" => "sink", "message_type" => "research_request"}
      ],
      "policies" => %{"recovery_mode" => "local_restart"}
    }

    assert {:ok, job_id, job} = MirrorNeuron.run_manifest(manifest, await: true, timeout: 2_000)
    assert job_id =~ "research_test-"
    assert job["status"] == "completed"

    assert {:ok, persisted_job} = MirrorNeuron.inspect_job(job_id)
    assert persisted_job["status"] == "completed"

    assert {:ok, agents} = MirrorNeuron.inspect_agents(job_id)
    assert Enum.any?(agents, &(&1["agent_id"] == "planner"))
    assert Enum.any?(agents, &(&1["agent_id"] == "sink"))

    assert {:ok, events} = MirrorNeuron.events(job_id)
    assert Enum.any?(events, &(&1["type"] == "job_completed"))

    RedisStore.delete_job(job_id)
  end

  test "queues messages while paused and completes after resume" do
    manifest = %{
      "manifest_version" => "1.0",
      "graph_id" => "pause_resume_test",
      "nodes" => [
        %{"node_id" => "root", "agent_type" => "user", "role" => "root_coordinator"},
        %{"node_id" => "sink", "agent_type" => "collector", "config" => %{"complete_on_message" => true}}
      ],
      "edges" => [],
      "policies" => %{"recovery_mode" => "local_restart"}
    }

    assert {:ok, job_id} = MirrorNeuron.run_manifest(manifest, await: false)
    wait_until(fn -> running_status?(job_id) end)

    assert {:ok, "paused"} = MirrorNeuron.pause(job_id)

    assert {:ok, "delivered"} =
             MirrorNeuron.send_message(job_id, "sink", %{
               "type" => "manual_result",
               "payload" => %{"text" => "approved while paused"}
             })

    assert {:ok, "resumed"} = MirrorNeuron.resume(job_id)
    assert {:ok, job} = MirrorNeuron.wait_for_job(job_id, 2_000)
    assert job["status"] == "completed"

    RedisStore.delete_job(job_id)
  end

  defp running_status?(job_id) do
    case MirrorNeuron.inspect_job(job_id) do
      {:ok, %{"status" => "running"}} -> true
      _ -> false
    end
  end

  defp wait_until(fun, timeout \\ 1_000) do
    started_at = System.monotonic_time(:millisecond)
    do_wait_until(fun, started_at, timeout)
  end

  defp do_wait_until(fun, started_at, timeout) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) - started_at > timeout do
        flunk("condition was not met within #{timeout}ms")
      else
        Process.sleep(20)
        do_wait_until(fun, started_at, timeout)
      end
    end
  end
end
