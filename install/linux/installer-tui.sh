#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_EXEC_SCRIPT="${LOCAL_QWEN_INSTALLER_TARGET_SCRIPT:-$SCRIPT_DIR/install.sh}"

prompt_with_default() {
  local label="$1"
  local default_value="$2"
  local result
  while true; do
    read -r -p "$label [$default_value]: " result
    if [ -z "$result" ]; then
      result="$default_value"
    fi
    printf '%s' "$result"
    return 0
  done
}

prompt_path_with_default() {
  local label="$1"
  local default_value="$2"
  local result
  while true; do
    result="$(prompt_with_default "$label" "$default_value")"
    case "${result,,}" in
      y|yes|n|no)
        echo "Unos '$result' izgleda kao potvrda, a ovde je potrebna putanja." >&2
        continue
        ;;
    esac
    if [[ "$result" == /* || "$result" == ~* || "$result" == .* ]]; then
      printf '%s' "$result"
      return 0
    fi
    echo "Putanja treba da pocinje sa /, ~/ ili ./ ." >&2
  done
}

prompt_choice_with_default() {
  local label="$1"
  local default_value="$2"
  shift 2
  local allowed=("$@")
  local result
  while true; do
    result="$(prompt_with_default "$label" "$default_value")"
    for item in "${allowed[@]}"; do
      if [ "$result" = "$item" ]; then
        printf '%s' "$result"
        return 0
      fi
    done
    echo "Dozvoljene vrednosti su: ${allowed[*]}" >&2
  done
}

prompt_integer_with_default() {
  local label="$1"
  local default_value="$2"
  local result
  while true; do
    result="$(prompt_with_default "$label" "$default_value")"
    if [[ "$result" =~ ^[0-9]+$ ]] && [ "$result" -gt 0 ]; then
      printf '%s' "$result"
      return 0
    fi
    echo "Ovde je potreban pozitivan ceo broj." >&2
  done
}

pick_yes_no() {
  local label="$1"
  local default_value="$2"
  local result
  while true; do
    read -r -p "$label ($default_value): " result
    result="${result,,}"
    if [ -z "$result" ]; then
      result="$default_value"
    fi
    case "$result" in
      y|yes)
        printf 'y'
        return 0
        ;;
      n|no)
        printf 'n'
        return 0
        ;;
      *)
        echo "Odgovori sa y ili n." >&2
        ;;
    esac
  done
}

echo
echo "Local Qwen Linux Installer TUI"
echo "Ubuntu 24.04 target"
echo

INSTALL_ROOT="$(prompt_path_with_default 'Install root' "$HOME/local-qwen-home")"
PROFILE="$(prompt_choice_with_default 'Profile (speed/balanced/video)' 'balanced' 'speed' 'balanced' 'video')"
CONTEXT_SIZE="$(prompt_integer_with_default 'Context size' '262144')"
MAX_OUTPUT_TOKENS="$(prompt_integer_with_default 'Max output tokens' '8192')"
BUILD_STEPS="$(prompt_integer_with_default 'OpenCode build steps' '120')"
PLAN_STEPS="$(prompt_integer_with_default 'OpenCode plan steps' '80')"
GENERAL_STEPS="$(prompt_integer_with_default 'OpenCode general steps' '100')"
EXPLORE_STEPS="$(prompt_integer_with_default 'OpenCode explore steps' '60')"
WORKING_DIRECTORY="$(prompt_path_with_default 'OpenCode working directory' "$HOME")"
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
echo "Izabrane vrednosti:"
echo "- Install root: $INSTALL_ROOT"
echo "- Profil: $PROFILE"
echo "- Context: $CONTEXT_SIZE"
echo "- Output: $MAX_OUTPUT_TOKENS"
echo "- Build steps: $BUILD_STEPS"
echo "- Plan steps: $PLAN_STEPS"
echo "- General steps: $GENERAL_STEPS"
echo "- Explore steps: $EXPLORE_STEPS"
echo "- Working dir: $WORKING_DIRECTORY"
echo "- Download model: $DOWNLOAD_MODEL_ANSWER"
echo "- Build runtime: $BUILD_RUNTIME_ANSWER"
echo
CONFIRM_INSTALL="$(pick_yes_no 'Potvrdi instalaciju? y/n' 'y')"
if [ "$CONFIRM_INSTALL" = "n" ]; then
  echo "Instalacija je otkazana."
  exit 1
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
bash "$INSTALL_EXEC_SCRIPT"
