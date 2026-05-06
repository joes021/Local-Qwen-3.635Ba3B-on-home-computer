#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-$HOME/local-qwen-home}"
PROFILE="${PROFILE:-balanced}"
SKIP_MODEL_DOWNLOAD="${SKIP_MODEL_DOWNLOAD:-0}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULTS_PATH="$REPO_ROOT/config/profiles/defaults.json"
STATE_DIR="$INSTALL_ROOT/state"
APPS_DIR="$INSTALL_ROOT/apps"
BIN_DIR="$INSTALL_ROOT/bin"
MODELS_DIR="$INSTALL_ROOT/models"
LAUNCHERS_DIR="$INSTALL_ROOT/launchers"
CONFIG_DIR="$INSTALL_ROOT/config"
ASSETS_DIR="$INSTALL_ROOT/assets"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"

ensure_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

ensure_packages_linux() {
  local pkgs=(git curl python3 python3-pip nodejs npm cmake ninja-build build-essential pkg-config)

  if ensure_cmd apt-get; then
    sudo apt-get update
    sudo apt-get install -y "${pkgs[@]}" || true
  elif ensure_cmd dnf; then
    sudo dnf install -y git curl python3 python3-pip nodejs npm cmake ninja-build gcc-c++ make pkgconfig || true
  elif ensure_cmd pacman; then
    sudo pacman -Sy --noconfirm git curl python python-pip nodejs npm cmake ninja base-devel pkgconf || true
  elif ensure_cmd zypper; then
    sudo zypper install -y git curl python3 python3-pip nodejs npm cmake ninja gcc-c++ make pkg-config || true
  fi
}

mkdir -p "$STATE_DIR" "$APPS_DIR" "$BIN_DIR" "$MODELS_DIR" "$LAUNCHERS_DIR" "$CONFIG_DIR" "$ASSETS_DIR"

ensure_packages_linux

if ! command -v git >/dev/null 2>&1; then
  echo "git nije instaliran. Instaliraj ga pa ponovo pokreni installer."
  exit 1
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js i npm su potrebni za OpenCode. Instaliraj ih pa pokreni skriptu ponovo."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 je potreban za model download i config pisanje."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl je potreban."
  exit 1
fi

if [ ! -d "$APPS_DIR/llama.cpp" ]; then
  git clone https://github.com/ggml-org/llama.cpp.git "$APPS_DIR/llama.cpp"
fi

if [ ! -d "$APPS_DIR/llama.cpp-turboquant" ]; then
  TURBO_REPO="$(python3 - <<'PY' "$DEFAULTS_PATH"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    print(json.load(f)["turboquant"]["repo"])
PY
)"
  TURBO_BRANCH="$(python3 - <<'PY' "$DEFAULTS_PATH"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    print(json.load(f)["turboquant"]["branch"])
PY
)"
  git clone "$TURBO_REPO" "$APPS_DIR/llama.cpp-turboquant"
  git -C "$APPS_DIR/llama.cpp-turboquant" checkout "$TURBO_BRANCH"
fi

if ! command -v opencode >/dev/null 2>&1; then
  npm install -g opencode-ai
fi

cp -R "$REPO_ROOT/launcher/linux/." "$LAUNCHERS_DIR/"
cp -R "$REPO_ROOT/config/profiles/." "$CONFIG_DIR/profiles/"
mkdir -p "$ASSETS_DIR/icons"
cp -R "$REPO_ROOT/assets/icons/." "$ASSETS_DIR/icons/"

chmod +x "$LAUNCHERS_DIR/"*.sh

LLAMA_SERVER_EXE=""
if [ -x "$APPS_DIR/llama.cpp/build/bin/llama-server" ]; then
  LLAMA_SERVER_EXE="$APPS_DIR/llama.cpp/build/bin/llama-server"
fi

MODEL_FILENAME="Qwen3.6-35B-A3B-UD-IQ2_XXS.gguf"
MODEL_REPO="Qwen/Qwen3.6-35B-A3B-GGUF"
MODEL_PATH="$MODELS_DIR/$MODEL_FILENAME"

if [ "$SKIP_MODEL_DOWNLOAD" != "1" ] && [ ! -f "$MODEL_PATH" ]; then
  python3 -m pip install --user -U huggingface_hub
  python3 - <<'PY' "$MODEL_REPO" "$MODEL_FILENAME" "$MODELS_DIR"
from huggingface_hub import hf_hub_download
import sys
repo_id, filename, local_dir = sys.argv[1:4]
hf_hub_download(repo_id=repo_id, filename=filename, local_dir=local_dir, local_dir_use_symlinks=False)
PY
fi

cat > "$STATE_DIR/install-state.json" <<EOF
{
  "installRoot": "$INSTALL_ROOT",
  "profile": "$PROFILE",
  "repoRoot": "$REPO_ROOT",
  "llamaSourceDir": "$APPS_DIR/llama.cpp",
  "turboDir": "$APPS_DIR/llama.cpp-turboquant",
  "llamaServerExe": "$LLAMA_SERVER_EXE",
  "modelFile": "$MODEL_PATH",
  "modelId": "$MODEL_FILENAME",
  "port": 8091,
  "threads": 16,
  "noMmap": true,
  "mlock": true
}
EOF

"$LAUNCHERS_DIR/configure-settings.sh"

mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/local-qwen-control-center.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Local Qwen Control Center
Exec=$LAUNCHERS_DIR/control-center.sh
Terminal=true
Icon=$ASSETS_DIR/icons/control-center.ico
Categories=Development;
EOF

cat > "$DESKTOP_DIR/opencode-local-qwen.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OpenCode - Local Qwen
Exec=$LAUNCHERS_DIR/start-opencode.sh balanced
Terminal=true
Icon=$ASSETS_DIR/icons/opencode-local-qwen.ico
Categories=Development;
EOF

chmod +x "$DESKTOP_DIR/local-qwen-control-center.desktop" "$DESKTOP_DIR/opencode-local-qwen.desktop"

cat <<EOF
Linux installer je pripremio lokalni stack.

Install root:
$INSTALL_ROOT

State:
$STATE_DIR/install-state.json

Launchers:
$LAUNCHERS_DIR

Primary commands:
- $LAUNCHERS_DIR/control-center.sh
- $LAUNCHERS_DIR/start-opencode.sh
- $LAUNCHERS_DIR/verify-install.sh

Model:
$MODEL_PATH

Napomena:
- Linux build i runtime parity jos nisu na nivou Windows milestone-a
- ako $LLAMA_SERVER_EXE nije postavljen, treba prvo build-ovati llama.cpp
EOF
