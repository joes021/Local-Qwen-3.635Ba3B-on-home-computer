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

DOWNLOAD_OUTPUT="$("$SCRIPT_DIR/manage-models.sh" download "$MODEL_ID" 2>&1)"
printf '%s\n' "$DOWNLOAD_OUTPUT" | python3 - <<'PY'
import sys

raw = sys.stdin.read()
lines = [line.rstrip() for line in raw.splitlines() if line.strip()]

if any("Model je vec prisutan:" in line for line in lines):
    print("Model je vec prisutan i deluje kompletno, pa download nije bio potreban.")
else:
    filtered = []
    for line in lines:
        if line.endswith("/state/settings.json"):
            continue
        if line.endswith("/.config/opencode/opencode.json"):
            continue
        if line == "Linux installer je pripremio lokalni stack.":
            continue
        if line in {"Install root:", "State:", "Install report:", "Launchers:", "Primary commands:", "Model:", "Napomena:"}:
            continue
        if line.startswith("- /"):
            continue
        filtered.append(line)
    for line in filtered[:8]:
        print(line)
PY
echo "Repair model zavrsen za: $MODEL_ID"
