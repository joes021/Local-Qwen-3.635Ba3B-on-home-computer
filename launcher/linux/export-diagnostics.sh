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

python3 - <<'PY' "$BUNDLE_DIR/diagnostics-meta.json" "$ROOT" "$(get_runtime_engine_path)" "$(get_install_state_path)" "$(get_settings_path)"
import json, os, subprocess, sys, urllib.request
target, root, runtime_script, state_path, settings_path = sys.argv[1:6]
version = "unknown"
version_path = os.path.join(root, "version.json")
if os.path.exists(version_path):
    with open(version_path, "r", encoding="utf-8-sig") as f:
        version = json.load(f).get("version", "unknown")
with open(state_path, "r", encoding="utf-8-sig") as f:
    state = json.load(f)
with open(settings_path, "r", encoding="utf-8-sig") as f:
    settings = json.load(f)
health_url = f"http://127.0.0.1:{state.get('port', 8091)}/health"
has_server = False
try:
    with urllib.request.urlopen(health_url, timeout=3) as response:
        has_server = response.status == 200
except Exception:
    pass
payload = subprocess.run(
    [
        sys.executable,
        runtime_script,
        "onboarding-checklist",
        "--has-server", str(has_server).lower(),
        "--has-model", str(os.path.isfile(state.get("modelFile", ""))).lower(),
        "--has-opencode-config", str(os.path.isfile(os.path.expanduser("~/.config/opencode/opencode.json"))).lower(),
        "--profile", settings.get("profile", "balanced"),
        "--model-id", state.get("modelId", "n/a"),
    ],
    capture_output=True,
    text=True,
    check=True,
)
dt = __import__("datetime")
payload = {
    "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "appVersion": version,
    "installRoot": root,
    "healthUrl": health_url,
    "serverHealthy": has_server,
    "onboarding": json.loads(payload.stdout),
}
with open(target, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
PY

tar -czf "$ARCHIVE_PATH" -C "$BUNDLE_DIR" .
echo "Diagnostics archive: $ARCHIVE_PATH"
python3 - <<'PY' "$ARCHIVE_PATH"
import os, sys
path = sys.argv[1]
size_mib = os.path.getsize(path) / (1024 ** 2)
print(f"Velicina bundle-a: {size_mib:.2f} MiB")
PY
