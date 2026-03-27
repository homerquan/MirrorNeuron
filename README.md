# MirrorNeuron

MirrorNeuron is a new Elixir/BEAM implementation of the old Scala/Akka multi-agent runtime in this repository.

This version is aligned to the architecture in [SPEC.md](/Volumes/1TB/Personal_projects/MirrorNeuron/SPEC.md): manifest-driven jobs, supervised agent workers, explicit message envelopes, Redis-backed persistence, and a CLI entrypoint.

## What is included

- JSON manifest loader and validator
- Supervised per-job runtime tree
- Long-lived `GenServer` agent workers
- Explicit internal message envelopes and event bus
- Redis persistence for job state, agent snapshots, and event history
- BEAM cluster support using `libcluster` + `Horde`
- Optional OpenShell sandbox execution for `sandbox_worker` nodes only
- CLI commands for `validate`, `run`, `inspect`, `events`, `pause`, `resume`, `cancel`, and `send`
- Built-in agent types for both the new spec and the legacy conversation model:
  - `planner`, `relay`, `collector`, `sandbox_worker`
  - `conversation`, `visitor`, `helper`, `policy`, `knowledge`, `user`, `intention`, `language`

## Project layout

- [mix.exs](/Volumes/1TB/Personal_projects/MirrorNeuron/mix.exs)
- [lib/mirror_neuron.ex](/Volumes/1TB/Personal_projects/MirrorNeuron/lib/mirror_neuron.ex)
- [lib/mirror_neuron/manifest.ex](/Volumes/1TB/Personal_projects/MirrorNeuron/lib/mirror_neuron/manifest.ex)
- [lib/mirror_neuron/runtime/job_coordinator.ex](/Volumes/1TB/Personal_projects/MirrorNeuron/lib/mirror_neuron/runtime/job_coordinator.ex)
- [lib/mirror_neuron/runtime/agent_worker.ex](/Volumes/1TB/Personal_projects/MirrorNeuron/lib/mirror_neuron/runtime/agent_worker.ex)
- [lib/mirror_neuron/persistence/redis_store.ex](/Volumes/1TB/Personal_projects/MirrorNeuron/lib/mirror_neuron/persistence/redis_store.ex)

## Legacy mapping

The Scala actors in [legacy_in_scala_akka](/Volumes/1TB/Personal_projects/MirrorNeuron/legacy_in_scala_akka) were conversation-centric:

- `ConversationActor` routed between visitor and helper
- `VisitorActor` represented the external user
- `HelperActor` coordinated human/machine assistance
- `PolicyActor` and `KnowledgeActor` formed the machine decision path
- `IntentionActor` tracked a rolling intent window

The Elixir version keeps that message-driven shape, but moves it into a manifest-defined runtime:

- every node in the manifest becomes a supervised agent worker
- edges describe allowed message flow
- the job coordinator owns lifecycle and persistence
- the event bus captures observability and replayable history

## Example manifests

- [examples/research_flow_manifest.json](/Volumes/1TB/Personal_projects/MirrorNeuron/examples/research_flow_manifest.json)
- [examples/legacy_conversation_manifest.json](/Volumes/1TB/Personal_projects/MirrorNeuron/examples/legacy_conversation_manifest.json)
- [examples/openshell_worker_demo_manifest.json](/Volumes/1TB/Personal_projects/MirrorNeuron/examples/openshell_worker_demo_manifest.json)

## CLI

```bash
docker run --name mirror-neuron-redis -p 6379:6379 redis:7

mix deps.get
mix escript.build

./mirror_neuron validate examples/research_flow_manifest.json
./mirror_neuron run examples/research_flow_manifest.json
./mirror_neuron inspect nodes
```

MirrorNeuron stores jobs, agent snapshots, and event history in Redis under the `mirror_neuron:*` namespace by default.

## Worker sandboxes only

MirrorNeuron remains the BEAM orchestrator. OpenShell is only used for nodes whose `agent_type` is `sandbox_worker`.

- job coordination stays in BEAM
- inter-agent routing stays in BEAM
- supervision, pause/resume, persistence, and cluster control stay in BEAM
- only the actual worker command for `sandbox_worker` nodes is executed inside OpenShell

## OpenShell worker agents

For `sandbox_worker` nodes, the runtime shells out to the OpenShell CLI using the non-interactive command path:

```bash
openshell sandbox create --upload <local_dir>:<remote_dir> --no-keep -- <command>
```

Install OpenShell first:

```bash
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
```

If the binary is not on your default `PATH`, set:

```bash
export MIRROR_NEURON_OPENSHELL_BIN="/absolute/path/to/openshell"
```

Then start a gateway once on the host that will run sandboxes:

```bash
openshell gateway start
openshell status
```

Useful `sandbox_worker` config fields:

- `from`: sandbox image or community sandbox name, usually `base`
- `upload_path`: local file or directory to stage into the sandbox
- `upload_as`: target directory name inside the staged upload root
- `workdir`: working directory inside the sandbox
- `command`: shell string or argv list to run inside the sandbox
- `output_message_type`: message type emitted to downstream agents
- `policy`: optional OpenShell policy YAML path
- `remote`: optional remote gateway bootstrap target
- `providers`: optional OpenShell provider names

The runtime writes two files into every staged sandbox upload:

- `mirror_neuron_input.json`: the current message payload
- `mirror_neuron_context.json`: job and agent metadata

Inside the sandbox those are exposed through:

- `MN_INPUT_FILE`
- `MN_CONTEXT_FILE`
- `MN_WORKDIR`

## Running a clustered runtime

Each machine must:

- run Redis reachable by every node
- use the same Erlang cookie
- start the runtime with a node name
- point `MN_CLUSTER_NODES` at the full list of runtime nodes

Example for node 1:

```bash
export ERL_AFLAGS="-setcookie mirrorneuron"
export MIRROR_NEURON_REDIS_URL="redis://10.0.0.10:6379/0"
export MN_CLUSTER_NODES="mn1@10.0.0.11,mn2@10.0.0.12"

iex --name mn1@10.0.0.11 -S mix
```

Then inside `iex`:

```elixir
MirrorNeuron.CLI.main(["server"])
```

Example for node 2:

```bash
export ERL_AFLAGS="-setcookie mirrorneuron"
export MIRROR_NEURON_REDIS_URL="redis://10.0.0.10:6379/0"
export MN_CLUSTER_NODES="mn1@10.0.0.11,mn2@10.0.0.12"

iex --name mn2@10.0.0.12 -S mix
```

Then inside `iex`:

```elixir
MirrorNeuron.CLI.main(["server"])
```

Once the nodes see each other through EPMD, `Horde` can place jobs and agent workers across the cluster and agent-to-agent communication uses BEAM messaging between nodes.

To run one-shot CLI commands from any machine and have them join the cluster, set a temporary node name and cookie first:

```bash
export MIRROR_NEURON_NODE_NAME="cli@10.0.0.20"
export MIRROR_NEURON_COOKIE="mirrorneuron"
export MIRROR_NEURON_REDIS_URL="redis://10.0.0.10:6379/0"
export MN_CLUSTER_NODES="mn1@10.0.0.11,mn2@10.0.0.12"

./mirror_neuron inspect nodes
./mirror_neuron run examples/research_flow_manifest.json
```

## Demo: self-contained worker manifest

The demo manifest is fully self-contained. The JSON includes:

1. an inline shell worker command
2. an inline Python worker command
3. a collector sink that completes the job

Run it directly:

```bash
./mirror_neuron validate examples/openshell_worker_demo_manifest.json
./mirror_neuron run examples/openshell_worker_demo_manifest.json --json
```

Or use the helper script:

```bash
bash demo/openshell_pipeline/run_demo.sh
```

## Current scope

This is still an MVP runtime. It now supports BEAM clustering and Redis persistence, but it does not yet include a separate gateway API, advanced placement policies, or node-failure recovery orchestration beyond what BEAM/Horde provide.
