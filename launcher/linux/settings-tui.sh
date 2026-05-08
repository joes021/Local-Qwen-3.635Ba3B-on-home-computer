#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

current_profile="$(get_saved_profile)"
current_workdir="$(get_saved_working_directory)"

current_json="$(python3 - <<'PY' "$(get_settings_path)"
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
llama = data.get("llama", {})
opencode = data.get("opencode", {})
print(llama.get("contextSize", 262144))
print(llama.get("maxOutputTokens", 8192))
print(opencode.get("buildSteps", 120))
print(opencode.get("planSteps", 80))
print(opencode.get("generalSteps", 100))
print(opencode.get("exploreSteps", 60))
PY
)"

current_values=()
mapfile -t current_values <<<"$current_json"
current_ctx="${current_values[0]}"
current_out="${current_values[1]}"
current_build="${current_values[2]}"
current_plan="${current_values[3]}"
current_general="${current_values[4]}"
current_explore="${current_values[5]}"

gpu_mib="0"
ram_gib="0"
cpu_threads="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 0)"
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d '[:space:]')"
fi
ram_gib="$(python3 - <<'PY'
import os
value = 0
try:
    page_size = os.sysconf("SC_PAGE_SIZE")
    phys_pages = os.sysconf("SC_PHYS_PAGES")
    value = int((page_size * phys_pages) / (1024 ** 3))
except Exception:
    value = 0
print(value)
PY
)"

preset_payload="$(get_settings_presets_json "${gpu_mib:-0}" "${ram_gib:-0}" "${cpu_threads:-0}")"
preset_choice=""
selected_preset_json=""

echo
echo "Local Qwen Settings TUI"
echo
echo "Quick presets"
python3 - <<'PY' "$preset_payload"
import json, sys
payload = json.loads(sys.argv[1])
for index, preset in enumerate(payload.get("presets", []), start=1):
    print(f"{index}. {preset['title']} | {preset['summary']}")
print("M. Manuelno zadrzi/unesi vrednosti")
PY
echo
read -r -p "Izbor preseta [M]: " preset_choice

if [[ "${preset_choice^^}" != "M" && -n "$preset_choice" ]]; then
  selected_preset_json="$(python3 - <<'PY' "$preset_payload" "$preset_choice"
import json, sys
payload = json.loads(sys.argv[1])
choice = sys.argv[2].strip()
presets = payload.get("presets", [])
try:
    index = int(choice) - 1
except ValueError:
    index = -1
if 0 <= index < len(presets):
    print(json.dumps(presets[index]))
PY
)"
fi

if [[ -n "$selected_preset_json" ]]; then
  preset_preview_json="$(get_settings_preset_preview_json "${gpu_mib:-0}" "${ram_gib:-0}" "${cpu_threads:-0}" \
    "$(python3 - <<'PY' "$selected_preset_json"
import json, sys
print(json.loads(sys.argv[1])["id"])
PY
)" \
    "$current_profile" "$current_ctx" "$current_out" "$current_build" "$current_plan" "$current_general" "$current_explore")"
  mapfile -t preset_values < <(python3 - <<'PY' "$selected_preset_json"
import json, sys
preset = json.loads(sys.argv[1])
print(preset["title"])
print(preset["profile"])
print(preset["contextSize"])
print(preset["maxOutputTokens"])
print(preset["buildSteps"])
print(preset["planSteps"])
print(preset["generalSteps"])
print(preset["exploreSteps"])
print(preset["target"])
print(preset["summary"])
print(preset["tradeoff"])
PY
)
  preset_title="${preset_values[0]}"
  current_profile="${preset_values[1]}"
  current_ctx="${preset_values[2]}"
  current_out="${preset_values[3]}"
  current_build="${preset_values[4]}"
  current_plan="${preset_values[5]}"
  current_general="${preset_values[6]}"
  current_explore="${preset_values[7]}"
  echo
  echo "Quick preset: $preset_title"
  echo "Za koga je: ${preset_values[8]}"
  echo "Sta radi: ${preset_values[9]}"
  echo "Tradeoff: ${preset_values[10]}"
  echo "Sta se menja:"
  python3 - <<'PY' "$preset_preview_json"
import json, sys
payload = json.loads(sys.argv[1])
for line in payload.get("compareLines", []):
    print(f"- {line}")
PY
  echo
fi

read -r -p "Profil [$current_profile]: " profile
read -r -p "Context size [$current_ctx]: " ctx
read -r -p "Max output tokens [$current_out]: " out
read -r -p "Build steps [$current_build]: " build
read -r -p "Plan steps [$current_plan]: " plan
read -r -p "General steps [$current_general]: " general
read -r -p "Explore steps [$current_explore]: " explore
read -r -p "Working directory [$current_workdir]: " workdir

PROFILE="${profile:-$current_profile}" \
CONTEXT_SIZE="${ctx:-$current_ctx}" \
MAX_OUTPUT_TOKENS="${out:-$current_out}" \
BUILD_STEPS="${build:-$current_build}" \
PLAN_STEPS="${plan:-$current_plan}" \
GENERAL_STEPS="${general:-$current_general}" \
EXPLORE_STEPS="${explore:-$current_explore}" \
WORKING_DIRECTORY="${workdir:-$current_workdir}" \
"$SCRIPT_DIR/configure-settings.sh"

echo
echo "Sacuvano."
