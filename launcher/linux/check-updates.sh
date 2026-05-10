#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/local_qwen_common.sh"

JSON_ONLY=0
if [[ "${1:-}" == "--json" ]]; then
  JSON_ONLY=1
fi

CURRENT_VERSION="$(python3 - <<'PY' "$(get_local_qwen_root)/version.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8-sig") as f:
    print(json.load(f).get("version", "unknown"))
PY
)"

LATEST_JSON="$(run_runtime_engine_json latest-release --repo "joes021/Local-Qwen-3.635Ba3B-on-home-computer" --current-version "$CURRENT_VERSION")"

if [[ "$JSON_ONLY" -eq 1 ]]; then
  printf '%s\n' "$LATEST_JSON"
  exit 0
fi

python3 - <<'PY' "$LATEST_JSON"
import json
import sys

info = json.loads(sys.argv[1])
current_version = str(info.get("currentVersion", "unknown"))
latest_version = str(info.get("latestVersion", "unknown"))
release_url = str(info.get("releaseUrl", ""))
update_available = bool(info.get("updateAvailable"))
ahead = bool(info.get("aheadOfPublicRelease"))
relation = str(info.get("versionRelation", "unknown"))

print(f"Trenutna verzija: v{current_version}")
print(f"Latest javna verzija: v{latest_version}")

if update_available:
    print("Dostupna je novija verzija.")
elif ahead:
    print("Instalacija je ispred poslednjeg javnog release-a.")
elif relation == "equal":
    print(f"Instalacija je vec na latest verziji: v{current_version}")
else:
    print("Nema novijih javnih azuriranja.")

if release_url:
    print(f"Release URL: {release_url}")
PY
