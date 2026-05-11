#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
REPORT_PATH="$ROOT/state/install-report.json"
REPAIR_SUMMARY_PATH="$ROOT/state/repair-summary.json"
SUMMARY_PATH="$ROOT/state/install-summary.txt"
FOUND_ITEMS=()
FIXED_ITEMS=()
MANUAL_ITEMS=()
NOTE_ITEMS=()
ATTEMPTED_ACTIONS=()

add_unique_item() {
  local array_name="$1"
  local value="$2"
  local existing
  eval "existing=(\"\${${array_name}[@]-}\")"
  for item in "${existing[@]}"; do
    [ "$item" = "$value" ] && return 0
  done
  eval "${array_name}+=(\"\$value\")"
}

was_attempted() {
  local action_id="$1"
  for item in "${ATTEMPTED_ACTIONS[@]-}"; do
    [ "$item" = "$action_id" ] && return 0
  done
  return 1
}

mark_attempted() {
  local action_id="$1"
  ATTEMPTED_ACTIONS+=("$action_id")
}

mkdir -p "$ROOT/logs" "$ROOT/state" "$ROOT/assets/icons" "$ROOT/config/profiles" "$ROOT/docs"

if [ ! -f "$ROOT/launchers/control-center.sh" ]; then
  echo "Launchers folder deluje nepotpuno: $ROOT/launchers"
  exit 1
fi

for round in 1 2 3 4 5 6; do
  plan_json="$(get_repair_plan_json)"
  next_action="$(python3 - <<'PY' "$plan_json" "${ATTEMPTED_ACTIONS[@]-}"
import json, sys
payload = json.loads(sys.argv[1])
attempted = set(sys.argv[2:])
for step in payload.get("steps", []):
    if step.get("id") not in attempted:
        print(json.dumps(step))
        raise SystemExit(0)
print("")
PY
)"
  if [ -z "$next_action" ]; then
    break
  fi

  action_id="$(python3 - <<'PY' "$next_action"
import json, sys
print(json.loads(sys.argv[1])["id"])
PY
)"
  action_title="$(python3 - <<'PY' "$next_action"
import json, sys
print(json.loads(sys.argv[1])["title"])
PY
)"
  action_reason="$(python3 - <<'PY' "$next_action"
import json, sys
print(json.loads(sys.argv[1])["reason"])
PY
)"

  mark_attempted "$action_id"
  add_unique_item FOUND_ITEMS "Planirana repair akcija: $action_title"
  add_unique_item NOTE_ITEMS "Repair round $round: $action_title"

  case "$action_id" in
    repair-runtime)
      "$SCRIPT_DIR/repair-runtime.sh"
      add_unique_item FIXED_ITEMS "Runtime repair je pokrenut."
      ;;
    repair-model)
      "$SCRIPT_DIR/repair-model.sh"
      add_unique_item FIXED_ITEMS "Model repair je pokrenut."
      ;;
    repair-config)
      "$SCRIPT_DIR/repair-config.sh"
      add_unique_item FIXED_ITEMS "Config repair je pokrenut."
      ;;
    repair-app-control)
      add_unique_item MANUAL_ITEMS "App Control / WDAC warning je Windows-specifcan: $action_reason"
      ;;
    start-server)
      add_unique_item NOTE_ITEMS "Repair plan sada predlaze start-server umesto dodatnog repair-a."
      ;;
    *)
      add_unique_item MANUAL_ITEMS "Nepoznata guided repair akcija: $action_id"
      ;;
  esac
done

add_unique_item FOUND_ITEMS "OpenCode config je proveravan kroz repair tok."
"$SCRIPT_DIR/configure-settings.sh"
add_unique_item FIXED_ITEMS "OpenCode config je osvezen."

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

final_plan_json="$(get_repair_plan_json)"
python3 - <<'PY' "$final_plan_json" > "$ROOT/state/remaining-repair-steps.json"
import json, sys
payload = json.loads(sys.argv[1])
json.dump(payload, sys.stdout, indent=2)
PY

while IFS= read -r remaining_line; do
  [ -n "$remaining_line" ] && add_unique_item MANUAL_ITEMS "$remaining_line"
done < <(
  python3 - <<'PY' "$final_plan_json"
import json, sys
payload = json.loads(sys.argv[1])
for step in payload.get("steps", []):
    print(f"I dalje ceka korak: {step.get('title')} - {step.get('reason')}")
PY
)

if [ "${#MANUAL_ITEMS[@]}" -eq 0 ] && [ "${#FIXED_ITEMS[@]}" -eq 0 ]; then
  add_unique_item NOTE_ITEMS "Repair nije morao da menja kriticne fajlove; sistem je vec delovao zdravo."
fi

python3 "$(get_runtime_engine_path)" repair-summary \
  --outcome "$(if [ "${#MANUAL_ITEMS[@]}" -gt 0 ]; then echo partial; else echo completed; fi)" \
  --found-json "$(python3 - <<'PY' "${FOUND_ITEMS[@]-}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
  --fixed-json "$(python3 - <<'PY' "${FIXED_ITEMS[@]-}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
  --manual-json "$(python3 - <<'PY' "${MANUAL_ITEMS[@]-}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" \
  --notes-json "$(python3 - <<'PY' "${NOTE_ITEMS[@]-}"
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)" > "$REPAIR_SUMMARY_PATH"

python3 - <<'PY' "$REPAIR_SUMMARY_PATH" "$SUMMARY_PATH"
import json, sys
repair_path, summary_path = sys.argv[1:3]
with open(repair_path, "r", encoding="utf-8") as f:
    payload = json.load(f)
lines = ["Repair summary"]
for key, title in (
    ("found", "Found"),
    ("fixed", "Fixed"),
    ("manual", "Manual"),
    ("notes", "Notes"),
):
    values = payload.get(key) or []
    if not values:
        continue
    lines.append("")
    lines.append(f"{title}:")
    lines.extend(f"- {item}" for item in values)
with open(summary_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY

echo "Repair zavrsen."
echo "Install report: $REPORT_PATH"
echo "Repair summary: $REPAIR_SUMMARY_PATH"
echo "Repair summary text: $SUMMARY_PATH"
