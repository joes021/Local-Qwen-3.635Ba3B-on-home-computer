#!/usr/bin/env bash
set -euo pipefail

control_center_has_tui() {
  if [ "${LOCAL_QWEN_FORCE_PLAIN_TUI:-0}" = "1" ]; then
    return 1
  fi
  command -v whiptail >/dev/null 2>&1
}

show_info_screen() {
  local title="$1"
  local body="${2:-}"
  if control_center_has_tui; then
    whiptail --title "$title" --msgbox "${body:-Nema dodatnih detalja.}" 22 90
    return 0
  fi

  clear
  echo "$title"
  echo
  if [ -n "$body" ]; then
    printf '%s\n' "$body"
    echo
  fi
  read -r -p "Pritisni Enter za nazad..." _
}

show_warning_screen() {
  local title="$1"
  local body="${2:-}"
  show_info_screen "$title" "$body"
}

show_error_screen() {
  local title="$1"
  local body="${2:-}"
  show_info_screen "$title" "$body"
}

prompt_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  if control_center_has_tui; then
    whiptail --title "$title" --inputbox "$prompt" 14 90 "$default_value" 3>&1 1>&2 2>&3
    return $?
  fi

  local answer
  read -r -p "$prompt" answer
  printf '%s' "$answer"
}

run_menu() {
  local title="$1"
  local prompt="$2"
  shift 2

  if control_center_has_tui; then
    whiptail --title "$title" --menu "$prompt" 24 90 12 "$@" 3>&1 1>&2 2>&3
    return $?
  fi

  clear
  echo "$title"
  echo
  if [ -n "$prompt" ]; then
    printf '%s\n\n' "$prompt"
  fi

  local i
  for ((i = 1; i <= $#; i += 2)); do
    local tag="${!i}"
    local next=$((i + 1))
    local label="${!next}"
    printf '%s. %s\n' "$tag" "$label"
  done
  echo
  read -r -p "Izaberi broj i pritisni Enter: " answer
  printf '%s' "$answer"
}

run_action_with_result_screen() {
  local title="$1"
  shift
  local output summary details response temp_file
  if output="$("$@" 2>&1)"; then
    summary="$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | head -n 6)"
    if [ -z "$summary" ]; then
      summary="Akcija je zavrsena bez dodatnog izlaza."
    fi
    if control_center_has_tui; then
      response=0
      if whiptail --title "$title" --yesno "$summary\n\nPrikazi detaljan izlaz?" 20 90; then
        temp_file="$(mktemp)"
        printf '%s\n' "$output" > "$temp_file"
        whiptail --title "$title - detalji" --textbox "$temp_file" 24 100
        rm -f "$temp_file"
      fi
    else
      show_info_screen "$title" "$output"
    fi
  else
    details="$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | head -n 8)"
    if [ -z "$details" ]; then
      details="Akcija nije uspela bez korisne poruke."
    fi
    if control_center_has_tui; then
      temp_file="$(mktemp)"
      printf '%s\n' "$output" > "$temp_file"
      whiptail --title "$title - greska" --yes-button "Detalji" --no-button "Nazad" --yesno "$details" 20 90
      if [ $? -eq 0 ]; then
        whiptail --title "$title - detalji" --textbox "$temp_file" 24 100
      fi
      rm -f "$temp_file"
    else
      show_error_screen "$title" "$output"
    fi
  fi
}
