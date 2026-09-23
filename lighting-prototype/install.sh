#!/bin/bash
# Install the prototype for the current user: config + launchd agent. Undo with ./install.sh --uninstall
set -e
PROTO="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.lighting.lightd.plist"
if [ "$1" = --uninstall ]; then
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"; echo "lightd removed (config kept in ~/.lighting)"; exit 0
fi
mkdir -p "$HOME/.lighting" "$HOME/Library/LaunchAgents"
[ -f "$HOME/.lighting/config.sh" ] || cp "$PROTO/config.example.sh" "$HOME/.lighting/config.sh"
chmod +x "$PROTO"/bin/* "$PROTO"/probe/*.sh
sed -e "s|__PROTO__|$PROTO|g" -e "s|__HOME__|$HOME|g" "$PROTO/launchd/com.lighting.lightd.plist.template" > "$PLIST"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "lightd running under launchd. Config: ~/.lighting/config.sh  Logs: ~/.lighting/lightd.log"
echo "Try: $PROTO/bin/light status"
