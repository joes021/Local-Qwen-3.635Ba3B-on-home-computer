#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

show_status() {
  if test_llama_health; then
    echo "Status: server aktivan na $(get_health_url)"
  else
    echo "Status: server nije aktivan"
  fi
}

show_settings() {
  python3 - <<'PY' "$(get_settings_path)" "$(get_install_state_path)"
import json, os, sys
settings_path, state_path = sys.argv[1:3]
settings = {}
state = {}
if os.path.exists(settings_path):
    with open(settings_path, "r", encoding="utf-8") as f:
        settings = json.load(f)
if os.path.exists(state_path):
    with open(state_path, "r", encoding="utf-8") as f:
        state = json.load(f)
print(f"Profil: {settings.get('profile', 'balanced')}")
print(f"Context: {settings.get('llama', {}).get('contextSize', 'n/a')}")
print(f"Output: {settings.get('llama', {}).get('maxOutputTokens', 'n/a')}")
print(f"Build steps: {settings.get('opencode', {}).get('buildSteps', 'n/a')}")
print(f"Plan steps: {settings.get('opencode', {}).get('planSteps', 'n/a')}")
print(f"General steps: {settings.get('opencode', {}).get('generalSteps', 'n/a')}")
print(f"Explore steps: {settings.get('opencode', {}).get('exploreSteps', 'n/a')}")
print(f"Working dir: {settings.get('opencode', {}).get('workingDirectory', os.path.expanduser('~'))}")
print(f"Model: {state.get('modelFile', 'n/a')}")
PY
}

configure_tui() {
  local current_profile current_workdir
  current_profile="$(get_saved_profile)"
  current_workdir="$(get_saved_working_directory)"
  local current_json
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
  local current_values=()
  mapfile -t current_values <<<"$current_json"
  local current_ctx="${current_values[0]}"
  local current_out="${current_values[1]}"
  local current_build="${current_values[2]}"
  local current_plan="${current_values[3]}"
  local current_general="${current_values[4]}"
  local current_explore="${current_values[5]}"

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
}

while true; do
  echo
  echo "Local Qwen Control Center"
  show_status
  show_settings
  echo "1) Start server (saved profile)"
  echo "2) Start server (choose profile)"
  echo "3) Stop server"
  echo "4) Configure settings"
  echo "5) Build runtime"
  echo "6) Write OpenCode config"
  echo "7) Start OpenCode"
  echo "8) Verify install"
  echo "9) Exit"
  read -r -p "Izbor: " choice

  case "$choice" in
    1) "$SCRIPT_DIR/start-server.sh" ;;
    2) read -r -p "Profil (speed/balanced/video): " profile; "$SCRIPT_DIR/start-server.sh" "${profile:-balanced}" ;;
    3) "$SCRIPT_DIR/stop-server.sh" ;;
    4) configure_tui ;;
    5) "$SCRIPT_DIR/build-runtime.sh" ;;
    6) "$SCRIPT_DIR/configure-settings.sh" ;;
    7) "$SCRIPT_DIR/start-opencode.sh" ;;
    8) "$SCRIPT_DIR/verify-install.sh" ;;
    9) exit 0 ;;
    *) echo "Nepoznat izbor." ;;
  esac
done
