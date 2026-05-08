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

get_settings_path() {
  echo "$(get_local_qwen_root)/state/settings.json"
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
