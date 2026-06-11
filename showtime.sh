#!/bin/bash
# ONE COMMAND to (re)start everything for the show:
#   ./showtime.sh
# Quits any running ShowRunner, makes sure Tailscale is connected, relaunches the
# app, and prints the phone-remote URLs. Safe to run as many times as you like.
set -u
cd "$(dirname "$0")"

echo "==> Quitting any running ShowRunner…"
osascript -e 'tell application "ShowRunner" to quit' >/dev/null 2>&1
pkill -x ShowRunner 2>/dev/null
sleep 1

echo "==> Making sure Tailscale is connected…"
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
TSIP=""
if [[ -x "$TS" ]]; then
  open -ga Tailscale 2>/dev/null      # launches/connects it if it wasn't running
  for _ in $(seq 1 20); do
    TSIP="$("$TS" ip -4 2>/dev/null | head -1)"
    [[ -n "$TSIP" ]] && break
    sleep 1
  done
  if [[ -n "$TSIP" ]]; then
    # CRITICAL: stop Tailscale from hijacking the lights. With accept-routes on,
    # a peer (e.g. an openclaw box) advertising a default + multicast route makes
    # this Mac swallow 224.0.0/4 into the tunnel — and sACN to the lights is
    # 239.255.x.x multicast, so the lights go dark while Tailscale is up. Force
    # accept-routes off + no exit node so multicast/Wi-Fi leave via the real NICs.
    "$TS" set --accept-routes=false --exit-node= 2>/dev/null \
      && echo "    ✓ Tailscale route-hijack guard set (accept-routes off, no exit node)"
    echo "    ✓ Tailscale up: $TSIP"
  else
    echo "    ⚠ Tailscale installed but not connected (logged out?) — open the"
    echo "      Tailscale menu-bar icon and log in. Remote still works on local Wi-Fi."
  fi
else
  echo "    ⚠ Tailscale not installed — remote works on local Wi-Fi only."
fi

echo "==> Launching ShowRunner…"
if [[ ! -d "ShowRunner.app" ]]; then
  echo "    ShowRunner.app missing — building it first…"
  (cd ShowRunnerApp && ./build.sh) || { echo "BUILD FAILED"; exit 1; }
fi
open ./ShowRunner.app
sleep 2
if pgrep -x ShowRunner >/dev/null; then
  echo "    ✓ ShowRunner is running"
else
  echo "    ⛔ ShowRunner did not start — check the log:"
  echo "       ~/Library/Logs/ShowRunner/showrunner.log"
  exit 1
fi

echo ""
echo "📱 Open ONE of these in Safari on the iPhone:"
[[ -n "$TSIP" ]] && echo "    http://$TSIP:8088          ← Tailscale (works on any network — bookmark this)"
LAN="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)"
[[ -n "${LAN:-}" ]] && echo "    http://$LAN:8088      ← same Wi-Fi only (fallback)"
echo ""
echo "Keyboard on the Mac always works: Space = GO, Esc = STOP."
