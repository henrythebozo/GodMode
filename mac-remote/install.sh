#!/bin/bash
# Mac Remote installer. Run ON THE MAC MINI:   bash install.sh
# - checks Node, offers to install cliclick / qrencode via Homebrew
# - generates the access token
# - installs a LaunchAgent so the server starts at login and restarts if it dies
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.macremote.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
bold() { printf '\033[1m%s\033[0m\n' "$*"; }

if [[ "$(uname)" != "Darwin" ]]; then echo "This installer is for macOS."; exit 1; fi

# ---- Node
NODE="$(command -v node || true)"
if [[ -z "$NODE" ]]; then
	for p in /opt/homebrew/bin/node /usr/local/bin/node; do [[ -x "$p" ]] && NODE="$p" && break; done
fi
if [[ -z "$NODE" ]]; then
	echo "Node.js not found."
	if command -v brew >/dev/null; then read -r -p "Install with Homebrew now? [Y/n] " a; [[ "${a:-Y}" =~ ^[Yy] ]] && brew install node && NODE="$(command -v node)"; fi
	[[ -z "$NODE" ]] && { echo "Install Node 18+ from https://nodejs.org and re-run."; exit 1; }
fi
MAJOR="$("$NODE" -p 'process.versions.node.split(".")[0]')"
if (( MAJOR < 18 )); then echo "Node $MAJOR is too old; need 18+."; exit 1; fi
bold "Node: $NODE ($("$NODE" --version))"

# ---- Optional helpers
if command -v brew >/dev/null; then
	for tool in cliclick qrencode; do
		if ! command -v "$tool" >/dev/null; then
			read -r -p "Install $tool via Homebrew? ($( [[ $tool == cliclick ]] && echo 'more reliable mouse control' || echo 'shows a QR code to log the phone in')) [Y/n] " a
			[[ "${a:-Y}" =~ ^[Yy] ]] && brew install "$tool" || true
		fi
	done
else
	echo "Homebrew not found; skipping optional tools (cliclick, qrencode). The built-in CoreGraphics fallback will be used for the mouse."
fi

# ---- Config + token
mkdir -p "$HOME/.mac-remote"
"$NODE" "$DIR/server.js" --init

# ---- LaunchAgent
bold "Installing LaunchAgent $LABEL"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|__NODE__|$NODE|g" -e "s|__DIR__|$DIR|g" -e "s|__HOME__|$HOME|g" "$DIR/com.macremote.agent.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
sleep 1.5

PORT="$("$NODE" -p 'JSON.parse(require("fs").readFileSync(process.env.HOME+"/.mac-remote/config.json")).port')"
if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then bold "Server is running on port $PORT."; else echo "Server did not answer yet; check $HOME/.mac-remote/server.log"; fi

cat <<MSG

$(bold "Next steps")
1. Permissions (one time). System Settings → Privacy & Security:
     • Screen Recording  → add:  $NODE
     • Accessibility     → add:  $NODE
   (Use the + button, press ⌘⇧G in the file dialog, paste the path above.)
   Then restart the server:  launchctl kickstart -k gui/$(id -u)/$LABEL

2. Reach it from anywhere: install Tailscale on the Mac and the phone
   (https://tailscale.com/download), sign in with the same account, then open
   http://<mac-tailscale-ip>:$PORT on the phone. Run  tail -n 30 ~/.mac-remote/server.log
   to see the login URL / QR code.

3. Keep the Mac awake so it stays reachable:
     sudo pmset -a sleep 0 disksleep 0 womp 1
   (display sleep is fine; the app has a "Wake display" button)

Logs:      tail -f ~/.mac-remote/server.log
Token:     $NODE $DIR/server.js --token
Uninstall: launchctl bootout gui/$(id -u)/$LABEL && rm "$PLIST"
MSG
