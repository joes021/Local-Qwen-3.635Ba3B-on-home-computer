#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

ROOT="$(get_local_qwen_root)"
STATE_PATH="$(get_install_state_path)"
SETTINGS_PATH="$(get_settings_path)"
DEFAULTS_PATH="$(get_defaults_path)"
OPENCODE_CONFIG_PATH="${HOME}/.config/opencode/opencode.json"

PROFILE="${PROFILE:-}"
CONTEXT_SIZE="${CONTEXT_SIZE:-}"
MAX_OUTPUT_TOKENS="${MAX_OUTPUT_TOKENS:-}"
BUILD_STEPS="${BUILD_STEPS:-}"
PLAN_STEPS="${PLAN_STEPS:-}"
GENERAL_STEPS="${GENERAL_STEPS:-}"
EXPLORE_STEPS="${EXPLORE_STEPS:-}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-}"

mkdir -p "$(dirname "$SETTINGS_PATH")" "$(dirname "$OPENCODE_CONFIG_PATH")"

python3 - <<'PY' "$STATE_PATH" "$DEFAULTS_PATH" "$SETTINGS_PATH" "$OPENCODE_CONFIG_PATH" "$PROFILE" "$CONTEXT_SIZE" "$MAX_OUTPUT_TOKENS" "$BUILD_STEPS" "$PLAN_STEPS" "$GENERAL_STEPS" "$EXPLORE_STEPS" "$WORKING_DIRECTORY"
import json, os, sys

state_path, defaults_path, settings_path, opencode_path, profile_in, ctx_in, out_tok_in, build_in, plan_in, general_in, explore_in, workdir_in = sys.argv[1:13]

with open(state_path, "r", encoding="utf-8") as f:
    state = json.load(f)
with open(defaults_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)

existing_settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            existing_settings = json.load(f)
    except Exception:
        existing_settings = {}

existing_llama = existing_settings.get("llama", {})
existing_opencode = existing_settings.get("opencode", {})

profile = profile_in or existing_settings.get("profile", "balanced")
ctx = int(ctx_in or existing_llama.get("contextSize", defaults["profiles"][profile]["contextSize"]))
out_tok = int(out_tok_in or existing_llama.get("maxOutputTokens", 8192))
build = int(build_in or existing_opencode.get("buildSteps", defaults["opencode"]["steps"]["build"]))
plan = int(plan_in or existing_opencode.get("planSteps", defaults["opencode"]["steps"]["plan"]))
general = int(general_in or existing_opencode.get("generalSteps", defaults["opencode"]["steps"]["general"]))
explore = int(explore_in or existing_opencode.get("exploreSteps", defaults["opencode"]["steps"]["explore"]))
working_directory = workdir_in or existing_opencode.get("workingDirectory", os.path.expanduser("~"))
selected_model = None
for item in defaults.get("modelChoices", {}).values():
    if item.get("id") == state.get("modelId") or item.get("filename") == state.get("modelId"):
        selected_model = item
        break
selected_label = selected_model.get("label") if selected_model else state["modelId"]
normalized_label = str(selected_label).strip()
if normalized_label.lower().endswith(" local"):
    display_name = f"{normalized_label} (llama.cpp)"
else:
    display_name = f"{normalized_label} Local (llama.cpp)"

settings = {
    "profile": profile,
    "llama": {
        "contextSize": ctx,
        "maxOutputTokens": out_tok,
        "contextSizeCustomized": bool(ctx_in) if ctx_in else existing_llama.get("contextSizeCustomized", False),
        "maxOutputTokensCustomized": bool(out_tok_in) if out_tok_in else existing_llama.get("maxOutputTokensCustomized", False),
    },
    "opencode": {
        "buildSteps": build,
        "planSteps": plan,
        "generalSteps": general,
        "exploreSteps": explore,
        "workingDirectory": working_directory,
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
        state["modelId"]: {
            "name": display_name
        }
    },
}
config["model"] = f"local-llamacpp/{state['modelId']}"
config["small_model"] = f"local-llamacpp/{state['modelId']}"
permission = config.setdefault("permission", {})
permission["webfetch"] = "allow"
permission["websearch"] = "allow"
agent = config.setdefault("agent", {})
for name, steps in {
    "build": build,
    "plan": plan,
    "general": general,
    "explore": explore,
}.items():
    agent.setdefault(name, {})
    agent[name]["steps"] = steps

with open(opencode_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)

print(settings_path)
print(opencode_path)
PY
