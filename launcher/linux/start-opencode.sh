#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

PROFILE="${1:-balanced}"
WORKDIR="$(get_saved_working_directory)"
OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
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

if [ ! -d "$WORKDIR" ]; then
  mkdir -p "$WORKDIR"
fi
cd "$WORKDIR"

if ! OPENCODE_CMD="$(resolve_opencode_command)"; then
  echo "OpenCode nije pronadjen kao validna Linux instalacija."
  if command -v npm >/dev/null 2>&1; then
    echo "Pokusavam automatsku Linux instalaciju OpenCode-a u \$HOME/.local ..."
    npm install -g opencode-ai --prefix "$HOME/.local"
    hash -r
  fi
  if ! OPENCODE_CMD="$(resolve_opencode_command)"; then
    echo "Pokreni repair/update ili instaliraj OpenCode pa probaj ponovo."
    exit 1
  fi
fi

echo "OpenCode executable: $OPENCODE_CMD"
echo "OpenCode config dir: $OPENCODE_CONFIG_DIR"
echo "Llama health: $(get_health_url)"
echo "Working directory: $WORKDIR"
echo "Pokrecem OpenCode u ovom terminalu..."

export OPENCODE_ENABLE_EXA=1
exec "$OPENCODE_CMD"
