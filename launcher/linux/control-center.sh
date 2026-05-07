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
    4) "$SCRIPT_DIR/settings-tui.sh" ;;
    5) "$SCRIPT_DIR/build-runtime.sh" ;;
    6) "$SCRIPT_DIR/configure-settings.sh" ;;
    7) "$SCRIPT_DIR/start-opencode.sh" ;;
    8) "$SCRIPT_DIR/verify-install.sh" ;;
    9) exit 0 ;;
    *) echo "Nepoznat izbor." ;;
  esac
done
