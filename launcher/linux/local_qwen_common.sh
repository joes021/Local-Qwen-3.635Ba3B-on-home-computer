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
