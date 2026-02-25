#!/bin/bash
# Dev script to start the canvas-host dev server and open in browser

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../web/canvas-host"

echo "Starting Vite dev server..."
npm run dev &

DEV_SERVER_PID=$!

# Wait for server to start
sleep 3

# Open in default browser
open http://localhost:5173

echo "Dev server running at http://localhost:5173"
echo "Press Ctrl+C to stop"

# Wait for interrupt
trap "kill $DEV_SERVER_PID" EXIT

wait
