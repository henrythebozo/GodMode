#!/usr/bin/env bash
# Serve the browser build of Breachline on localhost.
#   ./serve_web.sh            -> http://localhost:8080/play/
#   ./serve_web.sh 9000       -> custom port
# Rebuild the web export first with:  godot --headless --path breachline --export-release Web ../play/index.html
cd "$(dirname "$0")"
PORT="${1:-8080}"
echo "Breachline: http://localhost:${PORT}/play/   (Ctrl+C to stop)"
python3 -m http.server "$PORT" --bind 127.0.0.1
