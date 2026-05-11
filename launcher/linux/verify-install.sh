#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
OPENCODE_PATH="${HOME}/.config/opencode/opencode.json"
REPORT_PATH="$ROOT/state/install-report.json"
HEALTH_URL="$(get_health_url)"
SERVICE_STATUS_JSON="$(get_effective_service_status_json)"

python3 - <<'PY' "$STATE_PATH" "$SETTINGS_PATH" "$OPENCODE_PATH" "$ROOT" "$REPORT_PATH" "$HEALTH_URL" "$SERVICE_STATUS_JSON"
import json, os, sys
import urllib.request

state_path, settings_path, opencode_path, root, report_path, health_url, service_status_json = sys.argv[1:8]
with open(state_path, "r", encoding="utf-8-sig") as f:
    state = json.load(f)
service = json.loads(service_status_json)

health_ok = False
try:
    with urllib.request.urlopen(health_url, timeout=3) as response:
        health_ok = b'"status":"ok"' in response.read().replace(b" ", b"")
except Exception:
    health_ok = False

checks = [
    ("Install root", os.path.isdir(root), root),
    ("State file", os.path.isfile(state_path), state_path),
    ("Settings file", os.path.isfile(settings_path), settings_path),
    ("llama server", os.path.isfile(state.get("turboServerExe") or state.get("llamaServerExe", "")), state.get("turboServerExe") or state.get("llamaServerExe", "")),
    ("Model file", os.path.isfile(state.get("modelFile", "")), state.get("modelFile", "")),
    ("OpenCode config", os.path.isfile(opencode_path), opencode_path),
    ("Install report", os.path.isfile(report_path), report_path),
]

bad = False
for name, ok, value in checks:
    print(f"{name:16} : {'OK' if ok else 'FAIL'} : {value}")
    bad = bad or not ok

service_state = service.get("effectiveState", "inactive")
service_reason = service.get("reason", "")
if health_ok:
    print(f"{'Health endpoint':16} : OK   : {health_url}")
elif service_state == "inactive":
    print(f"{'Health endpoint':16} : INFO : {health_url} (server trenutno nije aktivan)")
elif service_state == "warming":
    print(f"{'Health endpoint':16} : INFO : {health_url} ({service_reason})")
else:
    print(f"{'Health endpoint':16} : FAIL : {health_url} ({service_reason})")
    bad = True

if os.path.isfile(report_path):
    print("\nInstall report:")
    with open(report_path, "r", encoding="utf-8-sig") as f:
        report = json.load(f)
    if health_ok:
        report["warnings"] = [
            warning for warning in (report.get("warnings") or [])
            if ("wdac" not in str(warning).lower()) and ("app control" not in str(warning).lower())
        ]
    print(json.dumps(report, indent=4, ensure_ascii=False))

raise SystemExit(1 if bad else 0)
PY
