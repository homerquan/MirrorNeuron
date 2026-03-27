defmodule MirrorNeuron.Sandbox.OpenShellTest do
  use ExUnit.Case, async: true

  alias MirrorNeuron.Sandbox.OpenShell

  test "stages uploads and executes a command through the configured sandbox cli" do
    tmp_dir = Path.join(System.tmp_dir!(), "mirror_neuron_openshell_test_#{System.unique_integer([:positive])}")
    upload_dir = Path.join(tmp_dir, "bundle")
    remote_dir = Path.join(tmp_dir, "remote_job")
    fake_cli = Path.join(tmp_dir, "fake_openshell.sh")

    File.mkdir_p!(Path.join(upload_dir, "scripts"))

    File.write!(
      Path.join(upload_dir, "scripts/echo_input.py"),
      """
      import json
      import os
      from pathlib import Path

      payload = json.loads(Path(os.environ["MN_INPUT_FILE"]).read_text())
      print(json.dumps({"seen": payload["value"]}))
      """
    )

    File.write!(
      fake_cli,
      """
      #!/usr/bin/env bash
      set -euo pipefail

      upload_spec=""
      args=("$@")
      i=0
      while [ "$i" -lt "$#" ]; do
        current="${args[$i]}"
        if [ "$current" = "--upload" ]; then
          i=$((i + 1))
          upload_spec="${args[$i]}"
        elif [ "$current" = "--" ]; then
          break
        fi
        i=$((i + 1))
      done

      local_path="${upload_spec%%:*}"
      remote_path="${upload_spec#*:}"
      rm -rf "$remote_path"
      mkdir -p "$(dirname "$remote_path")"
      cp -R "$local_path" "$remote_path"

      shift $((i + 1))
      exec "$@"
      """
    )

    File.chmod!(fake_cli, 0o755)

    payload = %{"value" => "sandbox-ok"}

    config = %{
      "sandbox_cli" => fake_cli,
      "upload_path" => upload_dir,
      "upload_as" => "bundle",
      "sandbox_upload_path" => remote_dir,
      "workdir" => Path.join(remote_dir, "bundle"),
      "command" => ["python3", "scripts/echo_input.py"],
      "no_keep" => true,
      "no_auto_providers" => true,
      "tty" => false,
      "name_prefix" => "test"
    }

    assert {:ok, result} = OpenShell.run(payload, config, job_id: "job-1", agent_id: "agent-1")
    assert result["exit_code"] == 0
    assert result["stdout"] =~ "\"seen\": \"sandbox-ok\""

    File.rm_rf!(tmp_dir)
  end
end
