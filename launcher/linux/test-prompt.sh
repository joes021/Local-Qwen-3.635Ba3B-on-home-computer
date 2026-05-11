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

python3 - <<'PY' "$STATE_PATH" "$PROMPT" "$(get_runtime_engine_path)" "$(get_token_metrics_history_path)"
import json, sys, urllib.request, time, tempfile, subprocess, os

state_path, prompt, runtime_script, history_path = sys.argv[1:5]
with open(state_path, "r", encoding="utf-8-sig") as f:
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

started = time.perf_counter()
with urllib.request.urlopen(req, timeout=60) as response:
    payload = json.loads(response.read().decode("utf-8"))
elapsed_ms = (time.perf_counter() - started) * 1000.0

payload["_elapsed_ms"] = elapsed_ms
payload["_measured_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".json") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    temp_response = handle.name

metrics_result = subprocess.run(
    [sys.executable, runtime_script, "token-metrics", "--response-file", temp_response, "--history-file", history_path, "--label", "test-prompt"],
    capture_output=True,
    text=True,
    check=True,
)
os.unlink(temp_response)
metrics = json.loads(metrics_result.stdout)

choice = payload["choices"][0]
message = choice.get("message") or {}
content = message.get("content") or ""
reasoning = message.get("reasoning_content") or ""

print("Smoke test odgovor:")
if content.strip():
    print(content)
elif reasoning.strip():
    print(reasoning.strip())
    print("Napomena: model nije vratio finalni tekst, pa je prikazan reasoning sadržaj.")
    print(f"Finish reason: {choice.get('finish_reason')}")
else:
    print("(prazan odgovor)")
    print(f"Finish reason: {choice.get('finish_reason')}")
print("Benchmark:")
print(f"Prompt tok/s: {metrics['current']['promptTokensPerSecond']}")
print(f"Output tok/s: {metrics['current']['completionTokensPerSecond']}")
print(f"Ukupno ms: {metrics['current']['totalMs']}")
PY
