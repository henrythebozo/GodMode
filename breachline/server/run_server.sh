#!/usr/bin/env bash
# Dedicated Breachline server. Requires the Godot 4.4 binary on PATH (or set GODOT=/path/to/godot).
# Usage: server/run_server.sh [--port 27015] [--bots 8] [--map foundry] [--autostart]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
exec "$GODOT" --headless --path . -- --server "$@"
