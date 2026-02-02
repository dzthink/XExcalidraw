#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/web/canvas-host"
DIST_DIR="$WEB_DIR/dist"

cd "$WEB_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to build the web host." >&2
  exit 1
fi

npm install
npm run build

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  RESOURCES_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
  echo "Copying web bundle to $RESOURCES_DIR"
  mkdir -p "$RESOURCES_DIR"
  rsync -a --delete "$DIST_DIR/" "$RESOURCES_DIR/"
fi
