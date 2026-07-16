#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/release/TokenDash.app"
APP_VERSION=$(node -p "require('$REPO_ROOT/package.json').version")
ARCH=$(uname -m)
DMG_PATH="$REPO_ROOT/release/TokenDash-$APP_VERSION-$ARCH.dmg"
STAGING_DIR="$REPO_ROOT/release/.dmg-staging"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: TokenDash.app not found. Run ./scripts/package-app.sh first."
    exit 1
fi

echo "==> Creating DMG..."

# Build a standard drag-to-install disk image. Finder displays the app next to
# an Applications alias so users can drag TokenDash.app directly into it.
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/TokenDash.app"
ln -s /Applications "$STAGING_DIR/Applications"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

# Remove old DMG.
rm -f "$DMG_PATH"

# Create DMG.
hdiutil create \
    -volname "TokenDash" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "$CODESIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
    echo "   Signed DMG with identity: $CODESIGN_IDENTITY"
fi

echo "✅ DMG created at $DMG_PATH"
echo "   Size: $(du -sh "$DMG_PATH" | cut -f1)"
