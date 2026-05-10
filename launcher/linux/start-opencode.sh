#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

PROFILE="${1:-balanced}"
WORKDIR="$(get_saved_working_directory)"
if [ -z "${1:-}" ]; then
  PROFILE="$(get_saved_profile)"
fi

PROFILE="$PROFILE" "$SCRIPT_DIR/configure-settings.sh"

if ! test_llama_health; then
  "$SCRIPT_DIR/start-server.sh" "$PROFILE"
  for _ in $(seq 1 30); do
    if test_llama_health; then
      break
    fi
    sleep 2
  done
fi

if ! test_llama_health; then
  echo "llama.cpp server nije dostupan."
  exit 1
fi

if [ -d "$WORKDIR" ]; then
  cd "$WORKDIR"
fi

export OPENCODE_ENABLE_EXA=1
exec opencode
