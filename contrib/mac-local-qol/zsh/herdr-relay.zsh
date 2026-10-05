# Herdr Mobile Relay 管理：服务 / watchdog / 健康 / 配对二维码
hrelay() {
  emulate -L zsh
  local svc=com.herdr-mobile-relay.service
  local wd=com.herdr-mobile-relay.watchdog
  local gui="gui/$(id -u)"
  local cfg="$HOME/.config/herdr/plugins/config/herdr-mobile-relay.events"
  local logdir="$HOME/Library/Logs/herdr-mobile-relay"
  local release="$HOME/.local/share/herdr-mobile-relay/current"
  local port="${HERDR_RELAY_PORT:-8375}"

  case "${1:-status}" in
    status|st)
      print -r -- "── launchd ──"
      launchctl print "$gui/$svc" 2>/dev/null | grep -E '^[[:space:]]*(state|pid|last exit code) ' \
        || print -r -- "service: 未加载"
      launchctl print "$gui/$wd" >/dev/null 2>&1 && print -r -- "watchdog: loaded" || print -r -- "watchdog: not loaded"
      print -r -- "── health ──"
      curl -s --max-time 5 "http://127.0.0.1:$port/healthz" \
        | grep -oE '"(readiness|status)":"[^"]*"|"(registered|clients|webrtc_active)":(true|false|[0-9]+)|"url":"[^"]*"|"gateway_selection":"[^"]*"' \
        || print -r -- "relay: 不可达"
      ;;
    start)  launchctl bootstrap "$gui" "$HOME/Library/LaunchAgents/$svc.plist" && print -r -- "service started" ;;
    stop)   launchctl bootout "$gui/$svc" && print -r -- "service stopped" ;;
    restart|rs) launchctl kickstart -k "$gui/$svc" && print -r -- "service restarted（正在重注册网关…）" ;;
    health) curl -s "http://127.0.0.1:$port/healthz" | python3 -m json.tool 2>/dev/null || print -r -- "relay: 不可达" ;;
    logs|l) tail -n 50 -f "$logdir/service.err" ;;
    wlog)   tail -n 50 -f "$logdir/watchdog.log" ;;
    qr|link)
      ( cd "$release" 2>/dev/null || cd "$cfg" || return
        HERDR_RELAY_ENV="$cfg/relay.env" HERDR_PLUGIN_CONFIG_DIR="$cfg" \
          bash "$release/relay/setup-link.sh" ) ;;
    open)   herdr plugin pane open --plugin herdr-mobile-relay.events --entrypoint setup --placement zoomed --focus ;;
    wd-on)  launchctl bootstrap "$gui" "$HOME/Library/LaunchAgents/$wd.plist" && print -r -- "watchdog on" ;;
    wd-off) launchctl bootout "$gui/$wd" && print -r -- "watchdog off" ;;
    wd-run) bash "$cfg/relay-watchdog.sh"; print -r -- "watchdog exit=$?" ;;
    doctor|doc)
      local now boot_sec h
      now="$(date '+%Y-%m-%d %H:%M:%S')"
      print -r -- "══ Herdr Mobile Relay doctor ══   $now"
      boot_sec="$(sysctl -n kern.boottime 2>/dev/null | grep -oE 'sec = [0-9]+' | head -1 | tr -dc '0-9')"
      print -r -- "── 系统 ──"
      [ -n "$boot_sec" ] && printf '  开机: %s（已运行 %s 分钟）\n' "$(date -r "$boot_sec" '+%m-%d %H:%M' 2>/dev/null)" "$(( ($(date +%s) - boot_sec) / 60 ))"
      pmset -g custom 2>/dev/null | awk '
        /^AC Power:/ {sec="AC"} /^Battery Power:/ {sec="Battery"}
        $1=="sleep" {printf "  %s sleep=%s\n", sec, $2}
        $1=="displaysleep" {printf "  %s displaysleep=%s\n", sec, $2}'
      printf '  SleepDisabled=%s  (1=合盖也不睡)\n' "$(pmset -g 2>/dev/null | awk '/SleepDisabled/{print $2}')"
      print -r -- "── launchd ──"
      if launchctl print "$gui/$svc" >/dev/null 2>&1; then
        launchctl print "$gui/$svc" 2>/dev/null | awk '
          /^[[:space:]]*state = / && !s {print "  state:", $3; s=1}
          /^[[:space:]]*pid = / && !p {print "  pid:", $3; p=1}
          /last exit code = / && !l {sub(/^[[:space:]]*/, ""); print " ", $0; l=1}'
      else
        print -r -- "  svc: 未加载 ❌"
      fi
      launchctl print "$gui/$wd" >/dev/null 2>&1 && print -r -- "  watchdog: loaded ✅" || print -r -- "  watchdog: 未加载 ⚠️"
      print -r -- "── relay (healthz) ──"
      h="$(curl -s --max-time 6 "http://127.0.0.1:$port/healthz" 2>/dev/null)"
      if [ -z "$h" ]; then
        print -r -- "  ❌ 本地 :$port 不可达（服务未起或端口被占）"
      else
        printf '%s' "$h" | python3 -c '
import sys, json
d = json.load(sys.stdin); g = d.get("gateway") or {}; inv = d.get("inventory") or {}
print("  readiness:", d.get("readiness"), "| status:", d.get("status"))
print("  version:", d.get("version"), str(d.get("revision",""))[:12], "| instance:", str(d.get("instance",""))[:12])
print("  inventory:", inv.get("state"), "stale=", str(inv.get("stale")).lower(), "err=", repr(inv.get("error_code","")))
print("  gateway:", g.get("registered"), g.get("url"), "| selection:", g.get("gateway_selection"))
print("  clients:", g.get("clients"), "| webrtc_active:", g.get("webrtc_active"), "| webrtc_port:", g.get("webrtc_port"))
if g.get("last_error"):  print("  last_error:", g.get("last_error"))
if g.get("last_notice"): print("  last_notice:", g.get("last_notice"))
r = g.get("reachability") or {}
if r: print("  reachability:", r.get("reachable"), "ext=", r.get("external_ip"), "detail=", r.get("detail"))
s = g.get("stun") or {}
if s: print("  stun mapped:", s.get("mapped"))
'
      fi
      print -r -- "── 网关探测 ──"
      for gw in gw1 gw2; do
        printf '  %s: ' "$gw"
        curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' --max-time 6 "https://$gw.herdr-mobile.dev/healthz" 2>/dev/null || print -r -- "FAIL"
      done
      print -r -- "── App 源 ──"
      printf '  manifest: '
      curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://herdr-ayamir.pages.dev/manifest.webmanifest 2>/dev/null || print -r -- "FAIL"
      print -r -- "── 配对凭据 ──"
      if [ -r "$cfg/device-auth/devices.json" ]; then
        python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); cs = d.get("credentials") or []
print("  设备数:", len(cs))
for c in cs: print("   -", c.get("name"), c.get("role"), "last_seen:", c.get("last_seen_at"))
' "$cfg/device-auth/devices.json" 2>/dev/null || print -r -- "  (无法解析)"
      else
        print -r -- "  (无凭据文件)"
      fi
      print -r -- "── Herdr ──"
      printf '  herdr: %s\n' "$(herdr --version 2>/dev/null | head -1)"
      print -r -- "── 最近 relay 告警 ──"
      grep -aE 'level=(WARN|ERROR)' "$logdir/service.err" 2>/dev/null | tail -4 | sed 's/^/  /' || print -r -- "  (无)"
      print -r -- "── watchdog 日志尾部 ──"
      if [ -s "$logdir/watchdog.log" ]; then tail -3 "$logdir/watchdog.log" | sed 's/^/  /'; else print -r -- "  (空)"; fi
      ;;
    *)
      cat <<'EOF'
hrelay <命令>
  status|st    服务 + watchdog + 健康（默认）
  start        启动 relay 服务
  stop         停止 relay 服务
  restart|rs   干净重启（重新注册网关）
  health       healthz 原始 JSON
  logs|l       跟随 relay 日志
  wlog         跟随 watchdog 日志
  qr|link      重新打印配对二维码 / 链接
  open         打开插件 Setup 面板
  wd-on/off    启用 / 停用 watchdog
  wd-run       立刻跑一次 watchdog
  doctor|doc   一次性体检（系统/服务/relay/网关/App源/凭据/日志）
EOF
      ;;
  esac
}
