#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
REPORT_PATH="$ROOT/state/install-report.json"
REPAIR_SUMMARY_PATH="$ROOT/state/repair-summary.json"
FOUND_ITEMS=()
FIXED_ITEMS=()
MANUAL_ITEMS=()
NOTE_ITEMS=()

mkdir -p "$ROOT/logs" "$ROOT/state" "$ROOT/assets/icons" "$ROOT/config/profiles" "$ROOT/docs"

if [ ! -f "$ROOT/launchers/control-center.sh" ]; then
  echo "Launchers folder deluje nepotpuno: $ROOT/launchers"
  exit 1
fi

MODEL_PATH="$(python3 - <<'PY' "$STATE_PATH"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    print(json.load(f)['modelFile'])
PY
)"

if [ ! -f "$MODEL_PATH" ] || ! model_file_looks_complete "$MODEL_PATH"; then
  FOUND_ITEMS+=("Aktivni model je nedostajao ili je bio nepotpun.")
  INSTALL_ROOT="$ROOT" SKIP_RUNTIME_BUILD=1 bash "$ROOT/install/linux/install.sh"
  FIXED_ITEMS+=("Linux installer repair tok je ponovo pokrenuo install za model/runtime sloj.")
  python3 "$(get_runtime_engine_path)" repair-summary \
    --outcome completed \
    --found-json "$(python3 - <<'PY' "${FOUND_ITEMS[@]}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
    --fixed-json "$(python3 - <<'PY' "${FIXED_ITEMS[@]}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
    --manual-json "[]" \
    --notes-json "[]" > "$REPAIR_SUMMARY_PATH"
  exit 0
fi

FOUND_ITEMS+=("OpenCode config je proveravan kroz repair tok.")
"$SCRIPT_DIR/configure-settings.sh"
FIXED_ITEMS+=("OpenCode config je osvezen.")

python3 - <<'PY' "$STATE_PATH" "$SETTINGS_PATH" "$REPORT_PATH" "$ROOT"
import json, os, sys

state_path, settings_path, report_path, root = sys.argv[1:5]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

report = {
    "generatedAt": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
    "platform": "linux",
    "profile": settings.get("profile", "balanced"),
    "installRoot": root,
    "components": {
        "installState": {"path": state_path, "ok": os.path.isfile(state_path)},
        "launchers": {"path": os.path.join(root, "launchers"), "ok": os.path.isfile(os.path.join(root, "launchers", "control-center.sh"))},
        "model": {"path": state.get("modelFile", ""), "ok": os.path.isfile(state.get("modelFile", "")), "sizeBytes": os.path.getsize(state.get("modelFile", "")) if os.path.isfile(state.get("modelFile", "")) else 0},
        "opencodeConfig": {"path": os.path.expanduser("~/.config/opencode/opencode.json"), "ok": os.path.isfile(os.path.expanduser("~/.config/opencode/opencode.json"))},
    },
}

with open(report_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
PY

python3 "$(get_runtime_engine_path)" repair-summary \
  --outcome completed \
  --found-json "$(python3 - <<'PY' "${FOUND_ITEMS[@]}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
  --fixed-json "$(python3 - <<'PY' "${FIXED_ITEMS[@]}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
  --manual-json "$(python3 - <<'PY' "${MANUAL_ITEMS[@]}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
  --notes-json "$(python3 - <<'PY' "${NOTE_ITEMS[@]}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" > "$REPAIR_SUMMARY_PATH"

echo "Repair zavrsen."
echo "Install report: $REPORT_PATH"
echo "Repair summary: $REPAIR_SUMMARY_PATH"
