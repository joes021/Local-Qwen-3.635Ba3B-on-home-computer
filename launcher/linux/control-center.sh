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

while true; do
  echo
  echo "Local Qwen Control Center"
  show_status
  echo "1) Start server (balanced)"
  echo "2) Stop server"
  echo "3) Build runtime"
  echo "4) Write OpenCode config"
  echo "5) Start OpenCode"
  echo "6) Verify install"
  echo "7) Exit"
  read -r -p "Izbor: " choice

  case "$choice" in
    1) "$SCRIPT_DIR/start-server.sh" balanced ;;
    2) "$SCRIPT_DIR/stop-server.sh" ;;
    3) "$SCRIPT_DIR/build-runtime.sh" ;;
    4) "$SCRIPT_DIR/configure-settings.sh" ;;
    5) "$SCRIPT_DIR/start-opencode.sh" balanced ;;
    6) "$SCRIPT_DIR/verify-install.sh" ;;
    7) exit 0 ;;
    *) echo "Nepoznat izbor." ;;
  esac
done
