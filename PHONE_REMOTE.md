# Phone Remote — control ShowRunner from your iPhone

ShowRunner now runs a tiny web server **inside the app** (port **8088**). Open the URL it
shows in the operator window in Safari on your phone and you get a remote with the full
running order, **PREV / NEXT / GO / STOP**, the on-deck piece, now-playing, and elapsed time.

It is **purely additive**: audio playback and the projector never touch the network. If
Wi-Fi dies mid-piece, nothing happens to the show — you only lose the phone buttons until
it reconnects (the page shows a red "RECONNECTING…" banner and recovers by itself). The
Mac's keyboard remains a full backup at all times.

## Using it

1. Launch ShowRunner. The operator window header shows a teal line like:
   `📱 Phone remote:  http://192.168.1.23:8088 · http://100.x.y.z:8088 (Tailscale)`
2. On your iPhone, open that URL in Safari.
3. Tap a piece to select it, or use **▲ PREV / ▼ NEXT**. **GO** fires the selected piece
   (title card + audio if it has any) — exactly like pressing Space on the Mac.
   **STOP / PANIC** needs **two taps** (tap once to arm, tap again within 2.5 s) so a
   pocket-tap can't kill a piece.
4. Tip: add it to the Home Screen (Share → Add to Home Screen) for a full-screen,
   app-like remote. The page asks iOS to keep the screen awake while it's open.

The line refreshes every few seconds, so when the Mac hops networks (venue Wi-Fi →
hotspot) the current URLs are always shown.

## Network plan for the concert

**Primary — Tailscale over venue Wi-Fi.** Both the Mac and the phone on the venue Wi-Fi,
both logged into Tailscale. Use the Tailscale URL (the `100.x.y.z` one, or
`http://<mac-name>:8088` with MagicDNS). Why Tailscale instead of the plain LAN IP: venue
networks often have *client isolation* (phone can't reach the Mac directly); Tailscale
detects that and relays via the internet automatically. Same URL works either way.

**Backup — iPhone Personal Hotspot.** If venue Wi-Fi dies: turn on Personal Hotspot on
the phone, join the Mac to it (Wi-Fi menu → your iPhone), wait a few seconds. The
Tailscale URL keeps working over the hotspot; the Mac's hotspot address (usually
`172.20.10.2`) is also shown in the operator window as a fallback.

**Last resort — the Mac's keyboard.** Space = GO, Esc = STOP. Always works.

### Before show day

- In the Tailscale admin console, **disable key expiry** for both the Mac and the phone
  (otherwise it may demand a re-login at the worst moment).
- At soundcheck: clear any venue Wi-Fi captive portal on both devices, confirm the remote
  works, then rehearse the hotspot switch once end-to-end.
- Note the remote has no password — anyone on the same network who knows the URL could
  drive it. On shared venue Wi-Fi prefer the Tailscale URL (encrypted, only your devices);
  client isolation usually blocks strangers from the plain IP anyway.

## Config

`showrunner.json` accepts an optional `"remotePort": 8088` (top level) to change the port.

## Endpoints (for debugging)

- `GET /` — the phone page
- `GET /state` — JSON snapshot (pieces, selected, playing, on-deck, now-playing, elapsed)
- `POST /next` `/prev` `/go` `/stop` — same actions as the keyboard
- `POST /select?i=N` — select piece at index N (0-based)

`curl -s localhost:8088/state | python3 -m json.tool` is a quick health check.
