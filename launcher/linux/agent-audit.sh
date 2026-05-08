#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

SECURITY_MODE="${1:-strict}"
CAPABILITY_MODE="${2:-confirm-commands}"
WORKING_FOLDER="${3:-$(get_saved_working_directory)}"

get_agent_audit_json "$SECURITY_MODE" "$CAPABILITY_MODE" "$WORKING_FOLDER"
