#!/usr/bin/env bash
set -euo pipefail

CONTROL_CENTER_DIALOG_HEIGHT="${CONTROL_CENTER_DIALOG_HEIGHT:-26}"
CONTROL_CENTER_DIALOG_WIDTH="${CONTROL_CENTER_DIALOG_WIDTH:-108}"
CONTROL_CENTER_MENU_HEIGHT="${CONTROL_CENTER_MENU_HEIGHT:-14}"

control_center_has_tui() {
  if [ "${LOCAL_QWEN_FORCE_PLAIN_TUI:-0}" = "1" ]; then
    return 1
  fi
  command -v whiptail >/dev/null 2>&1
}

format_panel_text() {
  local text="${1:-}"
  local width="${2:-84}"
  python3 - <<'PY' "$text" "$width"
import sys, textwrap
text = sys.argv[1]
width = int(sys.argv[2])
lines = []
for block in text.splitlines() or [""]:
    stripped = block.strip()
    if not stripped:
        lines.append("")
        continue
    wrapped = textwrap.wrap(stripped, width=width, break_long_words=False, break_on_hyphens=False)
    if not wrapped:
        lines.append("")
    else:
        lines.extend(wrapped)
formatted = "\n".join(("  " + line) if line else "" for line in lines)
print(formatted)
PY
}

show_info_screen() {
  local title="$1"
  local body="${2:-}"
  local formatted
  formatted="$(format_panel_text "${body:-Nema dodatnih detalja.}" 84)"
  if control_center_has_tui; then
    whiptail --title "$title" --msgbox "$formatted" "$CONTROL_CENTER_DIALOG_HEIGHT" "$CONTROL_CENTER_DIALOG_WIDTH"
    return 0
  fi

  clear
  echo "$title"
  echo
  if [ -n "$formatted" ]; then
    printf '%s\n' "$formatted"
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
  local formatted
  formatted="$(format_panel_text "$prompt" 78)"
  if control_center_has_tui; then
    if whiptail --title "$title" --inputbox "$formatted" 16 "$CONTROL_CENTER_DIALOG_WIDTH" "$default_value" 3>&1 1>&2 2>&3; then
      return 0
    fi
    printf '__CANCEL__'
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
  local formatted
  formatted="$(format_panel_text "$prompt" 84)"

  if control_center_has_tui; then
    local selection
    if selection="$(whiptail --title "$title" --menu "$formatted" "$CONTROL_CENTER_DIALOG_HEIGHT" "$CONTROL_CENTER_DIALOG_WIDTH" "$CONTROL_CENTER_MENU_HEIGHT" "$@" 3>&1 1>&2 2>&3)"; then
      printf '%s' "$selection"
      return 0
    fi
    printf '__BACK__'
    return 0
  fi

  clear
  echo "$title"
  echo
  if [ -n "$formatted" ]; then
    printf '%s\n\n' "$formatted"
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
      summary="$(format_panel_text "$summary" 84)"
      response=0
      if whiptail --title "$title" --yesno "$summary\n\n  Prikazi detaljan izlaz?" "$CONTROL_CENTER_DIALOG_HEIGHT" "$CONTROL_CENTER_DIALOG_WIDTH"; then
        temp_file="$(mktemp)"
        printf '%s\n' "$output" > "$temp_file"
        whiptail --title "$title - detalji" --scrolltext --textbox "$temp_file" 30 120
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
      details="$(format_panel_text "$details" 84)"
      temp_file="$(mktemp)"
      printf '%s\n' "$output" > "$temp_file"
      whiptail --title "$title - greska" --yes-button "Detalji" --no-button "Nazad" --yesno "$details" "$CONTROL_CENTER_DIALOG_HEIGHT" "$CONTROL_CENTER_DIALOG_WIDTH"
      if [ $? -eq 0 ]; then
        whiptail --title "$title - detalji" --scrolltext --textbox "$temp_file" 30 120
      fi
      rm -f "$temp_file"
    else
      show_error_screen "$title" "$output"
    fi
  fi
}
