#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"
ROOT="$(get_local_qwen_root)"

CURRENT_VERSION="$(python3 - <<'PY' "$ROOT/version.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
    print(json.load(f).get("version", "unknown"))
PY
)"
CURRENT_PROFILE="$(get_saved_profile)"
CURRENT_MODEL_ID="$(python3 - <<'PY' "$(get_install_state_path)"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
    print(json.load(f).get("modelId", ""))
PY
)"

LATEST_JSON="$(run_runtime_engine_json latest-release --repo "joes021/Local-Qwen-3.635Ba3B-on-home-computer" --current-version "$CURRENT_VERSION")"
UPDATE_AVAILABLE="$(python3 - <<'PY' "$LATEST_JSON"
import json, sys
print("yes" if json.loads(sys.argv[1]).get("updateAvailable") else "no")
PY
)"
LATEST_VERSION="$(python3 - <<'PY' "$LATEST_JSON"
import json, sys
print(json.loads(sys.argv[1]).get("latestVersion", "unknown"))
PY
)"
DOWNLOAD_URL="$(python3 - <<'PY' "$LATEST_JSON"
import json, sys
print(json.loads(sys.argv[1]).get("linuxInstallerUrl", ""))
PY
)"
RELEASE_URL="$(python3 - <<'PY' "$LATEST_JSON"
import json, sys
print(json.loads(sys.argv[1]).get("releaseUrl", ""))
PY
)"

if [[ "$UPDATE_AVAILABLE" != "yes" ]]; then
  echo "Trenutna verzija: v$CURRENT_VERSION"
  echo "Latest javna verzija: v$LATEST_VERSION"
  echo "Instalacija je vec na latest verziji: v$CURRENT_VERSION"
  if [[ -n "$RELEASE_URL" ]]; then
    echo "Release URL: $RELEASE_URL"
  fi
  exit 0
fi

TARGET_DIR="$HOME/Downloads"
TARGET_PATH="$TARGET_DIR/Local-Qwen-Setup-$LATEST_VERSION.run"
mkdir -p "$TARGET_DIR"

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Nije pronadjen Linux installer URL za verziju v$LATEST_VERSION"
  exit 1
fi

echo "Trenutna verzija: v$CURRENT_VERSION"
echo "Nova verzija: v$LATEST_VERSION"
echo "Preuzimam installer u: $TARGET_PATH"
curl -L "$DOWNLOAD_URL" -o "$TARGET_PATH"
chmod +x "$TARGET_PATH"

echo "Pokrecem neinteraktivni update installer..."
INSTALL_ROOT="$ROOT" \
PROFILE="${CURRENT_PROFILE:-balanced}" \
MODEL_ID="$CURRENT_MODEL_ID" \
SKIP_MODEL_DOWNLOAD=1 \
SKIP_RUNTIME_BUILD=1 \
LOCAL_QWEN_SKIP_PACKAGE_INSTALL=1 \
LOCAL_QWEN_SKIP_SOURCE_CLONE=1 \
LOCAL_QWEN_SKIP_OPENCODE_INSTALL=1 \
"$TARGET_PATH" --cli-install
