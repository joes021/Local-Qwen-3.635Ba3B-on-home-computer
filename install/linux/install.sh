#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-$HOME/local-qwen-home}"
PROFILE="${PROFILE:-balanced}"
SKIP_MODEL_DOWNLOAD="${SKIP_MODEL_DOWNLOAD:-0}"
SKIP_RUNTIME_BUILD="${SKIP_RUNTIME_BUILD:-0}"
LOCAL_QWEN_SKIP_PACKAGE_INSTALL="${LOCAL_QWEN_SKIP_PACKAGE_INSTALL:-0}"
LOCAL_QWEN_SKIP_SOURCE_CLONE="${LOCAL_QWEN_SKIP_SOURCE_CLONE:-0}"
LOCAL_QWEN_SKIP_OPENCODE_INSTALL="${LOCAL_QWEN_SKIP_OPENCODE_INSTALL:-0}"
LOCAL_QWEN_SKIP_PREREQ_CHECKS="${LOCAL_QWEN_SKIP_PREREQ_CHECKS:-0}"
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
INSTALL_REPORT_PATH="$STATE_DIR/install-report.json"

if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  ID=""
  VERSION_ID=""
fi

ensure_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

ensure_packages_linux() {
  local pkgs=(git curl python3 python3-pip python3-venv nodejs npm cmake ninja-build build-essential pkg-config)

  if ensure_cmd apt-get; then
    sudo apt-get update
    sudo apt-get install -y "${pkgs[@]}" || true
    if [ "${ID:-}" = "ubuntu" ] && [ "${VERSION_ID:-}" = "24.04" ]; then
      sudo apt-get install -y libcurl4-openssl-dev libopenblas-dev || true
      if ! command -v nvcc >/dev/null 2>&1; then
        sudo apt-get install -y nvidia-cuda-toolkit || true
      fi
    fi
  elif ensure_cmd dnf; then
    sudo dnf install -y git curl python3 python3-pip nodejs npm cmake ninja-build gcc-c++ make pkgconfig || true
  elif ensure_cmd pacman; then
    sudo pacman -Sy --noconfirm git curl python python-pip nodejs npm cmake ninja base-devel pkgconf || true
  elif ensure_cmd zypper; then
    sudo zypper install -y git curl python3 python3-pip nodejs npm cmake ninja gcc-c++ make pkg-config || true
  fi
}

mkdir -p "$STATE_DIR" "$APPS_DIR" "$BIN_DIR" "$MODELS_DIR" "$LAUNCHERS_DIR" "$CONFIG_DIR" "$ASSETS_DIR"
mkdir -p "$INSTALL_ROOT/docs"

if [ "$LOCAL_QWEN_SKIP_PACKAGE_INSTALL" != "1" ]; then
  ensure_packages_linux
fi

if [ "$LOCAL_QWEN_SKIP_PREREQ_CHECKS" != "1" ]; then
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
fi

if [ "$LOCAL_QWEN_SKIP_SOURCE_CLONE" = "1" ]; then
  mkdir -p "$APPS_DIR/llama.cpp" "$APPS_DIR/llama.cpp-turboquant"
elif [ ! -d "$APPS_DIR/llama.cpp" ]; then
  git clone https://github.com/ggml-org/llama.cpp.git "$APPS_DIR/llama.cpp"
fi

if [ "$LOCAL_QWEN_SKIP_SOURCE_CLONE" = "1" ]; then
  :
elif [ ! -d "$APPS_DIR/llama.cpp-turboquant" ]; then
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

if [ "$LOCAL_QWEN_SKIP_OPENCODE_INSTALL" = "1" ]; then
  :
elif ! command -v opencode >/dev/null 2>&1; then
  npm install -g opencode-ai
fi

cp -R "$REPO_ROOT/launcher/linux/." "$LAUNCHERS_DIR/"
cp -R "$REPO_ROOT/config/profiles/." "$CONFIG_DIR/profiles/"
mkdir -p "$ASSETS_DIR/icons"
cp -R "$REPO_ROOT/assets/icons/." "$ASSETS_DIR/icons/"
cp "$REPO_ROOT/version.json" "$INSTALL_ROOT/version.json"
if [ -f "$REPO_ROOT/release-notes.txt" ]; then
  cp "$REPO_ROOT/release-notes.txt" "$INSTALL_ROOT/docs/release-notes.txt"
else
  printf 'Release notes nisu dostupne u ovom payload-u.\n' > "$INSTALL_ROOT/docs/release-notes.txt"
fi

chmod +x "$LAUNCHERS_DIR/"*.sh

LLAMA_SERVER_EXE=""
if [ -x "$APPS_DIR/llama.cpp/build/bin/llama-server" ]; then
  LLAMA_SERVER_EXE="$APPS_DIR/llama.cpp/build/bin/llama-server"
fi

GPU_MIB="0"
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_MIB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d '[:space:]')"
fi

RAM_GIB="$(python3 - <<'PY'
import math
value = 0
with open("/proc/meminfo", "r", encoding="utf-8", errors="ignore") as handle:
    for line in handle:
        if line.startswith("MemTotal:"):
            value = round(int(line.split()[1]) / 1024 / 1024)
            break
print(value)
PY
)"

MODEL_META_JSON="$(python3 "$REPO_ROOT/scripts/local_qwen_runtime.py" recommend --defaults "$DEFAULTS_PATH" --gpu-mib "${GPU_MIB:-0}" --ram-gib "${RAM_GIB:-0}" --cpu-threads "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)")"

MODEL_REPO="$(python3 - <<'PY' "$MODEL_META_JSON"
import json, sys
payload = json.loads(sys.argv[1])
model = payload["recommendedModel"]
print(model["source"])
PY
)"
MODEL_FILENAME="$(python3 - <<'PY' "$MODEL_META_JSON"
import json, sys
payload = json.loads(sys.argv[1])
model = payload["recommendedModel"]
print(model["filename"])
PY
)"
MODEL_PATH="$MODELS_DIR/$MODEL_FILENAME"
MODEL_VENV_DIR="$STATE_DIR/model-download-venv"
MODEL_MIN_EXPECTED_BYTES="$(python3 - <<'PY' "$MODEL_META_JSON"
import json, sys
payload = json.loads(sys.argv[1])
model = payload["recommendedModel"]
print(model.get("minExpectedBytes", 0))
PY
)"

if [ "$SKIP_MODEL_DOWNLOAD" != "1" ] && { [ ! -f "$MODEL_PATH" ] || [ "$(stat -c%s "$MODEL_PATH" 2>/dev/null || echo 0)" -lt "$MODEL_MIN_EXPECTED_BYTES" ]; }; then
  python3 -m venv "$MODEL_VENV_DIR"
  "$MODEL_VENV_DIR/bin/python" -m pip install -U pip
  "$MODEL_VENV_DIR/bin/python" -m pip install -U huggingface_hub
  "$MODEL_VENV_DIR/bin/python" - <<'PY' "$MODEL_REPO" "$MODEL_FILENAME" "$MODELS_DIR"
from huggingface_hub import hf_hub_download
import sys
repo_id, filename, local_dir = sys.argv[1:4]
hf_hub_download(repo_id=repo_id, filename=filename, local_dir=local_dir, local_dir_use_symlinks=False)
PY

  if [ ! -f "$MODEL_PATH" ]; then
    echo "Model download nije proizveo ocekivani fajl: $MODEL_PATH"
    exit 1
  fi

  if [ "$MODEL_MIN_EXPECTED_BYTES" -gt 0 ] && [ "$(stat -c%s "$MODEL_PATH")" -lt "$MODEL_MIN_EXPECTED_BYTES" ]; then
    echo "Model je skinut nepotpuno: $MODEL_PATH"
    exit 1
  fi
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
  "mlock": true,
  "targetDistro": "ubuntu24.04"
}
EOF

PROFILE="$PROFILE" \
CONTEXT_SIZE="${CONTEXT_SIZE:-}" \
MAX_OUTPUT_TOKENS="${MAX_OUTPUT_TOKENS:-}" \
BUILD_STEPS="${BUILD_STEPS:-}" \
PLAN_STEPS="${PLAN_STEPS:-}" \
GENERAL_STEPS="${GENERAL_STEPS:-}" \
EXPLORE_STEPS="${EXPLORE_STEPS:-}" \
WORKING_DIRECTORY="${WORKING_DIRECTORY:-}" \
"$LAUNCHERS_DIR/configure-settings.sh"

python3 - <<'PY' "$STATE_DIR/settings.json"
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
data.setdefault("llama", {})
data["llama"]["contextSizeCustomized"] = False
data["llama"]["maxOutputTokensCustomized"] = False
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

if [ "$SKIP_RUNTIME_BUILD" != "1" ]; then
  "$LAUNCHERS_DIR/build-runtime.sh"
fi

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

LLAMA_UPSTREAM_PATH="$APPS_DIR/llama.cpp/build/bin/llama-server"
TURBO_RUNTIME_PATH="$APPS_DIR/llama.cpp-turboquant/build-cuda/bin/llama-server"
OPENCODE_PATH="$(command -v opencode || true)"

python3 - <<'PY' "$INSTALL_REPORT_PATH" "$INSTALL_ROOT" "$STATE_DIR/install-state.json" "$LAUNCHERS_DIR" "$DESKTOP_DIR" "$LLAMA_UPSTREAM_PATH" "$TURBO_RUNTIME_PATH" "$MODEL_PATH" "$OPENCODE_PATH" "$PROFILE"
import json, os, sys

(report_path, install_root, state_path, launchers_dir, desktop_dir,
 llama_path, turbo_path, model_path, opencode_path, profile) = sys.argv[1:11]

report = {
    "generatedAt": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
    "platform": "linux",
    "profile": profile,
    "installRoot": install_root,
    "components": {
        "installState": {
            "path": state_path,
            "ok": os.path.isfile(state_path),
        },
        "launchers": {
            "path": launchers_dir,
            "ok": os.path.isfile(os.path.join(launchers_dir, "control-center.sh")),
        },
        "desktopLaunchers": {
            "path": desktop_dir,
            "ok": os.path.isfile(os.path.join(desktop_dir, "local-qwen-control-center.desktop")),
        },
        "llamaCppRuntime": {
            "path": llama_path,
            "ok": os.path.isfile(llama_path),
        },
        "turboQuantRuntime": {
            "path": turbo_path,
            "ok": os.path.isfile(turbo_path),
        },
        "model": {
            "path": model_path,
            "ok": os.path.isfile(model_path),
            "sizeBytes": os.path.getsize(model_path) if os.path.isfile(model_path) else 0,
        },
        "opencodeCommand": {
            "path": opencode_path,
            "ok": bool(opencode_path and os.path.isfile(opencode_path)),
        },
    },
}

with open(report_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
PY

cat <<EOF
Linux installer je pripremio lokalni stack.

Install root:
$INSTALL_ROOT

State:
$STATE_DIR/install-state.json

Install report:
$INSTALL_REPORT_PATH

Launchers:
$LAUNCHERS_DIR

Primary commands:
- $LAUNCHERS_DIR/control-center.sh
- $LAUNCHERS_DIR/build-runtime.sh
- $LAUNCHERS_DIR/start-opencode.sh
- $LAUNCHERS_DIR/verify-install.sh

Model:
$MODEL_PATH

Napomena:
- Linux tok je sada usmeren na Ubuntu 24.04
- ako CUDA/TurboQuant build ne prodje, installer zadrzava upstream llama.cpp server fallback
EOF
