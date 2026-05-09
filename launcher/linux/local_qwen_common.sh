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

get_token_metrics_history_path() {
  echo "$(get_local_qwen_root)/state/token-metrics-history.json"
}

update_token_metrics_from_latest_logs() {
  local lifecycle_json stderr_path
  lifecycle_json="$(get_service_lifecycle_json)"
  stderr_path="$(python3 - <<'PY' "$lifecycle_json"
import json, sys
print(json.loads(sys.argv[1]).get("stderr", "") or "")
PY
)"
  if [ -z "$stderr_path" ] || [ ! -f "$stderr_path" ]; then
    return 0
  fi
  run_runtime_engine_json log-token-metrics --log-file "$stderr_path" --history-file "$(get_token_metrics_history_path)" --label "live-log" 2>/dev/null || true
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

get_download_candidates_json() {
  local gpu_mib="${1:-0}"
  local ram_gib="${2:-0}"
  local cpu_threads="${3:-0}"
  run_runtime_engine_json download-candidates --defaults "$(get_defaults_path)" --gpu-mib "$gpu_mib" --ram-gib "$ram_gib" --cpu-threads "$cpu_threads"
}

get_settings_presets_json() {
  local gpu_mib="${1:-0}"
  local ram_gib="${2:-0}"
  local cpu_threads="${3:-0}"
  run_runtime_engine_json settings-presets --defaults "$(get_defaults_path)" --gpu-mib "$gpu_mib" --ram-gib "$ram_gib" --cpu-threads "$cpu_threads"
}

get_settings_preset_preview_json() {
  local gpu_mib="${1:-0}"
  local ram_gib="${2:-0}"
  local cpu_threads="${3:-0}"
  local preset_id="${4:-}"
  local current_profile="${5:-balanced}"
  local current_context="${6:-262144}"
  local current_output="${7:-8192}"
  local current_build="${8:-120}"
  local current_plan="${9:-80}"
  local current_general="${10:-100}"
  local current_explore="${11:-60}"
  run_runtime_engine_json settings-preset-preview \
    --defaults "$(get_defaults_path)" \
    --gpu-mib "$gpu_mib" \
    --ram-gib "$ram_gib" \
    --cpu-threads "$cpu_threads" \
    --preset-id "$preset_id" \
    --current-profile "$current_profile" \
    --current-context "$current_context" \
    --current-output "$current_output" \
    --current-build "$current_build" \
    --current-plan "$current_plan" \
    --current-general "$current_general" \
    --current-explore "$current_explore"
}

get_installed_model_ids_csv() {
  local state_path defaults_path models_dir
  state_path="$(get_install_state_path)"
  defaults_path="$(get_defaults_path)"
  models_dir="$(get_local_qwen_root)/models"
  python3 - <<'PY' "$state_path" "$defaults_path" "$models_dir"
import json, os, sys
state_path, defaults_path, models_dir = sys.argv[1:4]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)
result = []
for item in defaults.get("modelChoices", {}).values():
    path = os.path.join(models_dir, item.get("filename", ""))
    minimum = int(item.get("minExpectedBytes", 0) or 0)
    if os.path.isfile(path) and (minimum <= 0 or os.path.getsize(path) >= minimum):
        result.append(item.get("id"))
print(",".join(result))
PY
}

get_model_browser_json() {
  local gpu_mib="${1:-0}"
  local ram_gib="${2:-0}"
  local cpu_threads="${3:-0}"
  local current_model_id="${4:-}"
  local installed_model_ids="${5:-}"
  local installed_model_sizes_json="${6:-{}}"
  local free_disk_gib="${7:--1}"
  local search="${8:-}"
  local family="${9:-}"
  shift 9 || true
  run_runtime_engine_json model-browser \
    --defaults "$(get_defaults_path)" \
    --gpu-mib "$gpu_mib" \
    --ram-gib "$ram_gib" \
    --cpu-threads "$cpu_threads" \
    --current-model-id "$current_model_id" \
    --installed-model-ids "$installed_model_ids" \
    --installed-model-sizes-json "$installed_model_sizes_json" \
    --free-disk-gib "$free_disk_gib" \
    --search "$search" \
    --family "$family" \
    "$@"
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

get_health_center_json() {
  local state_path report_path lifecycle_state has_server has_model has_runtime has_config warnings_json profile model_id
  state_path="$(get_install_state_path)"
  report_path="$(get_local_qwen_root)/state/install-report.json"
  lifecycle_state="$(python3 - <<'PY' "$(get_service_lifecycle_json)"
import json, sys
print(json.loads(sys.argv[1]).get("state", "inactive"))
PY
)"
  profile="$(get_saved_profile)"
  model_id="$(python3 - <<'PY' "$state_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelId", ""))
PY
)"
  if test_llama_health; then has_server="true"; else has_server="false"; fi
  if model_file_looks_complete "$(python3 - <<'PY' "$state_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelFile", ""))
PY
)"; then has_model="true"; else has_model="false"; fi
  if [ -x "$(get_local_qwen_root)/apps/llama.cpp/build/bin/llama-server" ] || [ -x "$(get_local_qwen_root)/apps/llama.cpp-turboquant/build-cuda/bin/llama-server" ]; then has_runtime="true"; else has_runtime="false"; fi
  if [ -f "$HOME/.config/opencode/opencode.json" ]; then has_config="true"; else has_config="false"; fi
  warnings_json="$(python3 - <<'PY' "$report_path"
import json, os, sys
path = sys.argv[1]
warnings = []
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            warnings = json.load(f).get("warnings", []) or []
    except Exception:
        warnings = []
print(json.dumps(warnings))
PY
)"
  run_runtime_engine_json health-center \
    --has-server "$has_server" \
    --has-model "$has_model" \
    --has-runtime "$has_runtime" \
    --has-opencode-config "$has_config" \
    --has-install-report "$( [ -f "$report_path" ] && echo true || echo false )" \
    --lifecycle-state "$lifecycle_state" \
    --model-id "$model_id" \
    --profile "$profile" \
    --warnings-json "$warnings_json"
}

get_repair_plan_json() {
  local state_path report_path lifecycle_state has_server has_model has_runtime has_config warnings_json profile model_id
  state_path="$(get_install_state_path)"
  report_path="$(get_local_qwen_root)/state/install-report.json"
  lifecycle_state="$(python3 - <<'PY' "$(get_service_lifecycle_json)"
import json, sys
print(json.loads(sys.argv[1]).get("state", "inactive"))
PY
)"
  profile="$(get_saved_profile)"
  model_id="$(python3 - <<'PY' "$state_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelId", ""))
PY
)"
  if test_llama_health; then has_server="true"; else has_server="false"; fi
  if model_file_looks_complete "$(python3 - <<'PY' "$state_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f).get("modelFile", ""))
PY
)"; then has_model="true"; else has_model="false"; fi
  if [ -x "$(get_local_qwen_root)/apps/llama.cpp/build/bin/llama-server" ] || [ -x "$(get_local_qwen_root)/apps/llama.cpp-turboquant/build-cuda/bin/llama-server" ]; then has_runtime="true"; else has_runtime="false"; fi
  if [ -f "$HOME/.config/opencode/opencode.json" ]; then has_config="true"; else has_config="false"; fi
  warnings_json="$(python3 - <<'PY' "$report_path"
import json, os, sys
path = sys.argv[1]
warnings = []
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            warnings = json.load(f).get("warnings", []) or []
    except Exception:
        warnings = []
print(json.dumps(warnings))
PY
)"
  run_runtime_engine_json repair-plan \
    --has-server "$has_server" \
    --has-model "$has_model" \
    --has-runtime "$has_runtime" \
    --has-opencode-config "$has_config" \
    --has-install-report "$( [ -f "$report_path" ] && echo true || echo false )" \
    --lifecycle-state "$lifecycle_state" \
    --model-id "$model_id" \
    --profile "$profile" \
    --warnings-json "$warnings_json"
}

get_repair_summary_json() {
  local path
  path="$(get_local_qwen_root)/state/repair-summary.json"
  python3 - <<'PY' "$path"
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            print(json.dumps(json.load(f)))
            raise SystemExit(0)
    except Exception:
        pass
print("null")
PY
}

get_token_metrics_summary_json() {
  local live_json
  live_json="$(update_token_metrics_from_latest_logs)"
  if [ -n "${live_json:-}" ]; then
    printf '%s\n' "$live_json"
    return 0
  fi

  local history_path
  history_path="$(get_token_metrics_history_path)"
  python3 - <<'PY' "$history_path"
import json, os, sys
path = sys.argv[1]
history = []
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            history = json.load(f)
    except Exception:
        history = []
current = history[-1] if history else None
averages = {
    "promptTokensPerSecond": 0.0,
    "completionTokensPerSecond": 0.0,
    "totalTokensPerSecond": 0.0,
}
if history:
    averages["promptTokensPerSecond"] = round(sum(item.get("promptTokensPerSecond", 0.0) for item in history) / len(history), 2)
    averages["completionTokensPerSecond"] = round(sum(item.get("completionTokensPerSecond", 0.0) for item in history) / len(history), 2)
    averages["totalTokensPerSecond"] = round(sum(item.get("totalTokensPerSecond", 0.0) for item in history) / len(history), 2)
print(json.dumps({
    "current": current,
    "history": history[-5:],
    "historyCount": len(history),
    "averages": averages,
}))
PY
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
