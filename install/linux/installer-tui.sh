#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prompt_with_default() {
  local label="$1"
  local default_value="$2"
  local result
  read -r -p "$label [$default_value]: " result
  if [ -z "$result" ]; then
    result="$default_value"
  fi
  printf '%s' "$result"
}

pick_yes_no() {
  local label="$1"
  local default_value="$2"
  local result
  read -r -p "$label ($default_value): " result
  result="${result,,}"
  if [ -z "$result" ]; then
    result="$default_value"
  fi
  printf '%s' "$result"
}

echo
echo "Local Qwen Linux Installer TUI"
echo "Ubuntu 24.04 target"
echo

INSTALL_ROOT="$(prompt_with_default 'Install root' "$HOME/local-qwen-home")"
PROFILE="$(prompt_with_default 'Profile (speed/balanced/video)' 'balanced')"
CONTEXT_SIZE="$(prompt_with_default 'Context size' '262144')"
MAX_OUTPUT_TOKENS="$(prompt_with_default 'Max output tokens' '8192')"
BUILD_STEPS="$(prompt_with_default 'OpenCode build steps' '120')"
PLAN_STEPS="$(prompt_with_default 'OpenCode plan steps' '80')"
GENERAL_STEPS="$(prompt_with_default 'OpenCode general steps' '100')"
EXPLORE_STEPS="$(prompt_with_default 'OpenCode explore steps' '60')"
WORKING_DIRECTORY="$(prompt_with_default 'OpenCode working directory' "$HOME")"
DOWNLOAD_MODEL_ANSWER="$(pick_yes_no 'Download model now? y/n' 'y')"
BUILD_RUNTIME_ANSWER="$(pick_yes_no 'Build llama.cpp runtime now? y/n' 'y')"

SKIP_MODEL_DOWNLOAD=0
SKIP_RUNTIME_BUILD=0
if [ "$DOWNLOAD_MODEL_ANSWER" = "n" ]; then
  SKIP_MODEL_DOWNLOAD=1
fi
if [ "$BUILD_RUNTIME_ANSWER" = "n" ]; then
  SKIP_RUNTIME_BUILD=1
fi

echo
echo "Pokrecem instalaciju sa izabranim vrednostima..."
echo

INSTALL_ROOT="$INSTALL_ROOT" \
PROFILE="$PROFILE" \
CONTEXT_SIZE="$CONTEXT_SIZE" \
MAX_OUTPUT_TOKENS="$MAX_OUTPUT_TOKENS" \
BUILD_STEPS="$BUILD_STEPS" \
PLAN_STEPS="$PLAN_STEPS" \
GENERAL_STEPS="$GENERAL_STEPS" \
EXPLORE_STEPS="$EXPLORE_STEPS" \
WORKING_DIRECTORY="$WORKING_DIRECTORY" \
SKIP_MODEL_DOWNLOAD="$SKIP_MODEL_DOWNLOAD" \
SKIP_RUNTIME_BUILD="$SKIP_RUNTIME_BUILD" \
bash "$SCRIPT_DIR/install.sh"
