#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

pkill -f 'llama-server' || true
set_service_lifecycle_state "inactive" "" "" "" "Stop server komanda je izvrsena."
echo "llama.cpp server stop requested."
