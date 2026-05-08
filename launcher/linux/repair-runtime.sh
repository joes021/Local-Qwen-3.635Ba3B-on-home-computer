#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"

mkdir -p "$ROOT/launchers" "$ROOT/config" "$ROOT/assets" "$ROOT/state" "$ROOT/logs"
"$SCRIPT_DIR/build-runtime.sh"
"$SCRIPT_DIR/configure-settings.sh" >/dev/null
echo "Repair runtime zavrsen."
