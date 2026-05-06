#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-$HOME/local-qwen-home}"
PROFILE="${PROFILE:-balanced}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULTS_PATH="$REPO_ROOT/config/profiles/defaults.json"
STATE_DIR="$INSTALL_ROOT/state"
APPS_DIR="$INSTALL_ROOT/apps"
MODELS_DIR="$INSTALL_ROOT/models"

mkdir -p "$STATE_DIR" "$APPS_DIR" "$MODELS_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "git nije instaliran. Instaliraj ga pa ponovo pokreni installer."
  exit 1
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js i npm su potrebni za OpenCode. Instaliraj ih pa pokreni skriptu ponovo."
  exit 1
fi

if [ ! -d "$APPS_DIR/llama.cpp" ]; then
  git clone https://github.com/ggml-org/llama.cpp.git "$APPS_DIR/llama.cpp"
fi

if [ ! -d "$APPS_DIR/llama.cpp-turboquant" ]; then
  git clone https://github.com/turboderp-org/llama.cpp.git "$APPS_DIR/llama.cpp-turboquant"
fi

if ! command -v opencode >/dev/null 2>&1; then
  npm install -g opencode-ai
fi

cat > "$STATE_DIR/install-state.json" <<EOF
{
  "installRoot": "$INSTALL_ROOT",
  "profile": "$PROFILE",
  "repoRoot": "$REPO_ROOT"
}
EOF

cat > "$STATE_DIR/model-download-next-step.txt" <<EOF
Automatski model download jos nije finalizovan u prvoj javnoj Linux verziji.

Preporuceni model:
Qwen/Qwen3.6-35B-A3B-GGUF
Qwen3.6-35B-A3B-UD-IQ2_XXS.gguf

Predvidjeno odrediste:
$MODELS_DIR/Qwen3.6-35B-A3B-UD-IQ2_XXS.gguf
EOF

cat <<EOF
Linux installer skeleton je zavrsen.

Install root:
$INSTALL_ROOT

State:
$STATE_DIR/install-state.json

Sledeci korak:
- build/configure llama.cpp i TurboQuant
- postaviti launchere
- povezati OpenCode sa lokalnim modelom
EOF
