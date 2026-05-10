#!/usr/bin/env bash
set -euo pipefail

show_info_screen() {
  local title="$1"
  local body="${2:-}"
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

run_action_with_result_screen() {
  local title="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    show_info_screen "$title" "$output"
  else
    show_error_screen "$title" "$output"
  fi
}
