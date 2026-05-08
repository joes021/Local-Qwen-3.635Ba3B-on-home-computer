#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

PROFILE="${1:-$(get_saved_profile)}"
PROMPT="${2:-Reply with exactly OK}"
STATE_PATH="$(get_install_state_path)"

if ! test_llama_health; then
  "$SCRIPT_DIR/start-server.sh" "$PROFILE"
  for _ in $(seq 1 30); do
    if test_llama_health; then
      break
    fi
    sleep 2
  done
fi

if ! test_llama_health; then
  echo "llama.cpp server nije dostupan."
  exit 1
fi

python3 - <<'PY' "$STATE_PATH" "$PROMPT"
import json, sys, urllib.request

state_path, prompt = sys.argv[1:3]
with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)

body = json.dumps({
    "model": state["modelId"],
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": 16,
    "temperature": 0,
}).encode("utf-8")

req = urllib.request.Request(
    f"http://127.0.0.1:{state['port']}/v1/chat/completions",
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)

with urllib.request.urlopen(req, timeout=60) as response:
    payload = json.loads(response.read().decode("utf-8"))

print("Smoke test odgovor:")
print(payload["choices"][0]["message"]["content"])
PY
