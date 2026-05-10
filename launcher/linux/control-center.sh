#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TERM="${TERM:-xterm-256color}"
exec "$SCRIPT_DIR/control-center-dashboard.sh"
