#!/bin/bash
# Builds Retrospection and assembles a real .app bundle, ad-hoc signed.
#
# A proper bundle (stable bundle id + signature) gives the app a stable identity for the macOS
# privacy system, so the Input Monitoring / Accessibility grants stick instead of being re-prompted.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Retrospection.app"
CONFIG="${1:-release}"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Retrospection"
if [[ ! -f "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Retrospection"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

IDENTITY="Retrospection Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "Signing with stable identity: $IDENTITY"
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Signing ad-hoc (run Scripts/setup_signing.sh once to stop permission re-prompts)…"
    codesign --force --sign - "$APP"
fi

echo "Done: $APP"
echo "Launch with: open \"$APP\""
