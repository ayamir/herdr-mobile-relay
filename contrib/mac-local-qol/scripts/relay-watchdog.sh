#!/bin/bash
# Herdr Mobile Relay watchdog.
#
# Two jobs:
#  1. After every boot/login, once the network is reachable, force ONE clean
#     gateway re-registration with `launchctl kickstart -k`. This is what
#     recovers a phone that cannot reconnect after the computer reboots (the
#     relay looks "registered" but the phone holds a stale session).
#  2. Periodically (StartInterval), kickstart the relay service when it is not
#     ready or not registered, after a conservative failure streak and with a
#     rate limit so a genuinely broken config is not restarted in a loop.
#
# Managed by ~/Library/LaunchAgents/com.herdr-mobile-relay.watchdog.plist.
set -u

SERVICE="gui/$(id -u)/com.herdr-mobile-relay.service"
DIR="$HOME/.config/herdr/plugins/config/herdr-mobile-relay.events"
PORT="${HERDR_RELAY_PORT:-8375}"
HEALTH_URL="http://127.0.0.1:${PORT}/healthz"

# First configured gateway, used only to wait for the network after boot.
# ws(s):// is turned into http(s):// for the health probe.
GATEWAY="$(awk -F= '/^HERDR_GATEWAY_URL=/{print $2}' "$DIR/relay.env" 2>/dev/null | tr -d "'" | tr -d '"' | cut -d, -f1)"
GATEWAY="${GATEWAY:-wss://gw1.herdr-mobile.dev}"
PROBE_URL="${GATEWAY/wss:/https:}"
PROBE_URL="${PROBE_URL/ws:/http:}"

FAIL_FILE="$DIR/.watchdog-failures"
LAST_FILE="$DIR/.watchdog-last-restart"
BOOT_FILE="$DIR/.watchdog-boot"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
kickstart() { launchctl kickstart -k "$SERVICE" >/dev/null 2>&1; }

boot_sec="$(sysctl -n kern.boottime 2>/dev/null | grep -oE 'sec = [0-9]+' | head -1 | tr -dc '0-9')"

# --- 1. one clean re-registration after each boot/login ---
if [ -n "$boot_sec" ] && [ "$(cat "$BOOT_FILE" 2>/dev/null)" != "$boot_sec" ]; then
    log "new boot detected (boot=$boot_sec); waiting for network"
    for _ in $(seq 1 30); do
        curl -s -o /dev/null --max-time 5 "$PROBE_URL/healthz" 2>/dev/null && break
        sleep 5
    done
    sleep 5
    if kickstart; then
        log "post-boot clean re-registration: relay kickstarted"
    else
        log "post-boot kickstart failed"
    fi
    printf '%s\n' "$boot_sec" > "$BOOT_FILE"
    exit 0
fi

# --- 2. periodic health check ---
body="$(curl -s --max-time 8 "$HEALTH_URL" 2>/dev/null)"
if printf '%s' "$body" | grep -qE '"readiness"[[:space:]]*:[[:space:]]*"ready"' &&
    printf '%s' "$body" | grep -qE '"registered"[[:space:]]*:[[:space:]]*true'; then
    printf '0\n' > "$FAIL_FILE"
    exit 0
fi

fails=$(( $(cat "$FAIL_FILE" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$fails" > "$FAIL_FILE"
last="$(cat "$LAST_FILE" 2>/dev/null || echo 0)"
now="$(date +%s)"
log "unhealthy (streak=$fails): $(printf '%s' "$body" | head -c 200)"

# Act after 3 consecutive unhealthy checks and at most once per 15 minutes.
if [ "$fails" -ge 3 ] && [ $(( now - last )) -ge 900 ]; then
    if kickstart; then
        log "kickstarted relay after $fails unhealthy checks"
        printf '%s\n' "$now" > "$LAST_FILE"
        printf '0\n' > "$FAIL_FILE"
    else
        log "kickstart failed"
    fi
fi
