#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION="${1:-$(python3 - <<'PY' "$REPO_ROOT/version.json"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print(json.load(f)["version"])
PY
)}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist/linux}"
STAGE_DIR="$(mktemp -d)"
PAYLOAD_DIR="$STAGE_DIR/payload"
PAYLOAD_TAR="$STAGE_DIR/payload.tar.gz"
OUTPUT_FILE="$OUTPUT_DIR/Local-Qwen-Setup-$VERSION.run"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$PAYLOAD_DIR" "$OUTPUT_DIR"

cp "$REPO_ROOT/version.json" "$PAYLOAD_DIR/"
cp "$REPO_ROOT/README.md" "$PAYLOAD_DIR/"
mkdir -p "$PAYLOAD_DIR/install" "$PAYLOAD_DIR/launcher" "$PAYLOAD_DIR/config" "$PAYLOAD_DIR/assets"
cp -R "$REPO_ROOT/install/linux" "$PAYLOAD_DIR/install/"
cp -R "$REPO_ROOT/launcher/linux" "$PAYLOAD_DIR/launcher/"
cp -R "$REPO_ROOT/config/profiles" "$PAYLOAD_DIR/config/"
cp -R "$REPO_ROOT/assets/icons" "$PAYLOAD_DIR/assets/"

cat > "$PAYLOAD_DIR/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/install/linux/installer-tui.sh" "$@"
EOF
chmod +x "$PAYLOAD_DIR/install.sh"
find "$PAYLOAD_DIR" -type f \( -name "*.sh" -o -name "*.run" \) -exec chmod +x {} \;

tar -C "$PAYLOAD_DIR" -czf "$PAYLOAD_TAR" .

cat > "$OUTPUT_FILE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SELF_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ARCHIVE_LINE="$(awk '/^__ARCHIVE_BELOW__$/ { print NR + 1; exit }' "$SELF_PATH")"
tail -n +"$ARCHIVE_LINE" "$SELF_PATH" | tar -xz -C "$WORK_DIR"
exec bash "$WORK_DIR/install.sh" "$@"
exit 0
__ARCHIVE_BELOW__
EOF

cat "$PAYLOAD_TAR" >> "$OUTPUT_FILE"
chmod +x "$OUTPUT_FILE"
echo "$OUTPUT_FILE"
