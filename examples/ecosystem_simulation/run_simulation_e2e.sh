#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/examples/ecosystem_simulation"
BUNDLE_ROOT="/tmp/mirror_neuron_cluster_bundles"
ANIMALS="2000"
REGIONS="16"
DURATION_SECONDS="300"
TICK_SECONDS="5"
MAX_FOOD="420"
FOOD_REGEN_PER_TICK="72"
MAX_REGION_POPULATION="220"
MIGRATION_RATE="0.035"
MUTATION_RATE="0.05"
SEED=""
DRY_RUN="0"
BOX1_IP=""
BOX2_IP=""
SELF_IP=""
WAIT_TIMEOUT_SECONDS="${MIRROR_NEURON_SIM_WAIT_TIMEOUT_SECONDS:-420}"
POLL_INTERVAL_SECONDS="${MIRROR_NEURON_SIM_POLL_INTERVAL_SECONDS:-5}"
REDIS_URL="${MIRROR_NEURON_REDIS_URL:-redis://127.0.0.1:6379/0}"

usage() {
  cat <<'EOF'
usage:
  bash examples/ecosystem_simulation/run_simulation_e2e.sh [options]

examples:
  bash examples/ecosystem_simulation/run_simulation_e2e.sh
  bash examples/ecosystem_simulation/run_simulation_e2e.sh --animals 2000 --regions 16
  bash examples/ecosystem_simulation/run_simulation_e2e.sh --box1-ip 192.168.4.29 --box2-ip 192.168.4.35 --self-ip 192.168.4.29

options:
      --animals <n>                Total animals, defaults to 2000
      --regions <n>                Region agents, defaults to 16
      --duration-seconds <n>       Simulated duration, defaults to 300
      --tick-seconds <n>           Simulated seconds per tick, defaults to 5
      --max-food <n>               Region food capacity, defaults to 420
      --food-regen-per-tick <n>    Food regenerated per tick, defaults to 72
      --max-region-population <n>  Soft population cap per region, defaults to 220
      --migration-rate <n>         Base migration rate, defaults to 0.035
      --mutation-rate <n>          DNA mutation rate, defaults to 0.05
      --seed <n>                   Simulation seed, defaults to a random value per run
      --box1-ip <ip>               Submit through cluster_cli.sh using box 1
      --box2-ip <ip>               Submit through cluster_cli.sh using box 2
      --self-ip <ip>               Submit through cluster_cli.sh from this machine
      --wait-timeout-seconds <n>   Maximum time to wait, defaults to 420
      --poll-interval-seconds <n>  Progress poll interval, defaults to 5
      --dry-run                    Generate only; do not run
  -h, --help                       Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --animals) ANIMALS="$2"; shift 2 ;;
    --regions) REGIONS="$2"; shift 2 ;;
    --duration-seconds) DURATION_SECONDS="$2"; shift 2 ;;
    --tick-seconds) TICK_SECONDS="$2"; shift 2 ;;
    --max-food) MAX_FOOD="$2"; shift 2 ;;
    --food-regen-per-tick) FOOD_REGEN_PER_TICK="$2"; shift 2 ;;
    --max-region-population) MAX_REGION_POPULATION="$2"; shift 2 ;;
    --migration-rate) MIGRATION_RATE="$2"; shift 2 ;;
    --mutation-rate) MUTATION_RATE="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    --box1-ip) BOX1_IP="$2"; shift 2 ;;
    --box2-ip) BOX2_IP="$2"; shift 2 ;;
    --self-ip) SELF_IP="$2"; shift 2 ;;
    --wait-timeout-seconds) WAIT_TIMEOUT_SECONDS="$2"; shift 2 ;;
    --poll-interval-seconds) POLL_INTERVAL_SECONDS="$2"; shift 2 ;;
    --dry-run) DRY_RUN="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

RUNNER=("$ROOT_DIR/mirror_neuron")

if [ -n "$BOX1_IP" ] || [ -n "$BOX2_IP" ] || [ -n "$SELF_IP" ]; then
  if [ -z "$BOX1_IP" ] || [ -z "$BOX2_IP" ] || [ -z "$SELF_IP" ]; then
    echo "cluster mode requires --box1-ip, --box2-ip, and --self-ip together" >&2
    exit 1
  fi

  RUNNER=(
    bash "$ROOT_DIR/scripts/cluster_cli.sh"
    --box1-ip "$BOX1_IP"
    --box2-ip "$BOX2_IP"
    --self-ip "$SELF_IP"
    --
  )

  REDIS_URL="redis://${BOX1_IP}:6379/0"
fi

BUNDLE_ARGS=(
  --animals "$ANIMALS"
  --regions "$REGIONS"
  --duration-seconds "$DURATION_SECONDS"
  --tick-seconds "$TICK_SECONDS"
  --max-food "$MAX_FOOD"
  --food-regen-per-tick "$FOOD_REGEN_PER_TICK"
  --max-region-population "$MAX_REGION_POPULATION"
  --migration-rate "$MIGRATION_RATE"
  --mutation-rate "$MUTATION_RATE"
)

if [ -n "$SEED" ]; then
  BUNDLE_ARGS+=(--seed "$SEED")
fi

if [ "$DRY_RUN" = "1" ] || [ -n "$SELF_IP" ]; then
  TMP_OUTPUT_DIR="$(mktemp -d /tmp/mirror_neuron_ecosystem.XXXXXX)"
  if [ -n "$SELF_IP" ]; then
    TMP_OUTPUT_DIR="$BUNDLE_ROOT"
    mkdir -p "$TMP_OUTPUT_DIR"
  fi
  BUNDLE_ARGS+=(--output-dir "$TMP_OUTPUT_DIR")
fi

BUNDLE_PATH="$(python3 "$SCRIPT_DIR/generate_bundle.py" "${BUNDLE_ARGS[@]}")"
RESULT_PATH="$BUNDLE_PATH/result.json"

echo "Building MirrorNeuron runtime..."
(cd "$ROOT_DIR" && mix escript.build >/dev/null)

echo "Generated bundle:"
echo "  $BUNDLE_PATH"
if [ -z "$SEED" ]; then
  SEED="$(python3 - "$BUNDLE_PATH/manifest.json" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
for node in manifest["nodes"]:
    if node["node_id"] == "world":
        print(node["config"]["seed"])
        break
PY
)"
fi
echo "Simulation seed:"
echo "  $SEED"

if [ "$DRY_RUN" = "1" ]; then
  echo "Dry run only. Bundle path:"
  echo "  $BUNDLE_PATH"
  exit 0
fi

if [ -n "$SELF_IP" ]; then
  if [ "$SELF_IP" = "$BOX1_IP" ]; then
    PEER_IP="$BOX2_IP"
  else
    PEER_IP="$BOX1_IP"
  fi
  echo "Syncing bundle to peer box:"
  echo "  peer=$PEER_IP"
  ssh "$PEER_IP" "mkdir -p \"$(dirname "$BUNDLE_PATH")\" && rm -rf \"$BUNDLE_PATH\""
  scp -r "$BUNDLE_PATH" "${PEER_IP}:$(dirname "$BUNDLE_PATH")/" >/dev/null
fi

echo "Validating bundle..."
"${RUNNER[@]}" validate "$BUNDLE_PATH" >/dev/null

echo "Running ecosystem simulation..."
echo "  timeout: ${WAIT_TIMEOUT_SECONDS}s"
echo "  poll interval: ${POLL_INTERVAL_SECONDS}s"

if [ -z "$SELF_IP" ]; then
  time "${RUNNER[@]}" run "$BUNDLE_PATH" --json | tee "$RESULT_PATH"
else
  SUBMIT_OUTPUT_FILE="$(mktemp /tmp/mirror_neuron_ecosystem_submit.XXXXXX)"
  time "${RUNNER[@]}" run "$BUNDLE_PATH" --json --no-await >"$SUBMIT_OUTPUT_FILE"

  JOB_ID="$(
    python3 - "$SUBMIT_OUTPUT_FILE" <<'PY'
import json
import sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text()
decoder = json.JSONDecoder()
for index, char in enumerate(raw):
    if char != "{":
        continue
    try:
        payload, _ = decoder.raw_decode(raw[index:])
        if "job_id" in payload:
            print(payload["job_id"])
            break
    except json.JSONDecodeError:
        continue
else:
    raise SystemExit("could not decode submit JSON")
PY
  )"

  echo "Submitted job:"
  echo "  $JOB_ID"
  echo "Waiting for completion..."

  JOB_JSON="$(
    cd "$ROOT_DIR"
    env MIRROR_NEURON_REDIS_URL="$REDIS_URL" mix run --no-start -e '
      Application.ensure_all_started(:mirror_neuron)
      job_id = System.argv() |> Enum.at(0)
      timeout_seconds = System.argv() |> Enum.at(1) |> String.to_integer()
      poll_interval_ms = System.argv() |> Enum.at(2) |> String.to_integer() |> Kernel.*(1_000)
      deadline = System.monotonic_time(:millisecond) + timeout_seconds * 1_000

      wait = fn wait ->
        case MirrorNeuron.inspect_job(job_id) do
          {:ok, %{"status" => status} = job} when status in ["completed", "failed", "cancelled"] ->
            IO.puts(Jason.encode!(job))

          _ ->
            progress =
              case MirrorNeuron.inspect_agents(job_id) do
                {:ok, agents} ->
                  regions = Enum.filter(agents, &String.starts_with?(&1["agent_id"] || "", "region_"))
                  progressed =
                    Enum.count(regions, fn agent ->
                      tick = get_in(agent, ["current_state", "agent_state", "tick"]) || 0
                      tick > 0
                    end)
                  "progress regions=#{progressed}/#{length(regions)}"

                _ ->
                  "progress unavailable"
              end

            IO.puts(:stderr, progress)

            if System.monotonic_time(:millisecond) >= deadline do
              IO.puts(:stderr, "timed out waiting for job #{job_id}")
              System.halt(2)
            else
              Process.sleep(poll_interval_ms)
              wait.(wait)
            end
        end
      end

      wait.(wait)
    ' -- "$JOB_ID" "$WAIT_TIMEOUT_SECONDS" "$POLL_INTERVAL_SECONDS"
  )"

  printf '%s\n' "$JOB_JSON" >"$RESULT_PATH"
fi

echo "Result written to:"
echo "  $RESULT_PATH"
echo "Summary:"
python3 "$SCRIPT_DIR/summarize_result.py" "$RESULT_PATH"
