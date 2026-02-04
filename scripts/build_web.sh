#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/web/canvas-host"
DIST_DIR="$WEB_DIR/dist"
WEB_COPY_DEST="${WEB_COPY_DEST:-}"
WEB_SKIP_BUILD="${WEB_SKIP_BUILD:-0}"

cd "$WEB_DIR"

if [[ "$WEB_SKIP_BUILD" != "1" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to build the web host." >&2
    exit 1
  fi

  npm install
  npm run build
fi

RESOURCES_DIR=""
if [[ -n "$WEB_COPY_DEST" ]]; then
  RESOURCES_DIR="$WEB_COPY_DEST"
fi
if [[ -z "$RESOURCES_DIR" && -n "${TARGET_BUILD_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  RESOURCES_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
elif [[ -z "$RESOURCES_DIR" && -n "${BUILT_PRODUCTS_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  RESOURCES_DIR="$BUILT_PRODUCTS_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
elif [[ -z "$RESOURCES_DIR" && -n "${CONFIGURATION_BUILD_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  RESOURCES_DIR="$CONFIGURATION_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
elif [[ -z "$RESOURCES_DIR" && -n "${BUILT_PRODUCTS_DIR:-}" && -n "${CONTENTS_FOLDER_PATH:-}" ]]; then
  RESOURCES_DIR="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources"
elif [[ -z "$RESOURCES_DIR" && -n "${CONFIGURATION_BUILD_DIR:-}" && -n "${CONTENTS_FOLDER_PATH:-}" ]]; then
  RESOURCES_DIR="$CONFIGURATION_BUILD_DIR/$CONTENTS_FOLDER_PATH/Resources"
fi

if [[ -n "$RESOURCES_DIR" ]]; then
  echo "Copying web bundle to $RESOURCES_DIR"
  mkdir -p "$RESOURCES_DIR"
  rsync -a --delete "$DIST_DIR/" "$RESOURCES_DIR/"
else
  echo "Skipping bundle copy; missing build output paths."
fi
