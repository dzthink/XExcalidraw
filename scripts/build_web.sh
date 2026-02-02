#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/web/canvas-host"

cd "$WEB_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to build the web host." >&2
  exit 1
fi

npm install
npm run build
