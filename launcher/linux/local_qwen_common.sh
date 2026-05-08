#!/usr/bin/env bash
set -euo pipefail

get_local_qwen_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$script_dir/../state/install-state.json" ]; then
    (cd "$script_dir/.." && pwd)
    return
  fi
  (cd "$script_dir/../.." && pwd)
}

get_install_state_path() {
  echo "$(get_local_qwen_root)/state/install-state.json"
}

get_defaults_path() {
  echo "$(get_local_qwen_root)/config/profiles/defaults.json"
}

get_runtime_engine_path() {
  echo "$(get_local_qwen_root)/scripts/local_qwen_runtime.py"
}

get_settings_path() {
  echo "$(get_local_qwen_root)/state/settings.json"
}

get_service_lifecycle_path() {
  echo "$(get_local_qwen_root)/state/server-lifecycle.json"
}

set_service_lifecycle_state() {
  local lifecycle_state="$1"
  local profile="${2:-}"
  local stdout_path="${3:-}"
  local stderr_path="${4:-}"
  local reason="${5:-}"
  local lifecycle_path
  lifecycle_path="$(get_service_lifecycle_path)"
  mkdir -p "$(dirname "$lifecycle_path")"
  python3 - <<'PY' "$lifecycle_path" "$lifecycle_state" "$profile" "$stdout_path" "$stderr_path" "$reason"
import json, sys, time
path, state, profile, stdout_path, stderr_path, reason = sys.argv[1:7]
payload = {
    "state": state,
    "profile": profile or None,
    "stdout": stdout_path or None,
    "stderr": stderr_path or None,
    "reason": reason or None,
    "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%S"),
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
PY
}

get_service_lifecycle_json() {
  local lifecycle_path
  lifecycle_path="$(get_service_lifecycle_path)"
  python3 - <<'PY' "$lifecycle_path"
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            print(json.dumps(json.load(f)))
            raise SystemExit(0)
    except Exception:
        pass
print(json.dumps({
    "state": "inactive",
    "profile": None,
    "stdout": None,
    "stderr": None,
    "reason": None,
    "updatedAt": None,
}))
PY
}

run_runtime_engine_json() {
  local script_path
  script_path="$(get_runtime_engine_path)"
  python3 "$script_path" "$@"
}

get_saved_working_directory() {
  local settings_path
  settings_path="$(get_settings_path)"
  python3 - <<'PY' "$settings_path"
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get("opencode", {}).get("workingDirectory", os.path.expanduser("~")))
else:
    print(os.path.expanduser("~"))
PY
}

get_saved_profile() {
  local settings_path
  settings_path="$(get_settings_path)"
  python3 - <<'PY' "$settings_path"
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get("profile", "balanced"))
else:
    print("balanced")
PY
}

get_health_url() {
  local state_path port
  state_path="$(get_install_state_path)"
  port="$(python3 - <<'PY' "$state_path"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    print(json.load(f)["port"])
PY
)"
  echo "http://127.0.0.1:${port}/health"
}

test_llama_health() {
  local url
  url="$(get_health_url)"
  curl -fsS "$url" >/dev/null 2>&1
}

get_model_min_expected_bytes() {
  local state_path defaults_path model_id
  state_path="$(get_install_state_path)"
  defaults_path="$(get_defaults_path)"
  model_id="$(python3 - <<'PY' "$state_path"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    print(json.load(f).get("modelId", ""))
PY
)"

  python3 - <<'PY' "$defaults_path" "$model_id"
import json, sys
defaults_path, model_id = sys.argv[1:3]
with open(defaults_path, 'r', encoding='utf-8') as f:
    defaults = json.load(f)
for item in defaults.get("modelChoices", {}).values():
    if item.get("id") == model_id or item.get("filename") == model_id:
        print(item.get("minExpectedBytes", 0))
        break
else:
    print(0)
PY
}

get_model_catalog_json() {
  run_runtime_engine_json catalog --defaults "$(get_defaults_path)"
}

get_recommendation_json() {
  local gpu_mib="${1:-0}"
  local ram_gib="${2:-0}"
  local cpu_threads="${3:-0}"
  run_runtime_engine_json recommend --defaults "$(get_defaults_path)" --gpu-mib "$gpu_mib" --ram-gib "$ram_gib" --cpu-threads "$cpu_threads"
}

get_agent_audit_json() {
  local security_mode="$1"
  local capability_mode="$2"
  local working_folder="$3"
  run_runtime_engine_json agent-audit --security-mode "$security_mode" --capability-mode "$capability_mode" --working-folder "$working_folder"
}

get_effective_service_status_json() {
  local lifecycle_json has_health lifecycle_state
  lifecycle_json="$(get_service_lifecycle_json)"
  if test_llama_health; then
    has_health="true"
  else
    has_health="false"
  fi
  lifecycle_state="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("state", "inactive"))
PY
)"
  run_runtime_engine_json service-status --has-health "$has_health" --lifecycle-state "$lifecycle_state"
}

model_file_looks_complete() {
  local path="$1"
  local min_bytes
  [ -f "$path" ] || return 1
  min_bytes="$(get_model_min_expected_bytes)"
  if [ "${min_bytes:-0}" -le 0 ]; then
    return 0
  fi

  local size
  size="$(python3 - <<'PY' "$path"
import os, sys
print(os.path.getsize(sys.argv[1]))
PY
)"

  [ "$size" -ge "$min_bytes" ]
}
