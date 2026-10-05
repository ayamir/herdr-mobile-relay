# mac local QoL bundle (personal)

Machine-specific convenience tooling for running **Herdr Mobile Relay over the
Community WebRTC gateway** on one macOS laptop. This lives in a personal fork;
it is *not* an upstream feature and is not proposed upstream.

Everything here assumes the plugin is already installed and configured
(`herdr plugin install 0cv/herdr-mobile-relay`, then the setup menu / gateway
choice), which creates `~/.config/herdr/plugins/config/herdr-mobile-relay.events`.

## What it installs

| Path | Purpose |
| --- | --- |
| `~/Library/LaunchAgents/com.herdr-mobile-relay.service.plist` | launchd **user service** running the relay in gateway (WebRTC) mode; `RunAtLoad` + `KeepAlive` |
| `~/Library/LaunchAgents/com.herdr-mobile-relay.watchdog.plist` | launchd **watchdog**: after each boot it forces one clean gateway re-registration, and kickstarts the relay when it is unhealthy |
| `<plugin config>/relay-watchdog.sh` | the watchdog logic |
| `<plugin config>/gateway-noop-tunnel.sh` + `.conf` | a no-op stand-in for `cloudflared` (see below) |
| `~/.config/zsh/herdr-relay.zsh` | the `hrelay` zsh function (sourced from `~/.zshrc`) |
| `~/.config/zsh-abbr/user-abbreviations` | `hr`/`hrs`/`hrd`/`hrr`/`hrl`/`hrw`/`hrq` abbreviations |

## Why the no-op tunnel shim

Herdr's stock service wrapper (`relay/herdr-mobile-relay-service.sh`) requires a
`cloudflared` binary and a readable tunnel config; it has no gateway branch.
The plugin's update hook (`relay/plugin-build.sh`) rewrites the service plist's
`ProgramArguments` to that wrapper but preserves other `EnvironmentVariables`,
so pointing `CLOUDFLARED_BIN` at the shim lets the stock wrapper supervise the
relay in gateway mode and keeps working across plugin updates.

If upstream ever adds gateway-mode service support, delete the shim and the two
`CLOUDFLARED_*` env vars from the service plist.

## Install

```bash
./install.sh          # idempotent; safe to re-run
```

Then open a new shell and run `hrelay doctor`.

## Usage

```
hrelay                        # = status
hrelay status|st              launchd + watchdog + healthz
hrelay doctor|doc             full diagnostic (system/launchd/relay/gateway/app-origin/credentials/logs)
hrelay start|stop|restart|rs
hrelay health                 raw healthz JSON
hrelay logs|l                 tail relay log
hrelay wlog                   tail watchdog log
hrelay qr|link                re-arm an invitation and print the pairing QR/link
hrelay open                   open the plugin Setup pane
hrelay wd-on|wd-off|wd-run    manage the watchdog
```

## Manual settings applied outside this bundle

These are not files; re-apply them by hand (or script them) on a rebuild.

- **Never idle-sleep on AC** (keeps the relay reachable while the screen is locked):
  ```bash
  sudo pmset -c sleep 0
  ```
  Revert with `sudo pmset -c sleep 1`. Lid-close sleep still needs
  `sudo pmset -a disablesleep 1` (or the Mole app's "Work Only" keep-awake mode).
- **Shadowrocket rule** (the local TUN proxy otherwise makes the gateway health
  probes flap): add `DOMAIN-SUFFIX,herdr-mobile.dev,DIRECT` to the active config.
- **Gateway selection** in `<plugin config>/relay.env`: keep both gateways but
  prefer the stable one:
  ```
  HERDR_GATEWAY_URL='wss://gw1.herdr-mobile.dev,wss://gw2.herdr-mobile.dev'
  HERDR_GATEWAY_SELECTION='ordered'
  ```
- **Phone app origin**: `<plugin config>/phone-app-origin-configured` holds the
  HTTPS origin that serves the PWA (e.g. a Cloudflare Pages `*.pages.dev`).
  The gateway carries relay traffic only and never hosts the app.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.herdr-mobile-relay.watchdog
launchctl bootout gui/$(id -u)/com.herdr-mobile-relay.service
rm -f ~/Library/LaunchAgents/com.herdr-mobile-relay.watchdog.plist \
      ~/Library/LaunchAgents/com.herdr-mobile-relay.service.plist \
      ~/.config/zsh/herdr-relay.zsh
```
