#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
LOG_DIR="$ROOT/logs"
INSTALL_SUMMARY="$ROOT/state/install-summary.txt"
INSTALL_REPORT="$ROOT/state/install-report.json"
MODE="${1:-}"
TAIL_LINES="${LOCAL_QWEN_LOG_TAIL_LINES:-60}"

latest_stdout="$(find "$LOG_DIR" -maxdepth 1 -type f -name 'llama-*.out.log' 2>/dev/null | sort | tail -n 1 || true)"
latest_stderr="$(find "$LOG_DIR" -maxdepth 1 -type f -name 'llama-*.err.log' 2>/dev/null | sort | tail -n 1 || true)"

print_section() {
  local title="$1"
  local path="$2"
  local mode="$3"

  [ -n "$path" ] && [ -f "$path" ] || return 0

  echo "===== $title ====="
  if [ "$mode" = "--full" ]; then
    cat "$path"
  else
    echo "Prikazujem poslednjih $TAIL_LINES linija. Pokreni sa --full za ceo sadrzaj."
    tail -n "$TAIL_LINES" "$path"
  fi
  echo
}

echo "Local Qwen log viewer"
echo "Log folder: $LOG_DIR"
echo "Latest stdout: ${latest_stdout:-nema}"
echo "Latest stderr: ${latest_stderr:-nema}"
echo "Install summary: $( [ -f "$INSTALL_SUMMARY" ] && echo "$INSTALL_SUMMARY" || echo "nema" )"
echo "Install report: $( [ -f "$INSTALL_REPORT" ] && echo "$INSTALL_REPORT" || echo "nema" )"
if [ "$MODE" != "--full" ]; then
  echo "Mode: preview (pokreni sa --full za kompletan izlaz)"
else
  echo "Mode: full"
fi
echo

print_section "STDERR" "$latest_stderr" "$MODE"
print_section "STDOUT" "$latest_stdout" "$MODE"

if [ -f "$INSTALL_SUMMARY" ]; then
  echo "===== INSTALL SUMMARY ====="
  cat "$INSTALL_SUMMARY"
  echo
fi

if [ -f "$INSTALL_REPORT" ]; then
  echo "===== INSTALL REPORT ====="
  if [ "$MODE" = "--full" ]; then
    cat "$INSTALL_REPORT"
  else
    python3 - <<'PY' "$INSTALL_REPORT"
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
with open(report_path, "r", encoding="utf-8-sig") as f:
    report = json.load(f)
print(json.dumps(report, indent=2, ensure_ascii=False))
PY
  fi
  echo
fi
