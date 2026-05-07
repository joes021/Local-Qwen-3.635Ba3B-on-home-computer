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

echo
echo "Local Qwen Settings TUI"
echo
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
