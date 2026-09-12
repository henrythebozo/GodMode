#!/usr/bin/env bash
# One-time local setup for the Claude Code tooling this repo enables.
#
# What the repo already does for you (via .claude/settings.json):
#   - frontend-design  (Anthropic official plugin)
#   - playwright       (Microsoft Playwright MCP, official plugin)
# Those load automatically when you open this repo in Claude Code and trust it.
#
# What a repo file CANNOT do is install local proxies or Python/npm packages
# on your machine. That's what this script is for. Run it once:
#   bash setup-claude-tools.sh
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 (install it first)"; exit 1; }; }
need node
need npm
need python3

py_install() {
  if command -v uv >/dev/null 2>&1; then
    uv tool install --upgrade "$1"
  else
    python3 -m pip install --user --upgrade "$1"
  fi
}

# --- Mem Palace: plugin expects the `mempalace-mcp` binary on PATH -----------
# The plugin itself is opt-in; see the mempalace note in the repo's settings.
py_install mempalace

# --- Playwright MCP: prefetch the package and a browser so first use is fast --
npx -y @playwright/mcp@latest --version >/dev/null
npx -y playwright install chromium

# --- Headroom: context-compression proxy (NOT a plugin) ----------------------
# Requires Python 3.10+. Launch Claude Code through it with: headroom wrap claude
py_install "headroom-ai[all]"

cat <<'MSG'

Done. Next steps:

  1. Open this repo in Claude Code, trust the folder, run /plugin to confirm
     frontend-design and playwright show as enabled.
  2. If you enable the mempalace plugin, run /mempalace:init once.
  3. Headroom: start Claude Code with     headroom wrap claude
MSG
