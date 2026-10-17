#!/bin/bash
set -euo pipefail

# Builds the Ubuntu desktop app: web bundle -> Tauri resources -> deb + AppImage.
# Node.js itself is not bundled; the daemon resolves it at runtime (see src-tauri/src/daemon.rs).

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN_DIR="$REPO_ROOT/src-tauri/gen/server"
DIST_DIR="$REPO_ROOT/dist"
APP_VERSION=$(node -p "require('$REPO_ROOT/package.json').version")

echo "==> Building web bundle and daemon..."
npm run build

if [ ! -f "$DIST_DIR/daemon.cjs" ] || [ ! -f "$DIST_DIR/client/menubar.html" ]; then
    echo "Error: dist/daemon.cjs or dist/client/menubar.html missing after build."
    exit 1
fi

echo "==> Staging daemon resources..."
rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR"
cp -R "$DIST_DIR" "$GEN_DIR/dist"

# esbuild keeps packages external, so the daemon needs its runtime deps (express + zod) installed.
# type=module keeps tsc's ESM output (dist/server/*.js, the Codex worker) loadable; the bundled
# entries are .cjs and stay CommonJS regardless, matching the macOS bundle's package.json.
cd "$GEN_DIR"
npm init -y --silent >/dev/null
npm pkg set name=tokendash-server version="$APP_VERSION" private=true type=module
npm pkg set dependencies.express="$(node -p "require('$REPO_ROOT/package.json').dependencies.express")"
npm pkg set dependencies.zod="$(node -p "require('$REPO_ROOT/package.json').dependencies.zod")"
npm pkg delete description main scripts
npm install --omit=dev --no-package-lock --silent

cd "$REPO_ROOT"

echo "==> Building Tauri bundles (deb + AppImage)..."
# tauri.conf.json keeps a placeholder version; take the release from package.json.
npx tauri build --config "{\"version\":\"$APP_VERSION\"}" --bundles deb,appimage
