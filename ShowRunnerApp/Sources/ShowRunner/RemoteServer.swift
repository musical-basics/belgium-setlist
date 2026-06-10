import Foundation
import Network

/// Actions the phone remote can trigger. Mirrors the keyboard exactly.
enum RemoteAction: String {
    case next, prev, go, stop, toggle
}

/// Snapshot sent to the phone as JSON. Text fields are read straight off the operator
/// window's labels so the phone always mirrors exactly what the Mac shows.
struct RemotePieceState: Codable {
    let order: String
    let title: String
    let subtitle: String
    let hasAudio: Bool
    let ready: Bool
    let speaking: Bool
    /// Speech text — present only for speaking cues, shown only on the phone.
    let notes: String?
}

struct RemoteState: Codable {
    let pieces: [RemotePieceState]
    let selected: Int
    let playing: Int?
    /// "stopped" | "playing" | "paused" — drives the phone's GO/PAUSE/RESUME button.
    let playState: String
    let onDeck: String
    let nowPlaying: String
    let elapsed: String
    let remaining: String
    let progress: Double
}

/// A local IPv4 address the phone could reach us on.
struct LocalAddress {
    let interface: String
    let address: String
    /// Tailscale hands out CGNAT addresses (100.64.0.0/10).
    var isTailscale: Bool {
        let o = address.split(separator: ".").compactMap { Int($0) }
        return o.count == 4 && o[0] == 100 && (64...127).contains(o[1])
    }
}

/// Tiny embedded HTTP server (Network.framework, zero dependencies) serving the phone
/// remote page plus a few control endpoints. Purely ADDITIVE: it never initiates network
/// traffic, and if Wi-Fi or this server dies the show is unaffected — audio keeps playing
/// from preloaded buffers and the keyboard still runs everything.
final class RemoteServer {
    let port: UInt16

    /// All three are invoked on the MAIN thread.
    var onAction: ((RemoteAction) -> Void)?
    var onSelect: ((Int) -> Void)?
    var stateProvider: (() -> RemoteState)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "showrunner.remote")

    init(port: UInt16) { self.port = port }

    /// Returns nil on success, or a short error string (e.g. port already in use).
    func start() -> String? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return "invalid port \(port)" }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l: NWListener
        do {
            l = try NWListener(using: params, on: nwPort)
        } catch {
            return "\(error)"
        }
        let p = port
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: Logger.shared.info("Phone remote listening on port \(p)")
            case .failed(let e): Logger.shared.error("Phone remote listener failed: \(e)")
            default: break
            }
        }
        l.start(queue: queue)
        listener = l
        return nil
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Local addresses (for the "type this into Safari" label)

    static func localIPv4Addresses() -> [LocalAddress] {
        var found: [LocalAddress] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            found.append(LocalAddress(interface: String(cString: ptr.pointee.ifa_name),
                                      address: String(cString: host)))
        }
        // Real LAN interfaces (en*) first, then Tailscale/utun, then the rest.
        func rank(_ a: LocalAddress) -> Int {
            if a.interface.hasPrefix("en") { return 0 }
            if a.isTailscale { return 1 }
            return 2
        }
        return found.sorted { rank($0) < rank($1) }
    }

    // MARK: Connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn, buffer: Data())
    }

    /// Accumulate until the end of the request headers; we never need a body
    /// (every endpoint is path/query only), so route as soon as headers are complete.
    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if error != nil || buf.count > 16384 { conn.cancel(); return }
            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.route(conn, header: buf.subdata(in: buf.startIndex..<headerEnd.lowerBound))
            } else if isComplete {
                conn.cancel()
            } else {
                self.receiveRequest(conn, buffer: buf)
            }
        }
    }

    private func route(_ conn: NWConnection, header: Data) {
        guard let requestLine = String(data: header, encoding: .utf8)?
            .components(separatedBy: "\r\n").first else { conn.cancel(); return }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let target = String(parts[1])
        let pieces = target.split(separator: "?", maxSplits: 1)
        let path = pieces.first.map(String.init) ?? "/"
        let query = pieces.count > 1 ? String(pieces[1]) : ""

        switch path {
        case "/", "/index.html":
            send(conn, status: "200 OK", contentType: "text/html; charset=utf-8",
                 body: Data(Self.pageHTML.utf8))
        case "/state":
            respondWithState(conn)
        case "/next", "/prev", "/go", "/stop", "/toggle":
            let action = RemoteAction(rawValue: String(path.dropFirst()))!
            DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
            // The state hop below is queued on main AFTER the action, so the
            // response already reflects what the tap did.
            respondWithState(conn)
        case "/select":
            let idx = query.split(separator: "&").compactMap { kv -> Int? in
                let p = kv.split(separator: "=")
                return p.count == 2 && p[0] == "i" ? Int(p[1]) : nil
            }.first
            if let i = idx {
                DispatchQueue.main.async { [weak self] in self?.onSelect?(i) }
            }
            respondWithState(conn)
        default:
            send(conn, status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8))
        }
    }

    private func respondWithState(_ conn: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { conn.cancel(); return }
            let body: Data
            if let provider = self.stateProvider, let data = try? JSONEncoder().encode(provider()) {
                body = data
            } else {
                body = Data("{}".utf8)
            }
            self.send(conn, status: "200 OK", contentType: "application/json", body: body)
        }
    }

    private func send(_ conn: NWConnection, status: String, contentType: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: The phone page

    static let pageHTML = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>ShowRunner</title>
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; margin: 0; -webkit-tap-highlight-color: transparent;
    touch-action: manipulation; -webkit-user-select: none; user-select: none; }
html, body { height: 100%; }
body { background:#101014; color:#f2f2f5; font-family:-apple-system,system-ui,sans-serif;
       display:flex; flex-direction:column; height:100dvh; overflow:hidden; }
#offline { display:none; background:#c62828; color:#fff; text-align:center;
           font-weight:700; padding:6px; font-size:14px; }
header { padding:calc(env(safe-area-inset-top) + 8px) 16px 10px; background:#17171c;
         border-bottom:1px solid #26262e; }
#hdrRow { display:flex; align-items:center; gap:8px; }
#hdrRow h1 { font-size:14px; font-weight:800; letter-spacing:1px; color:#9a9aa5; flex:1; }
.dot { width:10px; height:10px; border-radius:5px; background:#555; }
.dot.ok { background:#2ecc40; } .dot.bad { background:#ff4136; }
#ondeck { font-size:20px; font-weight:700; margin-top:6px; }
#ondeck small { color:#7f9cf5; font-size:11px; font-weight:800; letter-spacing:1px; display:block; }
#nowplaying { font-size:14px; color:#bdbdc7; margin-top:6px;
              overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
#timerow { display:flex; justify-content:space-between; align-items:baseline; margin-top:4px; }
#bigtime { font-size:34px; font-weight:700; font-variant-numeric:tabular-nums; color:#f2f2f5; }
#bigtime.idle { color:#55555f; }
#remaining { font-size:17px; font-weight:600; font-variant-numeric:tabular-nums; color:#9a9aa5; }
#bar { height:3px; background:#26262e; margin-top:8px; border-radius:2px; overflow:hidden; }
#fill { height:100%; width:0%; background:#2ecc40; }
#list { flex:1; overflow-y:auto; -webkit-overflow-scrolling:touch; padding:8px 10px; }
.row { display:flex; align-items:center; gap:12px; padding:12px; border-radius:10px; margin-bottom:4px; }
.row .num { font-size:17px; font-weight:800; color:#8a8a95; width:30px; text-align:center;
            font-variant-numeric:tabular-nums; }
.row .t { flex:1; min-width:0; }
.row .ti { font-size:17px; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.row .su { font-size:12px; color:#8a8a95; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.row .badge { font-size:10px; font-weight:800; background:#2b5ccc; color:#fff;
              border-radius:4px; padding:2px 6px; }
.row .speak { font-size:10px; font-weight:800; background:#7c3aed; color:#fff;
              border-radius:4px; padding:2px 6px; }
.row .warn { font-size:10px; font-weight:800; background:#c62828; color:#fff;
             border-radius:4px; padding:2px 6px; }
.row.sel { background:rgba(80,120,255,.30); }
.row.play { background:rgba(46,204,64,.26); }
.notes { display:none; margin:0 6px 10px; padding:14px 16px; background:#1b1626;
         border:1px solid #4c3a78; border-radius:12px; font-size:18px; line-height:1.5;
         color:#efeaf7; white-space:pre-wrap; -webkit-user-select:none; }
.notes.show { display:block; }
footer { padding:10px 12px calc(env(safe-area-inset-bottom) + 10px); background:#17171c;
         border-top:1px solid #26262e; display:grid; grid-template-columns:1fr 1fr; gap:10px; }
button { border:none; border-radius:12px; font-weight:800; color:#fff; font-family:inherit; }
#prev, #next { background:#2c2c34; font-size:18px; padding:16px 0; }
#go { grid-column:1/-1; background:#1f9d40; font-size:24px; padding:20px 0; }
#go.pause { background:#c87f0a; }
#go.resume { background:#2563c9; }
#stop { grid-column:1/-1; background:#8c1d1d; font-size:15px; padding:12px 0; }
#stop.armed { background:#e53935; font-size:18px; }
button:active { filter:brightness(1.25); }
</style>
</head>
<body>
<div id="offline">RECONNECTING&hellip;</div>
<header>
  <div id="hdrRow"><h1>SHOWRUNNER REMOTE</h1><div class="dot" id="dot"></div></div>
  <div id="ondeck"><small>ON DECK</small><span id="ondecktext">&mdash;</span></div>
  <div id="nowplaying">&mdash;</div>
  <div id="timerow"><div id="bigtime" class="idle">&ndash;&ndash;:&ndash;&ndash;</div><div id="remaining"></div></div>
  <div id="bar"><div id="fill"></div></div>
</header>
<div id="list"></div>
<footer>
  <button id="prev">&#9650; PREV</button>
  <button id="next">&#9660; NEXT</button>
  <button id="go">GO</button>
  <button id="stop">STOP / PANIC</button>
</footer>
<script>
var rows = [], noteEls = [], lastSelected = -1, stopTimer = null;
function $(id){ return document.getElementById(id); }
function handle(p){ return p.then(function(r){ if(!r.ok) throw 0; return r.json(); })
                     .then(function(s){ render(s); online(true); })
                     .catch(function(){ online(false); }); }
function send(path){ handle(fetch(path, {method:'POST', cache:'no-store'})); }
function poll(){ handle(fetch('/state', {cache:'no-store'})); }
function online(ok){
  $('dot').className = 'dot ' + (ok ? 'ok' : 'bad');
  $('offline').style.display = ok ? 'none' : 'block';
}
function buildList(pieces){
  var list = $('list');
  list.innerHTML = '';
  rows = []; noteEls = []; lastSelected = -1;
  pieces.forEach(function(p, i){
    var row = document.createElement('div'); row.className = 'row';
    var num = document.createElement('div'); num.className = 'num'; num.textContent = p.order;
    var t = document.createElement('div'); t.className = 't';
    var ti = document.createElement('div'); ti.className = 'ti'; ti.textContent = p.title;
    var su = document.createElement('div'); su.className = 'su'; su.textContent = p.subtitle;
    t.appendChild(ti); t.appendChild(su);
    row.appendChild(num); row.appendChild(t);
    if (p.speaking) { var sp = document.createElement('div'); sp.className = 'speak'; sp.textContent = 'SPEAKING'; row.appendChild(sp); }
    else if (!p.ready) { var w = document.createElement('div'); w.className = 'warn'; w.textContent = 'MISSING'; row.appendChild(w); }
    else if (p.hasAudio) { var b = document.createElement('div'); b.className = 'badge'; b.textContent = 'AUDIO'; row.appendChild(b); }
    row.onclick = function(){ send('/select?i=' + i); };
    list.appendChild(row);
    rows.push(row);
    var n = null;
    if (p.speaking && p.notes) {
      n = document.createElement('div'); n.className = 'notes'; n.textContent = p.notes;
      list.appendChild(n);
    }
    noteEls.push(n);
  });
}
function render(s){
  if (rows.length !== s.pieces.length) buildList(s.pieces);
  rows.forEach(function(row, i){
    row.className = 'row' + (i === s.playing ? ' play' : (i === s.selected ? ' sel' : ''));
    if (noteEls[i]) noteEls[i].className = 'notes' + (i === s.selected ? ' show' : '');
  });
  if (s.selected !== lastSelected) {
    lastSelected = s.selected;
    if (rows[s.selected]) rows[s.selected].scrollIntoView({block:'start', behavior:'smooth'});
  }
  $('ondecktext').textContent = s.onDeck;
  $('nowplaying').textContent = s.nowPlaying;
  var bt = $('bigtime');
  bt.textContent = s.elapsed;
  bt.className = (s.playState === 'stopped') ? 'idle' : '';
  $('remaining').textContent = s.remaining;
  $('fill').style.width = (s.progress * 100) + '%';
  var go = $('go');
  if (s.playState === 'playing') { go.className = 'pause'; go.textContent = '⏸ PAUSE'; }
  else if (s.playState === 'paused') { go.className = 'resume'; go.textContent = '▶ RESUME'; }
  else { go.className = ''; go.textContent = 'GO'; }
}
$('prev').onclick = function(){ send('/prev'); };
$('next').onclick = function(){ send('/next'); };
$('go').onclick = function(){ send('/toggle'); };
$('stop').onclick = function(){
  var b = $('stop');
  if (b.classList.contains('armed')) {
    clearTimeout(stopTimer);
    b.classList.remove('armed'); b.textContent = 'STOP / PANIC';
    send('/stop');
  } else {
    b.classList.add('armed'); b.textContent = 'TAP AGAIN TO STOP';
    stopTimer = setTimeout(function(){
      b.classList.remove('armed'); b.textContent = 'STOP / PANIC';
    }, 2500);
  }
};
setInterval(poll, 1000);
poll();
function wakeLock(){ if (navigator.wakeLock) { navigator.wakeLock.request('screen').catch(function(){}); } }
document.addEventListener('visibilitychange', function(){ if (!document.hidden) { wakeLock(); poll(); } });
wakeLock();
</script>
</body>
</html>
"""#
}
