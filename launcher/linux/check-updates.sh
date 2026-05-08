#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

CURRENT_VERSION="$(python3 - <<'PY' "$(get_local_qwen_root)/version.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("version", "unknown"))
PY
)"

run_runtime_engine_json latest-release --repo "joes021/Local-Qwen-3.635Ba3B-on-home-computer" --current-version "$CURRENT_VERSION"
