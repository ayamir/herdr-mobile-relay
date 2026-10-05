#!/usr/bin/env bash
# Deploy the Herdr Mobile Relay "mac local QoL" bundle on a macOS user account.
#
# This is machine-specific convenience tooling kept in a personal fork, not an
# upstream feature. It installs:
#   - a launchd user service running the relay in gateway (WebRTC) mode,
#   - a watchdog that re-registers after boot and self-heals an unhealthy relay,
#   - a `hrelay` zsh helper and its zsh-abbr abbreviations.
#
# Idempotent: safe to re-run. It never prints or touches relay/device secrets.
set -euo pipefail

BUNDLE="$(cd "$(dirname "$0")" && pwd)"
CFG="$HOME/.config/herdr/plugins/config/herdr-mobile-relay.events"
LA="$HOME/Library/LaunchAgents"
ZSH_DIR="$HOME/.config/zsh"
ZSH_FUNC="$ZSH_DIR/herdr-relay.zsh"
ABBR_FILE="$HOME/.config/zsh-abbr/user-abbreviations"
ZSHRC="$HOME/.zshrc"
UID_NUM="$(id -u)"

say() { printf '==> %s\n' "$*"; }

if [ ! -d "$CFG" ]; then
    echo "missing plugin config dir: $CFG" >&2
    echo "Run the Herdr Mobile Relay setup once (it creates relay.env), then retry." >&2
    exit 1
fi

# 1) helper scripts live next to relay.env so plugin updates never touch them
cp "$BUNDLE/scripts/relay-watchdog.sh"        "$CFG/relay-watchdog.sh"
cp "$BUNDLE/scripts/gateway-noop-tunnel.sh"   "$CFG/gateway-noop-tunnel.sh"
cp "$BUNDLE/scripts/gateway-noop-tunnel.conf" "$CFG/gateway-noop-tunnel.conf"
chmod 700 "$CFG/relay-watchdog.sh" "$CFG/gateway-noop-tunnel.sh" "$CFG/gateway-noop-tunnel.conf"
say "installed helper scripts into $CFG"

# 2) launchd plists (paths are stored as __HOME__ in the bundle)
mkdir -p "$LA"
for p in com.herdr-mobile-relay.service com.herdr-mobile-relay.watchdog; do
    sed "s|__HOME__|$HOME|g" "$BUNDLE/launchd/$p.plist" > "$LA/$p.plist"
    chmod 644 "$LA/$p.plist"
    plutil -lint "$LA/$p.plist" >/dev/null
    say "wrote $LA/$p.plist"
done

# 3) zsh helper, sourced from ~/.zshrc
mkdir -p "$ZSH_DIR"
cp "$BUNDLE/zsh/herdr-relay.zsh" "$ZSH_FUNC"
if ! grep -qF 'herdr-relay.zsh' "$ZSHRC" 2>/dev/null; then
    printf '\n# Herdr Mobile Relay helper (hrelay)\n[ -r ~/.config/zsh/herdr-relay.zsh ] && source ~/.config/zsh/herdr-relay.zsh\n' >> "$ZSHRC"
    say "added source line to $ZSHRC"
fi

# 4) zsh-abbr abbreviations
if [ -d "$(dirname "$ABBR_FILE")" ]; then
    touch "$ABBR_FILE"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -qxF "$line" "$ABBR_FILE" || printf '%s\n' "$line" >> "$ABBR_FILE"
    done < "$BUNDLE/zsh-abbr/herdr-abbrs"
    say "ensured abbreviations in $ABBR_FILE"
fi

# 5) (re)load the launchd jobs
for p in com.herdr-mobile-relay.service com.herdr-mobile-relay.watchdog; do
    launchctl bootout "gui/$UID_NUM/$p" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$LA/$p.plist"
    say "loaded $p"
done

# 6) seed the watchdog boot marker so it does not force a restart on this run
sysctl -n kern.boottime | grep -oE 'sec = [0-9]+' | head -1 | tr -dc '0-9' > "$CFG/.watchdog-boot"

say "done. Open a new shell and run: hrelay doctor"
