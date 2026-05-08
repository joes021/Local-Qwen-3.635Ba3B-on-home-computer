#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

STATE_PATH="$(get_install_state_path)"
MODEL_ID="$(python3 - <<'PY' "$STATE_PATH"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelId", ""))
PY
)"

if [ -z "$MODEL_ID" ]; then
  echo "Model ID nije pronadjen u install state-u."
  exit 1
fi

"$SCRIPT_DIR/manage-models.sh" download "$MODEL_ID"
echo "Repair model zavrsen za: $MODEL_ID"
