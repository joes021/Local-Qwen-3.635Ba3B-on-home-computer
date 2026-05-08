#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
LOG_DIR="$ROOT/logs"
INSTALL_SUMMARY="$ROOT/state/install-summary.txt"
INSTALL_REPORT="$ROOT/state/install-report.json"

latest_stdout="$(find "$LOG_DIR" -maxdepth 1 -type f -name 'llama-*.out.log' 2>/dev/null | sort | tail -n 1 || true)"
latest_stderr="$(find "$LOG_DIR" -maxdepth 1 -type f -name 'llama-*.err.log' 2>/dev/null | sort | tail -n 1 || true)"

echo "Local Qwen log viewer"
echo "Log folder: $LOG_DIR"
echo "Latest stdout: ${latest_stdout:-nema}"
echo "Latest stderr: ${latest_stderr:-nema}"
echo "Install summary: $( [ -f "$INSTALL_SUMMARY" ] && echo "$INSTALL_SUMMARY" || echo "nema" )"
echo "Install report: $( [ -f "$INSTALL_REPORT" ] && echo "$INSTALL_REPORT" || echo "nema" )"
echo

if [ -n "$latest_stderr" ] && [ -f "$latest_stderr" ]; then
  echo "===== STDERR ====="
  cat "$latest_stderr"
  echo
fi

if [ -n "$latest_stdout" ] && [ -f "$latest_stdout" ]; then
  echo "===== STDOUT ====="
  cat "$latest_stdout"
  echo
fi

if [ -f "$INSTALL_SUMMARY" ]; then
  echo "===== INSTALL SUMMARY ====="
  cat "$INSTALL_SUMMARY"
  echo
fi

if [ -f "$INSTALL_REPORT" ]; then
  echo "===== INSTALL REPORT ====="
  cat "$INSTALL_REPORT"
  echo
fi
