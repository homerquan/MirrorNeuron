# SPEC.md

## Project

**Project name:** MirrorNeuron

MirrorNeuron is a BEAM-based multi-agent runtime built in Ellang/Elixir for long-lived, distributed agent execution. Its primary input is a JSON manifest that describes the multi-agent layout as a graph. MirrorNeuron can run directly through a CLI and can also serve as an execution backend for LangGraph through a dedicated adapter layer.

---

## 1. Purpose

MirrorNeuron provides a production-oriented runtime for AI agents using the BEAM ecosystem.

The runtime treats agents as long-lived, message-driven processes rather than short-lived function calls. It supports durable execution, fault isolation, inter-agent communication, cluster-aware scheduling, and integration with external orchestration frameworks such as LangGraph.

Unlike frameworks that define agent topology mainly in code, MirrorNeuron should accept a **graph manifest in JSON** as its execution input. That manifest describes what agents exist, how they are connected, what roles they play, and how messages or tasks flow between them.

MirrorNeuron should also be directly usable from a terminal through a CLI, so developers can run, inspect, pause, resume, and debug agent graphs without first embedding the runtime inside another framework.

---

## 2. Goals

### Primary goals

* Support long-lived jobs and agents
* Run across multiple machines in a BEAM cluster
* Accept a JSON graph manifest as the primary runtime input
* Build and execute multi-agent topologies from that manifest
* Integrate cleanly with LangGraph-based orchestration
* Expose a first-class CLI for direct execution and operations
* Isolate failures using supervision trees
* Support asynchronous message-passing between agents
* Make agent state observable and inspectable
* Allow workload placement, restart, and migration policies

### Secondary goals

* Durable job recovery after node failure
* Human-in-the-loop pause and resume
* Streaming events for monitoring and debugging
* Support tool wrappers and external service adapters
* Permit future addition of persistent memory backends
* Allow manifest validation and dry-run topology inspection

### Non-goals (v1)

* Training LLMs
* Replacing LangGraph
* Full workflow authoring UI
* Full vector database implementation
* Cross-region consensus-heavy distributed database features
* A complete graphical manifest editor

---

## 3. Design Principles

* **Agents are processes.** Every live agent instance should map to an Elixir/Erlang process abstraction.
* **The manifest is the contract.** Agent topology should be described declaratively in JSON rather than hidden in ad hoc runtime code.
* **Messages are the runtime protocol.** Communication should happen through explicit internal message envelopes.
* **Let it crash.** Fault recovery should rely on supervision rather than defensive local complexity.
* **CLI-first operability.** A developer should be able to run and manage the system directly from the terminal.
* **LangGraph-compatible, not LangGraph-dependent.** The runtime should be usable on its own, but easy to attach to Python/LangGraph systems.
* **Observable by default.** Events, state transitions, and failures should be visible.
* **Runtime over prompting.** The project focuses on execution, lifecycle, reliability, and coordination rather than LLM reasoning itself.

---

## 4. Core User Stories

### Runtime operator

* As an operator, I want agents to survive worker process crashes through supervised restart.
* As an operator, I want workloads to continue running on a healthy node if one machine dies.
* As an operator, I want to inspect which agents are running, where they are running, and what state they are in.
* As an operator, I want to submit and control jobs from the CLI.

### AI application developer

* As a developer, I want to define an agent system as a JSON graph manifest.
* As a developer, I want to submit a long-lived job that may take minutes, hours, or days.
* As a developer, I want an agent to wait for external events and resume later.
* As a developer, I want multiple agents to collaborate through messages.
* As a developer, I want to run the same manifest either directly through the CLI or via LangGraph integration.

### LangGraph integrator

* As a LangGraph user, I want a node to dispatch work to MirrorNeuron and get back status, events, and final results.
* As a LangGraph user, I want to offload long-lived and failure-sensitive execution into MirrorNeuron while keeping planning logic in LangGraph.
* As a LangGraph user, I want to generate or transform a graph spec in Python and submit it as a manifest to MirrorNeuron.

---

## 5. System Overview

The system consists of seven main layers:

1. **Manifest Layer**

   * JSON schema for agent graph layout
   * topology validation
   * manifest parsing and normalization
   * versioned manifest format

2. **Cluster Layer**

   * node discovery
   * cluster membership
   * distributed registry
   * remote process communication

3. **Runtime Layer**

   * agent lifecycle management
   * job scheduling
   * supervision trees
   * placement policies

4. **Execution Layer**

   * agent workers
   * tool workers
   * event handlers
   * pause/resume handling

5. **Persistence Layer**

   * job metadata store
   * checkpoint store
   * event log
   * optional memory adapters

6. **API / Integration Layer**

   * HTTP/gRPC API
   * message ingress API
   * LangGraph adapter protocol
   * CLI command surface

7. **Observability Layer**

   * structured logs
   * metrics
   * trace/event streaming
   * runtime inspection endpoints

---

## 6. Conceptual Model

### Manifest

A JSON document that describes the multi-agent layout to run.

The manifest represents a graph with nodes and edges, plus runtime metadata.

Attributes:

* manifest_version
* graph_id
* job_name
* metadata
* nodes
* edges
* policies
* entrypoints
* initial_inputs

### Agent Node

A declarative description of one agent in the graph.

Attributes:

* node_id
* agent_type
* role
* config
* tool_bindings
* retry_policy
* checkpoint_policy
* spawn_policy

### Edge

A declarative connection between two nodes.

Attributes:

* edge_id
* from_node
* to_node
* message_type
* routing_mode
* conditions

### Agent

A long-lived, message-driven runtime process created from an Agent Node.

Attributes:

* agent_id
* node_id
* agent_type
* current_state
* mailbox_depth
* assigned_node
* parent_job_id
* metadata

### Job

A durable unit of work created from a manifest.

Attributes:

* job_id
* graph_id
* manifest_ref
* status
* submitted_at
* updated_at
* root_agent_ids
* placement_policy
* recovery_policy
* result_ref

### Message

An explicit communication envelope between agents or between external systems and the runtime.

Attributes:

* message_id
* from
* to
* type
* payload
* correlation_id
* timestamp
* reply_to
* causation_id

### Tool Invocation

A runtime-managed execution of an external tool, service, or callback.

Attributes:

* invocation_id
* tool_name
* request_payload
* timeout_ms
* retry_policy
* status
* result

### Checkpoint

A serialized runtime snapshot sufficient to resume a long-lived job or recover state after failure.

---

## 7. Manifest Format

MirrorNeuron uses a JSON graph manifest as the primary execution input.

### Manifest requirements

* machine-readable JSON
* explicit node and edge definitions
* stable schema versioning
* validation before execution
* support for runtime policy blocks
* support for future extension without breaking old manifests

### Conceptual structure

```json
{
  "manifest_version": "1.0",
  "graph_id": "research_flow_v1",
  "job_name": "market-analysis",
  "nodes": [
    {
      "node_id": "planner",
      "agent_type": "planner",
      "role": "root_coordinator"
    },
    {
      "node_id": "retriever",
      "agent_type": "retrieval_agent"
    },
    {
      "node_id": "reviewer",
      "agent_type": "review_agent"
    }
  ],
  "edges": [
    {
      "from_node": "planner",
      "to_node": "retriever",
      "message_type": "research_request"
    },
    {
      "from_node": "retriever",
      "to_node": "reviewer",
      "message_type": "draft_result"
    }
  ],
  "policies": {
    "recovery_mode": "cluster_recover"
  }
}
```

### Manifest semantics

* nodes define what agents exist
* edges define who can communicate with whom
* policies define scheduling, restart, and checkpointing behavior
* entrypoints define where execution begins
* initial_inputs provide startup payloads

### Validation behavior

The runtime should reject invalid manifests before scheduling any work.

Validation should check:

* schema correctness
* duplicate node IDs
* missing references in edges
* unsupported agent types
* invalid policy combinations
* unreachable or malformed entrypoints

---

## 8. High-Level Architecture

```text
JSON Manifest / LangGraph Adapter / CLI Input
                    |
                    v
            Manifest Loader + Validator
                    |
                    v
             Runtime Coordinator
                    |
      -----------------------------------
      |                |                |
  Job Registry     Scheduler        Event Bus
      |                |                |
      -----------------------------------
                    |
      Distributed Job Supervisors
                    |
      Agent Processes across BEAM Cluster
                    |
     Tool Adapters / External Services / Human Inputs
```

---

## 9. Runtime Components

### 9.1 Manifest Loader

Responsibilities:

* load manifest from file, stdin, or API payload
* normalize manifest structure
* validate schema and references
* produce internal runtime plan

### 9.2 Cluster Manager

Responsibilities:

* manage node membership
* detect joins/leaves
* support cluster formation in local and production environments
* expose cluster health

Candidate technologies:

* libcluster
* Erlang distribution primitives
* Horde / Swarm / Phoenix.PubSub-based patterns, subject to evaluation

### 9.3 Distributed Registry

Responsibilities:

* locate job coordinators and agent processes
* resolve agent_id to pid/node
* support failover-friendly lookup

### 9.4 Job Supervisor Tree

Responsibilities:

* create one supervision subtree per job
* host root job coordinator
* host child agent supervisors
* encapsulate failure boundaries

### 9.5 Job Coordinator

Responsibilities:

* own durable job state machine
* materialize runtime topology from manifest
* coordinate child agent creation
* manage pause, resume, cancel, timeout, completion
* emit job lifecycle events

### 9.6 Agent Worker

Responsibilities:

* process inbound messages
* maintain local runtime state
* call tools through tool adapters
* collaborate with peer agents
* checkpoint when required

### 9.7 Scheduler / Placement Engine

Responsibilities:

* decide which node hosts new jobs or agents
* enforce placement policy
* avoid overloaded nodes
* support future affinity rules such as GPU, locality, or compliance zone

### 9.8 Tool Adapter Layer

Responsibilities:

* wrap external Python/HTTP/gRPC tools
* isolate side effects from the core runtime
* handle timeouts, retry, circuit breaker policies

### 9.9 Event Bus

Responsibilities:

* publish runtime events internally and externally
* stream updates to LangGraph, CLI consumers, and observability consumers

### 9.10 Persistence Adapter

Responsibilities:

* store job metadata, checkpoints, event history
* provide pluggable backend abstraction

### 9.11 CLI Frontend

Responsibilities:

* run manifests directly
* inspect jobs, agents, and nodes
* pause, resume, and cancel jobs
* stream logs and events for debugging
* validate manifests without execution

### 9.12 LangGraph Adapter

Responsibilities:

* accept graph or plan output from LangGraph
* transform it into a MirrorNeuron-compatible manifest when needed
* submit and monitor jobs
* translate runtime events back into LangGraph-facing state updates

---

## 10. Job Lifecycle

### States

* pending
* validated
* scheduled
* starting
* running
* waiting
* paused
* resuming
* completed
* failed
* cancelled

### Lifecycle outline

1. Client submits a manifest through CLI, API, or LangGraph adapter
2. Runtime validates manifest and policies
3. Scheduler chooses node placement
4. Job coordinator starts under supervision
5. Runtime materializes agents from manifest nodes
6. Agents exchange messages and call tools according to edge rules
7. Job may enter waiting or paused state for external input
8. Job emits final result or failure reason
9. Job metadata and event history remain queryable

---

## 11. Long-Lived Job Support

The runtime must support workloads that remain alive for extended periods, including jobs that:

* wait on external APIs
* pause for human approval
* resume on message arrival
* span multiple days
* survive deploys and node restarts

### Required capabilities

* durable job metadata
* checkpointing strategy
* time-based wake-up or timeout support
* event-driven resume
* explicit pause/resume/cancel commands

### Checkpoint strategy (v1)

Checkpoint at safe boundaries rather than every message:

* after agent state transitions
* before and after tool invocations when needed
* before entering waiting/paused state
* before final completion

---

## 12. Multi-Machine / Cluster Support

The runtime must support execution over multiple machines using BEAM clustering.

### Required capabilities

* node discovery
* distributed registry
* remote process messaging
* job placement across nodes
* recovery after node disappearance

### Expected behavior

* if a worker process crashes, supervisor restarts it locally when possible
* if a node crashes, the system reconstitutes job ownership based on persisted job metadata and recovery policy
* cluster membership changes should not require full system restart

### Recovery modes

* **local_restart**: restart only on the same node if available
* **cluster_recover**: recover on another healthy node
* **manual_recover**: hold state for operator intervention

---

## 13. CLI Interface

The project must ship with a first-class CLI so developers can use MirrorNeuron directly without LangGraph.

### CLI goals

* make local experimentation easy
* make operational control explicit
* support scripting and automation
* expose observability without needing a UI

### Core commands

#### `mirror_neuron run <manifest.json>`

Run a manifest as a new job.

#### `mirror_neuron validate <manifest.json>`

Validate manifest structure and references without executing it.

#### `mirror_neuron inspect job <job_id>`

Return job metadata, state, and summary.

#### `mirror_neuron inspect agents <job_id>`

List live agents for a job.

#### `mirror_neuron inspect nodes`

List cluster nodes and health.

#### `mirror_neuron events <job_id>`

Stream runtime events for a job.

#### `mirror_neuron pause <job_id>`

Pause a job.

#### `mirror_neuron resume <job_id>`

Resume a paused job.

#### `mirror_neuron cancel <job_id>`

Cancel a running job.

#### `mirror_neuron send <job_id> <agent_id> <message.json>`

Send a message to a live agent.

### CLI behavior requirements

* human-readable output by default
* JSON output mode for scripting
* clear non-zero exit codes on failure
* works against local node or remote runtime endpoint

---

## 14. LangGraph Integration

### Integration philosophy

LangGraph remains responsible for graph-level planning and Python-native orchestration where appropriate. MirrorNeuron takes over long-lived execution, durable state, distributed coordination, and eventful agent lifecycle management.

### Integration model

LangGraph should produce either:

* a direct MirrorNeuron-compatible manifest, or
* a higher-level graph definition that the adapter converts into a manifest

### Supported integration models

#### Model A: LangGraph as control plane

* LangGraph node submits manifest to MirrorNeuron
* MirrorNeuron executes long-lived job
* LangGraph polls or subscribes for updates
* final result returns to LangGraph

#### Model B: LangGraph as planner only

* LangGraph produces graph plan/spec
* adapter converts it into MirrorNeuron manifest
* MirrorNeuron owns execution until completion

#### Model C: Hybrid callback mode

* MirrorNeuron executes tasks
* selected reasoning steps call back into Python/LangGraph or model-serving endpoints

### Minimum integration contract

The runtime should expose APIs for:

* submit_job
* validate_manifest
* get_job_status
* stream_job_events
* send_message_to_agent
* pause_job
* resume_job
* cancel_job
* fetch_job_result

### Suggested transport

* v1: HTTP + SSE/WebSocket for events
* v2: gRPC for stronger contracts and streaming

### LangGraph adapter package

A separate Python adapter package should:

* define a LangGraph node wrapper
* accept a graph/state object or explicit manifest
* transform LangGraph-side definitions into a MirrorNeuron manifest when needed
* submit jobs to MirrorNeuron
* convert runtime events into LangGraph-compatible callbacks/state updates
* support sync and async waiting patterns

---

## 15. APIs

### External API surface (conceptual)

#### POST /jobs

Submit a new job from a manifest.

#### POST /manifests/validate

Validate a manifest without execution.

#### GET /jobs/:id

Return job metadata and status.

#### POST /jobs/:id/pause

Pause a running or waiting job.

#### POST /jobs/:id/resume

Resume a paused job.

#### POST /jobs/:id/cancel

Cancel a job.

#### GET /jobs/:id/events

Stream job events.

#### GET /jobs/:id/result

Fetch final result.

#### POST /agents/:id/message

Send a message to a live agent.

#### GET /runtime/agents

Inspect live agents.

#### GET /runtime/nodes

Inspect cluster nodes.

---

## 16. Internal Messaging Model

All inter-agent communication should use explicit envelopes.

### Message classes

* command
* response
* event
* heartbeat
* control
* tool_result
* error

### Requirements

* correlation_id support for request/response flows
* timestamps for observability
* optional causation_id for tracing multi-step workflows
* dead-letter handling for undeliverable messages

---

## 17. Failure Model and Supervision

### Failure assumptions

* agent crashes are expected
* tool calls fail often
* network partitions may occur
* nodes may leave unexpectedly
* external reasoning/model endpoints may timeout
* invalid manifests will be submitted and should fail early

### Supervision strategy

* top-level runtime supervisor
* per-job supervisor subtree
* per-agent worker supervision
* adapter supervisors for tool connectors

### Failure handling goals

* localize failures
* restart cheaply when safe
* escalate only when policy requires
* avoid duplicated side effects where possible
* distinguish manifest validation failures from runtime failures

---

## 18. Persistence Requirements

### Persisted data types

* job metadata
* manifest reference or manifest snapshot
* job state transitions
* agent checkpoints
* event log
* optional inbox snapshots where needed

### Storage requirements

* pluggable backend abstraction
* transactional semantics where reasonable
* recoverability after process/node loss

### Candidate storage backends

* PostgreSQL for metadata and events
* Redis only for transient acceleration, not sole source of truth
* object storage for large artifacts/checkpoints if needed

---

## 19. Observability

### Requirements

* structured logs with job_id and agent_id
* metrics for queue depth, restarts, runtime latency, tool latency, node health
* event tracing across agents and job coordinators
* admin inspection endpoints
* CLI-accessible event and inspection flows

### Important metrics

* running_jobs
* waiting_jobs
* failed_jobs
* active_agents
* mailbox_depth
* restart_count
* tool_timeout_count
* node_recovery_count
* job_recovery_duration_ms
* manifest_validation_failure_count

---

## 20. Security and Isolation

### v1 requirements

* API authentication
* per-job tenancy metadata
* basic authorization around inspection and control APIs
* TLS for external API transport

### Future direction

* stronger multi-tenant isolation
* policy-driven tool access
* audit trails for regulated environments

---

## 21. Deployment Model

### Local development

* single-node runtime
* CLI-first developer flow
* optional local cluster with docker-compose or multiple BEAM nodes
* mock LangGraph adapter for testing

### Production

* clustered nodes in Kubernetes or VM-based deployment
* external PostgreSQL
* service discovery / cluster formation layer
* rolling deploy strategy with recovery validation

---

## 22. Milestones

### Milestone 0: Architecture spike

* validate BEAM clustering approach
* validate distributed registry approach
* validate persistence/recovery shape
* validate manifest schema shape
* validate Python/LangGraph adapter contract
* validate CLI ergonomics

### Milestone 1: Single-node runtime MVP

* manifest loader and validator
* submit jobs from CLI
* run long-lived agents
* pause/resume/cancel
* local supervision
* event streaming

### Milestone 2: Multi-node cluster MVP

* distributed job placement
* remote agent messaging
* node failure recovery
* cluster introspection

### Milestone 3: LangGraph integration MVP

* Python adapter package
* manifest submission from LangGraph
* submit + wait pattern
* event subscription
* result retrieval

### Milestone 4: Hardening

* stronger persistence
* backpressure controls
* dead-letter handling
* observability dashboards
* production readiness validation

---

## 23. Open Questions

* Should agent state be process-local only, or partially externalized by default?
* Which distributed registry model is most stable for the expected cluster topology?
* How much replay/recovery should be automatic versus operator-controlled?
* Should LangGraph integration be HTTP-first or gRPC-first?
* How should tool execution idempotency be enforced?
* Is per-agent checkpointing needed in v1, or is per-job checkpointing enough?
* Should GPU-aware placement be part of v1 or deferred?
* Should the CLI talk directly to BEAM nodes, or always through a gateway API?
* Should manifests support dynamic graph expansion in v1, or only static topology plus runtime spawning rules?

---

## 24. Success Criteria

The project is successful if:

* a developer can define a multi-agent system as a JSON graph manifest
* a developer can run that manifest directly from the CLI
* the runtime survives process crashes through supervision
* the runtime can operate on multiple machines in a cluster
* a node failure does not irretrievably lose a durable job
* a LangGraph workflow can offload a manifest-driven job into MirrorNeuron and receive updates/results
* the operator can inspect cluster, job, and agent status with reasonable visibility

---

## 25. Example Usage Scenario

A developer writes a JSON manifest that describes a planner agent, retrieval agent, tool agent, and review agent as a graph.

They run:

```bash
mirror_neuron run market_research_manifest.json
```

MirrorNeuron validates the manifest, materializes the runtime topology, and starts a long-lived job. The retrieval agent pauses while waiting on an external connector. The tool agent times out once, is retried under policy, and succeeds. A node dies during execution. The cluster restores the job coordinator on another node using persisted metadata and resumes execution.

In a second scenario, a LangGraph planner generates the graph structure dynamically in Python. The LangGraph adapter converts it into a MirrorNeuron manifest, submits it to the runtime, subscribes to streamed events, and later returns the final result into the LangGraph state.

These scenarios should work without the application developer having to manually implement retries, recovery orchestration, or cross-node agent coordination.

---

## 26. Future Extensions

* pluggable memory backends
* richer workflow-to-agent compiler from LangGraph specs
* manifest visualizer and dry-run topology printer
* human approval inbox
* policy engine for tool access and safety
* priority scheduling and quotas
* GPU-aware and data-locality-aware placement
* Web UI for runtime inspection
* Temporal-style durable command history for selected workflows
* manifest diffing and versioned rollout support
