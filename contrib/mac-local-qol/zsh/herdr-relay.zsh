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
    bootstrap|boot)
      # 新机器一键收敛：App 源 + 网关设置 + 装 QoL 工具 + pmset + 提醒 + 出码
      local origin="${HERDR_QOL_APP_ORIGIN:-}" gw_list gw_sel bundle cur
      if [ ! -f "$cfg/relay.env" ]; then
        print -ru2 -- "✗ 未找到 $cfg/relay.env：先安装并配置插件（herdr plugin install 0cv/herdr-mobile-relay）"
        return 1
      fi
      if [ -z "$origin" ]; then origin="$(head -1 "$cfg/phone-app-origin-configured" 2>/dev/null)"; fi
      if [ -z "$origin" ]; then
        if [ -t 0 ]; then
          print -n "输入手机 App 的 HTTPS 源（如 https://your-app.pages.dev）: "; read -r origin
        else
          print -ru2 -- "✗ 未提供 App 源：export HERDR_QOL_APP_ORIGIN=https://… 后重跑"
          return 1
        fi
      fi
      origin="${origin%/}"
      print -r -- "▸ App 源: $origin"
      if curl -s --max-time 10 "$origin/manifest.webmanifest" 2>/dev/null | grep -q '"name"[[:space:]]*:[[:space:]]*"Herdr Mobile Relay"'; then
        print -r -- "  ✓ 已确认返回 Herdr Mobile Relay manifest"
      else
        print -r -- "  ⚠️ 未返回预期 manifest，请确认该源确实是 Herdr App"
      fi
      gw_list="${HERDR_QOL_GATEWAY_URL:-wss://gw1.herdr-mobile.dev,wss://gw2.herdr-mobile.dev}"
      gw_sel="${HERDR_QOL_GATEWAY_SELECTION:-ordered}"
      print -r -- "▸ 网关: $gw_list  ($gw_sel)"
      HERDR_RELAY_ENV="$cfg/relay.env" ORIGIN="$origin" GW_LIST="$gw_list" GW_SEL="$gw_sel" bash -c '
        set -euo pipefail
        . "$HOME/.local/share/herdr-mobile-relay/current/relay/common.sh"
        set_gateway_url "$HERDR_RELAY_ENV" "$GW_LIST"
        set_gateway_selection "$HERDR_RELAY_ENV" "$GW_SEL"
        record_phone_app_origin "$ORIGIN" "$HERDR_RELAY_ENV"
      ' && print -r -- "  ✓ 已写入 relay.env 与 phone-app-origin-configured"
      for cand in "${HERDR_QOL_BUNDLE:-}" "$HOME/clone/herdr-mobile-relay/contrib/mac-local-qol" "$PWD/contrib/mac-local-qol"; do
        [ -n "$cand" ] && [ -x "$cand/install.sh" ] && bundle="$cand" && break
      done
      if [ -n "${bundle:-}" ]; then
        print -r -- "▸ 安装 QoL 工具（launchd / watchdog / zsh）…"; bash "$bundle/install.sh"
      else
        print -r -- "⚠️ 未找到 install.sh；设 HERDR_QOL_BUNDLE 指向 contrib/mac-local-qol 后重跑"
      fi
      cur="$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{f=1} f&&$1=="sleep"{print $2; exit}')"
      if [ "$cur" = "0" ]; then
        print -r -- "▸ pmset: AC sleep 已是 0，跳过"
      elif [ -t 0 ]; then
        print -r -- "▸ pmset: 当前 AC sleep=$cur；设为 0 可让锁屏后仍在线（会弹管理员授权）"
        if read -q "REPLY?现在设置? [y/N] "; then
          print
          osascript -e 'do shell script "/usr/bin/pmset -c sleep 0" with administrator privileges' && print -r -- "  ✓ 已设置"
        else
          print -r -- "  跳过（以后可自行: sudo pmset -c sleep 0）"
        fi
      else
        print -r -- "▸ pmset: 非交互，跳过（手动: sudo pmset -c sleep 0）"
      fi
      print -r -- "▸ 还需手动：Shadowrocket 加规则  DOMAIN-SUFFIX,herdr-mobile.dev,DIRECT"
      print -r -- "▸ 配对二维码："
      ( cd "$release" 2>/dev/null || cd "$cfg" || return
        HERDR_RELAY_ENV="$cfg/relay.env" HERDR_PLUGIN_CONFIG_DIR="$cfg" bash "$release/relay/setup-link.sh" )
      ;;
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
      local gws gw hg
      gws="$(awk -F= '/^HERDR_GATEWAY_URL=/{print $2}' "$cfg/relay.env" 2>/dev/null | tr -d "'" | tr -d '"' | tr ',' ' ')"
      gws="${gws:-wss://gw1.herdr-mobile.dev wss://gw2.herdr-mobile.dev}"
      for gw in ${=gws}; do
        hg="${gw/wss:/https:}"; hg="${hg/ws:/http:}"
        printf '  %s: ' "$gw"
        curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' --max-time 6 "$hg/healthz" 2>/dev/null || print -r -- "FAIL"
      done
      print -r -- "── App 源 ──"
      local origin
      origin="$(head -1 "$cfg/phone-app-origin-configured" 2>/dev/null)"
      if [ -n "$origin" ]; then
        printf '  %s -> ' "$origin"
        curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$origin/manifest.webmanifest" 2>/dev/null || print -r -- "FAIL"
      else
        print -r -- "  (未设置 phone-app-origin-configured)"
      fi
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
  bootstrap|boot  新机器一键收敛（App源+网关+装工具+pmset+提醒+出码）
EOF
      ;;
  esac
}
