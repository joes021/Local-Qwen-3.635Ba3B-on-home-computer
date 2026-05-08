#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
DIAG_DIR="$ROOT/state/diagnostics"
STAMP="$(date +%Y%m%d-%H%M%S)"
BUNDLE_DIR="$DIAG_DIR/bundle-$STAMP"
ARCHIVE_PATH="$DIAG_DIR/local-qwen-diagnostics-$STAMP.tar.gz"

mkdir -p "$BUNDLE_DIR"

copy_if_present() {
  local path="$1"
  if [ -n "$path" ] && [ -f "$path" ]; then
    cp "$path" "$BUNDLE_DIR/"
  fi
}

copy_if_present "$ROOT/state/install-state.json"
copy_if_present "$ROOT/state/settings.json"
copy_if_present "$ROOT/state/install-report.json"
copy_if_present "$ROOT/state/install-summary.txt"
copy_if_present "$ROOT/state/agent-launch-settings.json"
copy_if_present "$ROOT/version.json"
copy_if_present "$HOME/.config/opencode/opencode.json"

latest_log="$(find "$ROOT/logs" -maxdepth 1 -type f 2>/dev/null | sort | tail -n 4 || true)"
for path in $latest_log; do
  copy_if_present "$path"
done

python3 - <<'PY' "$BUNDLE_DIR/diagnostics-meta.json" "$ROOT"
import json, os, subprocess, sys
target, root = sys.argv[1:3]
version = "unknown"
version_path = os.path.join(root, "version.json")
if os.path.exists(version_path):
    with open(version_path, "r", encoding="utf-8") as f:
        version = json.load(f).get("version", "unknown")
payload = {
    "generatedAt": __import__("datetime").datetime.utcnow().isoformat(),
    "appVersion": version,
    "installRoot": root,
}
with open(target, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
PY

tar -czf "$ARCHIVE_PATH" -C "$BUNDLE_DIR" .
echo "Diagnostics archive: $ARCHIVE_PATH"
