#!/bin/bash
# EMERGENCY KILL for ShowRunner — the last-resort way to quit the app when the
# screen is locked behind a full-screen title card and the keyboard won't reach it.
#
# Run this:
#   • In Terminal ON THE MAC (e.g. switch apps with Cmd-Tab to Terminal, or open it
#     from Spotlight), OR
#   • Over SSH FROM THE PHONE if the Mac is unreachable any other way — see the
#     "Kill it from the phone over SSH" section in PHONE_REMOTE.md.
#
# It tries the polite quit first, then a force-kill. Safe to run repeatedly.
set -u

echo "==> Asking ShowRunner to quit…"
osascript -e 'tell application "ShowRunner" to quit' >/dev/null 2>&1
sleep 1

if pgrep -x ShowRunner >/dev/null; then
  echo "==> Still running — force-killing…"
  pkill -x ShowRunner 2>/dev/null
  sleep 1
  pkill -9 -x ShowRunner 2>/dev/null   # last resort
fi

sleep 1
if pgrep -x ShowRunner >/dev/null; then
  echo "⛔ ShowRunner is STILL running — try: sudo pkill -9 -x ShowRunner"
  exit 1
else
  echo "✓ ShowRunner is dead. The projector display is released."
fi
