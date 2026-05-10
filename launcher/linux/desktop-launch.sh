#!/usr/bin/env bash
set -euo pipefail

find_terminal_launcher() {
  if command -v x-terminal-emulator >/dev/null 2>&1; then
    echo "x-terminal-emulator"
    return 0
  fi
  if command -v gnome-terminal >/dev/null 2>&1; then
    echo "gnome-terminal"
    return 0
  fi
  if command -v konsole >/dev/null 2>&1; then
    echo "konsole"
    return 0
  fi
  if command -v xfce4-terminal >/dev/null 2>&1; then
    echo "xfce4-terminal"
    return 0
  fi
  if command -v xterm >/dev/null 2>&1; then
    echo "xterm"
    return 0
  fi
  return 1
}

main() {
  if [ "$#" -lt 1 ]; then
    echo "Upotreba: desktop-launch.sh <skripta> [args...]"
    exit 1
  fi

  local target="$1"
  shift || true

  if [ ! -f "$target" ]; then
    echo "Launcher skripta nije pronadjena: $target"
    exit 1
  fi

  local terminal
  if ! terminal="$(find_terminal_launcher)"; then
    echo "Nije pronadjen terminal emulator. Pokreni rucno: $target $*"
    exit 1
  fi

  local quoted_target quoted_args inner_command
  printf -v quoted_target '%q' "$target"
  quoted_args=""
  if [ "$#" -gt 0 ]; then
    printf -v quoted_args ' %q' "$@"
  fi
  printf -v inner_command 'bash %s%s; status=$?; echo; if [ $status -eq 0 ]; then echo "Akcija je zavrsena. Pritisni Enter za zatvaranje..."; else echo "Akcija je zavrsena sa greskom ($status). Pritisni Enter za zatvaranje..."; fi; read -r _; exit $status' "$quoted_target" "$quoted_args"

  case "$terminal" in
    x-terminal-emulator)
      nohup "$terminal" -e bash -lc "$inner_command" >/dev/null 2>&1 &
      ;;
    gnome-terminal)
      nohup "$terminal" -- bash -lc "$inner_command" >/dev/null 2>&1 &
      ;;
    konsole)
      nohup "$terminal" -e bash -lc "$inner_command" >/dev/null 2>&1 &
      ;;
    xfce4-terminal)
      nohup "$terminal" --hold -e "bash -lc \"$inner_command\"" >/dev/null 2>&1 &
      ;;
    xterm)
      nohup "$terminal" -hold -e bash -lc "$inner_command" >/dev/null 2>&1 &
      ;;
    *)
      echo "Nepodrzan terminal emulator: $terminal"
      exit 1
      ;;
  esac
}

main "$@"
