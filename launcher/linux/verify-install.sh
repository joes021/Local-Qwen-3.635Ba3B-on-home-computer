#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
OPENCODE_PATH="${HOME}/.config/opencode/opencode.json"

python3 - <<'PY' "$STATE_PATH" "$SETTINGS_PATH" "$OPENCODE_PATH" "$ROOT"
import json, os, sys

state_path, settings_path, opencode_path, root = sys.argv[1:5]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)

checks = [
    ("Install root", os.path.isdir(root), root),
    ("State file", os.path.isfile(state_path), state_path),
    ("Settings file", os.path.isfile(settings_path), settings_path),
    ("Model file", os.path.isfile(state.get("modelFile", "")), state.get("modelFile", "")),
    ("OpenCode config", os.path.isfile(opencode_path), opencode_path),
]

bad = False
for name, ok, value in checks:
    print(f"{name:16} : {'OK' if ok else 'FAIL'} : {value}")
    bad = bad or not ok

raise SystemExit(1 if bad else 0)
PY
