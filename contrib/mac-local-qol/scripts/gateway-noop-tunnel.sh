#!/bin/sh
# No-op stand-in for cloudflared.
#
# This relay runs in gateway (WebRTC) mode: relay.env carries HERDR_GATEWAY_URL,
# so no Cloudflare tunnel exists or is needed. The stock service wrapper
# (relay/herdr-mobile-relay-service.sh) still requires a cloudflared binary and a
# readable tunnel config because it has no gateway branch. Pointing
# CLOUDFLARED_BIN here satisfies that check and lets the wrapper supervise the
# relay exactly as it supervises a real tunnel process. This script ignores argv
# and idles; it never touches the network.
while :; do sleep 3600; done
