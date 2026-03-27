#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/examples/openshell_worker_demo_manifest.json"

echo "Generated manifest:"
echo "  $MANIFEST_PATH"
echo
echo "Validate the manifest:"
echo "  cd $ROOT_DIR && ./mirror_neuron validate $MANIFEST_PATH"
echo
echo "Run the sandboxed demo:"
echo "  cd $ROOT_DIR && ./mirror_neuron run $MANIFEST_PATH --json"
