#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
SETTINGS_PATH="$(get_settings_path)"
DEFAULTS_PATH="$(get_defaults_path)"
OPENCODE_CONFIG_PATH="${HOME}/.config/opencode/opencode.json"

PROFILE="${PROFILE:-balanced}"
CONTEXT_SIZE="${CONTEXT_SIZE:-262144}"
MAX_OUTPUT_TOKENS="${MAX_OUTPUT_TOKENS:-8192}"
BUILD_STEPS="${BUILD_STEPS:-120}"
PLAN_STEPS="${PLAN_STEPS:-80}"
GENERAL_STEPS="${GENERAL_STEPS:-100}"
EXPLORE_STEPS="${EXPLORE_STEPS:-60}"

mkdir -p "$(dirname "$SETTINGS_PATH")" "$(dirname "$OPENCODE_CONFIG_PATH")"

python3 - <<'PY' "$SETTINGS_PATH" "$OPENCODE_CONFIG_PATH" "$PROFILE" "$CONTEXT_SIZE" "$MAX_OUTPUT_TOKENS" "$BUILD_STEPS" "$PLAN_STEPS" "$GENERAL_STEPS" "$EXPLORE_STEPS"
import json, os, sys

settings_path, opencode_path, profile, ctx, out_tok, build, plan, general, explore = sys.argv[1:10]

settings = {
    "profile": profile,
    "llama": {
        "contextSize": int(ctx),
        "maxOutputTokens": int(out_tok),
    },
    "opencode": {
        "buildSteps": int(build),
        "planSteps": int(plan),
        "generalSteps": int(general),
        "exploreSteps": int(explore),
    },
}
with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2)

config = {}
if os.path.exists(opencode_path):
    try:
        with open(opencode_path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception:
        config = {}

provider = config.setdefault("provider", {})
provider["local-llamacpp"] = {
    "npm": "@ai-sdk/openai-compatible",
    "name": "Local llama.cpp",
    "options": {
        "baseURL": "http://127.0.0.1:8091/v1",
        "apiKey": "llama.cpp",
    },
    "models": {
        "Qwen3.6-35B-A3B-UD-IQ2_XXS.gguf": {
            "name": "Qwen 3.6 35B A3B Local (llama.cpp)"
        }
    },
}
config["model"] = "local-llamacpp/Qwen3.6-35B-A3B-UD-IQ2_XXS.gguf"
config["small_model"] = config.get("small_model", "local-llamacpp/Qwen3.6-35B-A3B-UD-IQ2_XXS.gguf")
agent = config.setdefault("agent", {})
for name, steps in {
    "build": int(build),
    "plan": int(plan),
    "general": int(general),
    "explore": int(explore),
}.items():
    agent.setdefault(name, {})
    agent[name]["steps"] = steps

with open(opencode_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)

print(settings_path)
print(opencode_path)
PY
