import AppKit

/// Runtime model for one piece: resolved file URLs, preloaded image, readiness, premixed audio.
final class PieceModel {
    let piece: Piece
    let titleCardURL: URL?
    let backingURL: URL?
    let clickURL: URL?
    var image: NSImage?
    var imageReady = false
    var audioReady = false
    var loadError: String?
    var premix: PremixedAudio?

    init(piece: Piece, root: URL) {
        self.piece = piece
        if let folder = piece.folder {
            let folderURL = root.appendingPathComponent(folder, isDirectory: true)
            self.titleCardURL = piece.titleCard.map { folderURL.appendingPathComponent($0) }
            self.backingURL = piece.backing.map { PieceModel.audioURL(root: root, folder: folder, file: $0) }
            self.clickURL = piece.click.map { PieceModel.audioURL(root: root, folder: folder, file: $0) }
        } else {
            // Speaking cue — nothing to load.
            self.titleCardURL = nil
            self.backingURL = nil
            self.clickURL = nil
        }
    }

    /// Single-folder audio bundle (all the non-git WAVs) you can copy to another Mac.
    static let assetsSubdir = "ShowAudio"

    /// Resolve a backing/click WAV: prefer it in the piece folder, else fall back to the bundled
    /// `ShowAudio/<folder>/<file>`. Returns the in-place path if neither exists (clear error msg).
    static func audioURL(root: URL, folder: String, file: String) -> URL {
        let inPlace = root.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: inPlace.path) { return inPlace }
        let bundled = root.appendingPathComponent(assetsSubdir, isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true).appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return inPlace
    }
}

final class AppController: NSObject, OperatorWindowDelegate {
    private let configPath: String?
    private var config: ShowConfig!
    private var root: URL!
    private var configURL: URL!
    private var saveWorkItem: DispatchWorkItem?

    private let audioEngine = AudioEngine()
    private var audienceWindow: AudienceWindow!
    private var operatorController: OperatorWindowController!

    private var pieces: [PieceModel] = []
    private var availableDevices: [AudioDeviceInfo] = []
    private var selectedIndex = 0
    private var playingIndex: Int?
    /// Piece paused mid-playback by the phone's PAUSE button; RESUME continues it.
    private var pausedIndex: Int?
    private var previewLightingIndex: Int?

    private var keyMonitor: Any?
    private var elapsedTimer: Timer?

    private var remoteServer: RemoteServer?
    private var remoteInfoTick = 0

    /// Optional, fully-isolated lighting module (see LightingBridge). nil = lighting off/unavailable;
    /// the audio show is identical with or without it. Nothing here writes back into the audio path.
    private var lighting: LightingBridge?

    init(configPath: String?) {
        self.configPath = configPath
        super.init()
    }

    // MARK: Bootstrap

    func bootstrap() {
        do {
            let loaded = try ConfigLoader.load(explicit: configPath)
            config = loaded.config
            root = loaded.root
            configURL = loaded.url
            Logger.shared.info("Loaded config: \(loaded.root.path) (\(config.pieces.count) pieces)")
        } catch {
            presentFatalConfigError("\(error)")
            return
        }

        pieces = config.pieces.map { PieceModel(piece: $0, root: root) }
        guard !pieces.isEmpty else {
            presentFatalConfigError("showrunner.json contains no pieces.")
            return
        }
        preloadImages()

        // Windows
        operatorController = OperatorWindowController(headerTitle: "ShowRunner — Belgium · 11 June 2026")
        operatorController.delegate = self
        operatorController.window.makeKeyAndOrderFront(nil)

        audienceWindow = AudienceWindow(fadeSeconds: config.fadeSeconds)

        // If the interface is unplugged mid-show, stop and make it impossible to miss.
        audioEngine.onDeviceLost = { [weak self] in
            guard let self = self else { return }
            self.stop()
            self.operatorController.setNowPlaying("⛔ AUDIO DEVICE DISCONNECTED — reconnect & re-select it")
            self.refreshDevicePopup()
            self.updateStatus()
        }

        // Audio device
        let rate = config.engineSampleRate ?? 48000
        availableDevices = AudioEngine.outputDevices()
        let wantedDevice = ProcessInfo.processInfo.environment["SHOWRUNNER_DEVICE"] ?? config.audioDeviceName
        if let dev = AudioEngine.findDevice(named: wantedDevice) {
            audioEngine.configure(device: dev, requestedRate: rate)
        } else {
            Logger.shared.warn("Audio device '\(config.audioDeviceName)' not found — pick one from the menu.")
        }
        applyRoutingFromConfig()
        reloadAudio()

        // Populate UI
        let mb = config.masterBackingGainDb ?? 0
        let mc = config.masterClickGainDb ?? 0
        audioEngine.setMasterGains(backingDb: mb, clickDb: mc)
        operatorController.setMasterLevels(backingDb: mb, clickDb: mc)

        refreshDevicePopup()
        refreshDisplayPopup()
        refreshChannelPopups()
        refreshRows()
        selectIndex(0)
        applyAudienceDisplay(index: config.audienceDisplayIndex)
        updateStatus()

        installKeyboard()
        startElapsedTimer()

        // Make sure the control window is actually in front of the operator, on their Space.
        NSApp.activate(ignoringOtherApps: true)
        operatorController.window.makeKeyAndOrderFront(nil)
        operatorController.window.orderFrontRegardless()

        Logger.shared.info("ShowRunner ready.")

        // --- Lighting module (separate, fail-safe) ---------------------------------------------
        // Connect the lighting feature. It reads the audio playback clock through a read-only
        // adapter and runs entirely in its own module/window. If it is disabled or anything goes
        // wrong, `lighting` stays nil and the audio show is completely unaffected.
        lighting = LightingBridge(engine: audioEngine, showRoot: root)
        lighting?.start()
        operatorController.setLightingWindowsAvailable(lighting?.isActive ?? false)
        // ---------------------------------------------------------------------------------------

        // Phone web remote (separate, fail-safe): serves a control page the operator's phone
        // opens in Safari over Wi-Fi/Tailscale. Purely additive — if it fails to start or the
        // network dies, the keyboard still runs the entire show.
        startRemoteServer()

        // Hidden debug hook: dump the (re-encoded) config to a path and quit — verifies save round-trips.
        if let dump = ProcessInfo.processInfo.environment["SHOWRUNNER_DUMPCONFIG"] {
            ConfigLoader.save(config, to: URL(fileURLWithPath: dump))
            Logger.shared.info("Dumped config to \(dump)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
            return
        }

        // Hidden debug hook: SHOWRUNNER_SELFPLAY=6,9,12 auto-fires those pieces 4s apart.
        if let order = ProcessInfo.processInfo.environment["SHOWRUNNER_SELFPLAY"] {
            let orders = order.split(separator: ",").map(String.init)
            for (k, ord) in orders.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(k) * 4.0) { [weak self] in
                    guard let self = self, let idx = self.pieces.firstIndex(where: { $0.piece.order == ord }) else { return }
                    Logger.shared.info("SELFPLAY firing piece \(ord)")
                    self.selectIndex(idx)
                    self.go()
                }
            }
        }
    }

    private func preloadImages() {
        for m in pieces where !m.piece.isSpeaking {
            if let url = m.titleCardURL, FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url) {
                m.image = img
                m.imageReady = true
            } else {
                m.imageReady = false
                Logger.shared.warn("Missing title card for [\(m.piece.order)] \(m.piece.title)")
            }
        }
    }

    /// (Re)load all EDM premixes at the current engine sample rate.
    private func reloadAudio() {
        for m in pieces where m.piece.hasAudio {
            guard let b = m.backingURL, let c = m.clickURL,
                  FileManager.default.fileExists(atPath: b.path),
                  FileManager.default.fileExists(atPath: c.path) else {
                m.audioReady = false
                m.premix = nil
                m.loadError = "file missing"
                Logger.shared.warn("Missing audio file for [\(m.piece.order)] \(m.piece.title)")
                continue
            }
            do {
                let r = try audioEngine.loadPremix(backingURL: b, clickURL: c)
                m.premix = r.premix
                m.audioReady = true
                m.loadError = nil
                let drift = abs(r.backingFrames - r.clickFrames)
                Logger.shared.info("Loaded [\(m.piece.order)] \(m.piece.title): backing \(r.backingFrames)f, click \(r.clickFrames)f @ \(Int(r.targetRate))Hz (pad \(drift)f)")
            } catch {
                m.premix = nil
                m.audioReady = false
                m.loadError = "\(error)"
                Logger.shared.error("Failed to load audio for [\(m.piece.order)]: \(error)")
            }
        }
    }

    // MARK: UI refresh

    private func refreshRows() {
        let infos = pieces.map { m -> PieceRowInfo in
            let ready: Bool
            let status: String
            if m.piece.isSpeaking {
                ready = true; status = "SPEAKING"
            } else if !m.imageReady {
                ready = false; status = "NO TITLE CARD"
            } else if m.piece.hasAudio {
                ready = m.audioReady
                status = m.audioReady ? "AUDIO READY" : "AUDIO MISSING"
            } else {
                ready = true; status = "—"
            }
            return PieceRowInfo(order: m.piece.order, title: m.piece.title,
                                subtitle: m.piece.subtitle, hasAudio: m.piece.hasAudio,
                                ready: ready, statusText: status)
        }
        operatorController.setPieces(infos)
        operatorController.setSelected(selectedIndex)
        operatorController.setPlaying(index: playingIndex)
    }

    private func refreshDevicePopup() {
        let names = availableDevices.map { "\($0.name) (\($0.outputChannels)ch)" }
        let sel = availableDevices.firstIndex(where: { $0.id == audioEngine.deviceID }) ?? -1
        operatorController.setDevices(names, selected: sel)
    }

    private func refreshDisplayPopup() {
        let screens = NSScreen.screens
        let names = screens.enumerated().map { (i, s) -> String in
            let main = (s == NSScreen.main) ? " (Main)" : ""
            return "Display \(i + 1)\(main) — \(Int(s.frame.width))×\(Int(s.frame.height))"
        }
        let sel = min(max(0, config.audienceDisplayIndex), max(0, screens.count - 1))
        operatorController.setDisplays(names.isEmpty ? ["No display"] : names, selected: sel)
    }

    /// Output channel pairs available on the current device, 0-based.
    private func availablePairs() -> [(Int, Int)] {
        let c = audioEngine.deviceChannels
        var pairs: [(Int, Int)] = []
        var i = 0
        while i + 1 < c { pairs.append((i, i + 1)); i += 2 }
        if pairs.isEmpty { pairs.append((0, 1)) }
        return pairs
    }

    private func applyRoutingFromConfig() {
        let b = config.backingChannels ?? [1, 2]
        let c = config.clickChannels ?? [3, 4]
        let backing = (max(0, (b.first ?? 1) - 1), max(0, (b.count > 1 ? b[1] : 2) - 1))
        let click = (max(0, (c.first ?? 3) - 1), max(0, (c.count > 1 ? c[1] : 4) - 1))
        audioEngine.setRouting(backing: backing, click: click)
    }

    private func refreshChannelPopups() {
        let pairs = availablePairs()
        let labels = pairs.map { "Out \($0.0 + 1)·\($0.1 + 1)" }
        let bSel = pairs.firstIndex(where: { $0 == audioEngine.backingChannels }) ?? 0
        let cSel = pairs.firstIndex(where: { $0 == audioEngine.clickChannels }) ?? min(1, pairs.count - 1)
        operatorController.setChannelPairs(labels, backingSel: bSel, clickSel: cSel)
    }

    private func updateStatus() {
        var parts: [String] = []
        if audioEngine.deviceReady {
            parts.append("Audio: \(audioEngine.deviceName) · \(audioEngine.deviceChannels)ch @ \(Int(audioEngine.sampleRate))Hz")
            let b = audioEngine.backingChannels, c = audioEngine.clickChannels
            if audioEngine.clickFolded {
                parts.append("⚠︎ \(audioEngine.deviceChannels)-ch out — backing+click summed to \(b.0 + 1)·\(b.1 + 1) (stereo)")
            } else {
                parts.append("Backing→\(b.0 + 1)·\(b.1 + 1)  Click→\(c.0 + 1)·\(c.1 + 1)")
            }
        } else {
            parts.append("⚠︎ No audio device — EDM pieces will be silent")
        }
        parts.append("Screens: \(NSScreen.screens.count)")
        operatorController.setStatus(parts.joined(separator: "   |   "))
    }

    // MARK: Audience display

    private func applyAudienceDisplay(index: Int) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let idx = min(max(0, index), screens.count - 1)
        if idx != index {
            Logger.shared.warn("Audience display \(index + 1) unavailable (\(screens.count) screen(s)); using display \(idx + 1).")
            operatorController.setNowPlaying("⚠︎ Audience display \(index + 1) unavailable — using display \(idx + 1)")
        }
        let target = screens[idx]
        let operatorScreen = operatorController.window.screen ?? NSScreen.main
        // Fullscreen only when the audience screen is a DIFFERENT screen from the operator's,
        // otherwise it would cover the control UI — fall back to a windowed preview.
        let fullscreen = (target != operatorScreen)
        audienceWindow.place(on: target, fullscreen: fullscreen)
        // Placing the audience window must never steal focus from — or sit on top of — the
        // operator window. Bring the control window back to the front and make it key.
        operatorController.window.makeKeyAndOrderFront(nil)
        Logger.shared.info("Audience display -> index \(idx) (\(fullscreen ? "fullscreen" : "windowed preview"))")
    }

    // MARK: Transport

    private func go() {
        guard selectedIndex >= 0, selectedIndex < pieces.count else { return }
        pausedIndex = nil
        let m = pieces[selectedIndex]
        Logger.shared.info("GO [\(m.piece.order)] \(m.piece.title)")

        if m.piece.isSpeaking {
            // Speaking cue: fade the projector to black, stop any audio, fade lights.
            // The speech text itself lives only on the phone remote.
            audioEngine.stop()
            lighting?.stop()
            audienceWindow.clear()
            playingIndex = nil
            previewLightingIndex = nil
            operatorController.setPlaying(index: nil)
            updateScrubEnabled()
            operatorController.setNowPlaying("🎤  \(m.piece.title)")
            operatorController.setElapsed("––:–– / ––:––")
            operatorController.setRemaining("−––:––")
            operatorController.setProgress(0)
            updatePlayPauseButton()
            return
        }

        audienceWindow.showCard(m.imageReady ? m.image : nil)
        audioEngine.stop()
        operatorController.setProgress(0)
        operatorController.setRemaining("−––:––")

        if m.piece.hasAudio {
            // Only block if there is NO audio device at all. On a device with fewer than 4 outputs
            // (e.g. the 2-channel Mac speakers) the engine folds the click onto the backing pair so
            // the show still plays in stereo — no need to refuse.
            if !audioEngine.deviceReady {
                playingIndex = nil
                operatorController.setPlaying(index: nil)
                operatorController.setNowPlaying("⛔ \(m.piece.title) — no audio output device. Pick one from the Audio device menu.")
                operatorController.setElapsed("––:–– / ––:––")
                Logger.shared.error("Blocked GO [\(m.piece.order)] — no audio output device.")
            } else if let pre = m.premix {
                let p = config.pieces[selectedIndex]
                audioEngine.play(pre, pieceBackingDb: p.backingGainDb ?? 0, pieceClickDb: p.clickGainDb ?? 0)
                playingIndex = selectedIndex
                previewLightingIndex = nil
                operatorController.setPlaying(index: selectedIndex)
                updateScrubEnabled()
                let b = audioEngine.backingChannels
                let fold = audioEngine.clickFolded ? "  (stereo — click summed to outs \(b.0 + 1)·\(b.1 + 1))" : ""
                operatorController.setNowPlaying("▶  \(m.piece.order) — \(m.piece.title)\(fold)")
            } else {
                playingIndex = nil
                operatorController.setPlaying(index: nil)
                operatorController.setNowPlaying("⚠︎  \(m.piece.title) — audio missing")
                operatorController.setElapsed("––:–– / ––:––")
                Logger.shared.warn("GO with missing audio for [\(m.piece.order)]")
            }
        } else {
            playingIndex = nil
            previewLightingIndex = nil
            operatorController.setPlaying(index: nil)
            updateScrubEnabled()
            operatorController.setNowPlaying("\(m.piece.order) — \(m.piece.title)  (no audio)")
            operatorController.setElapsed("––:–– / ––:––")
        }
        updateScrubEnabled()

        // Tell the (optional) lighting module which piece fired so it can select that piece's
        // program. Done LAST — after audioEngine.play() has reset the clock to 0 — so lighting is
        // never on the GO→sound critical path and never samples the previous piece's stale clock.
        // No-op when lighting is off; never blocks or affects audio.
        lighting?.pieceDidStart(order: m.piece.order)
        updatePlayPauseButton()
    }

    private func stop() {
        Logger.shared.info("STOP / PANIC")
        lighting?.stop()   // softly fade lights out alongside the audio panic (no-op if off)
        audioEngine.stop()
        audienceWindow.clear()
        playingIndex = nil
        pausedIndex = nil
        previewLightingIndex = nil
        operatorController.setPlaying(index: nil)
        operatorController.setNowPlaying("— stopped —")
        operatorController.setElapsed("––:–– / ––:––")
        operatorController.setRemaining("−––:––")
        operatorController.setProgress(0)
        updateScrubEnabled()
        updatePlayPauseButton()
    }

    /// Phone PLAY/PAUSE button: pause the playing piece, resume the paused one,
    /// or — when nothing is active — behave exactly like GO.
    private func togglePlayPause() {
        if let pi = playingIndex, audioEngine.isPlaying {
            audioEngine.pause()
            pausedIndex = pi
            playingIndex = nil
            // Keep the green "active piece" row highlight while paused.
            operatorController.setPlaying(index: pi)
            let m = pieces[pi]
            operatorController.setNowPlaying("⏸  \(m.piece.order) — \(m.piece.title)  (paused)")
            Logger.shared.info("PAUSE [\(m.piece.order)] \(m.piece.title) at \(String(format: "%.1f", audioEngine.elapsedSeconds))s")
        } else if let qi = pausedIndex {
            audioEngine.resume()
            pausedIndex = nil
            playingIndex = qi
            operatorController.setPlaying(index: qi)
            let m = pieces[qi]
            operatorController.setNowPlaying("▶  \(m.piece.order) — \(m.piece.title)")
            Logger.shared.info("RESUME [\(m.piece.order)] \(m.piece.title)")
        } else {
            go()
        }
        updatePlayPauseButton()
    }

    /// Keyboard [ / ] : move the on-deck selection one piece (clamped) and fire it immediately.
    private func goRelative(_ delta: Int) {
        selectIndex(selectedIndex + delta)
        go()
    }

    private func selectIndex(_ i: Int) {
        guard !pieces.isEmpty else { return }
        selectedIndex = min(max(0, i), pieces.count - 1)
        operatorController.setSelected(selectedIndex)
        let m = pieces[selectedIndex]
        let tag = m.piece.isSpeaking ? "  🎤" : (m.piece.hasAudio ? "  ♪" : "")
        operatorController.setOnDeck("\(m.piece.order) — \(m.piece.title)\(tag)")
        updatePieceTrimUI()
        updateScrubEnabled()
        if playingIndex == nil {
            previewLightingIndex = nil
            if let total = durationSeconds(for: selectedIndex) {
                operatorController.setElapsed("00:00 / \(AppController.fmt(total))")
                operatorController.setRemaining("−\(AppController.fmt(total))")
            } else {
                operatorController.setElapsed("––:–– / ––:––")
                operatorController.setRemaining("−––:––")
            }
            operatorController.setProgress(0)
        }
    }

    private func updateScrubEnabled() {
        let index = playingIndex ?? selectedIndex
        let enabled = pieces.indices.contains(index) && pieces[index].piece.hasAudio && pieces[index].premix != nil
        operatorController.setScrubEnabled(enabled)
    }

    /// Keep the operator window's PLAY/PAUSE button in sync with transport state (same model the
    /// phone remote shows). Called after every transport change.
    private func updatePlayPauseButton() {
        let state = playingIndex != nil ? "playing" : (pausedIndex != nil ? "paused" : "stopped")
        operatorController.setPlayPauseState(state)
    }

    private func durationSeconds(for index: Int) -> Double? {
        guard pieces.indices.contains(index), let pre = pieces[index].premix else { return nil }
        let rate = pre.sampleRate > 0 ? pre.sampleRate : audioEngine.sampleRate
        guard rate > 0 else { return nil }
        return Double(pre.frameCount) / rate
    }

    private func updatePieceTrimUI() {
        guard selectedIndex < config.pieces.count else { return }
        let p = config.pieces[selectedIndex]
        if p.hasAudio {
            operatorController.setPieceTrim(enabled: true, caption: "PER-PIECE TRIM — \(p.title)",
                                            backingDb: p.backingGainDb ?? 0, clickDb: p.clickGainDb ?? 0)
        } else {
            operatorController.setPieceTrim(enabled: false, caption: "PER-PIECE TRIM (audio pieces only)",
                                            backingDb: 0, clickDb: 0)
        }
    }

    /// Bump a master fader by `delta` dB (from the keyboard), clamp, update UI + save.
    private func nudgeMaster(backing: Bool, delta: Double) {
        var b = audioEngine.masterBackingDb
        var c = audioEngine.masterClickDb
        if backing { b = min(6, max(-40, b + delta)) } else { c = min(6, max(-40, c + delta)) }
        audioEngine.setMasterGains(backingDb: b, clickDb: c)
        config.masterBackingGainDb = b
        config.masterClickGainDb = c
        operatorController.setMasterLevels(backingDb: b, clickDb: c)
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let url = self.configURL else { return }
            ConfigLoader.save(self.config, to: url)
            Logger.shared.info("Saved levels to \(url.lastPathComponent)")
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    // MARK: Phone remote

    private func startRemoteServer() {
        let port = UInt16(clamping: config.remotePort ?? 8088)
        let server = RemoteServer(port: port)
        server.onAction = { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .next: self.selectIndex(self.selectedIndex + 1)
            case .prev: self.selectIndex(self.selectedIndex - 1)
            case .go:     self.go()
            case .stop:   self.stop()
            case .toggle: self.togglePlayPause()
            }
        }
        server.onSelect = { [weak self] i in self?.selectIndex(i) }
        server.onArmMovers = { [weak self] in self?.lighting?.toggleArmMovers() }
        server.onEditNotes = { [weak self] i, text in
            guard let self = self, self.config.pieces.indices.contains(i),
                  self.config.pieces[i].isSpeaking else { return }
            self.config.pieces[i].notes = text
            self.scheduleSave()
            Logger.shared.info("Speech notes edited from phone for [\(self.config.pieces[i].order)] (\(text.count) chars)")
        }
        server.stateProvider = { [weak self] in
            self?.remoteState() ?? RemoteState(pieces: [], selected: 0, playing: nil, playState: "stopped",
                                               onDeck: "", nowPlaying: "", elapsed: "", remaining: "", progress: 0,
                                               lightingArmable: false, lightingArmed: false)
        }
        if let err = server.start() {
            Logger.shared.error("Phone remote failed to start on port \(port): \(err)")
            operatorController.setRemoteInfo("⚠︎ Phone remote OFF — port \(port) unavailable")
        } else {
            remoteServer = server
            refreshRemoteInfo()
        }
    }

    private func remoteState() -> RemoteState {
        let infos = pieces.enumerated().map { (i, m) -> RemotePieceState in
            let ready = m.piece.isSpeaking || (m.imageReady && (!m.piece.hasAudio || m.audioReady))
            // Notes come from the live config (not the PieceModel snapshot) so phone
            // edits are reflected immediately.
            let notes = (m.piece.isSpeaking && config.pieces.indices.contains(i)) ? config.pieces[i].notes : nil
            return RemotePieceState(order: m.piece.order, title: m.piece.title,
                                    subtitle: m.piece.subtitle, hasAudio: m.piece.hasAudio,
                                    ready: ready, speaking: m.piece.isSpeaking, notes: notes)
        }
        let playState = playingIndex != nil ? "playing" : (pausedIndex != nil ? "paused" : "stopped")
        return RemoteState(pieces: infos,
                           selected: selectedIndex,
                           playing: playingIndex ?? pausedIndex,
                           playState: playState,
                           onDeck: operatorController.onDeckText,
                           nowPlaying: operatorController.nowPlayingText,
                           elapsed: operatorController.elapsedText,
                           remaining: operatorController.remainingText,
                           progress: operatorController.progressValue,
                           lightingArmable: lighting?.moversArmable ?? false,
                           lightingArmed: lighting?.moversArmed ?? false)
    }

    /// Show the URL(s) the phone can reach us on. Re-checked every few seconds because the
    /// Mac's addresses change when it hops networks (venue Wi-Fi → hotspot) mid-soundcheck.
    private func refreshRemoteInfo() {
        guard let server = remoteServer else { return }
        let addrs = RemoteServer.localIPv4Addresses()
        guard !addrs.isEmpty else {
            operatorController.setRemoteInfo("📱 Phone remote: waiting for a network… (port \(server.port))")
            return
        }
        let parts = addrs.prefix(3).map { a -> String in
            let tag = a.isTailscale ? " (Tailscale)" : ""
            return "http://\(a.address):\(server.port)\(tag)"
        }
        operatorController.setRemoteInfo("📱 Phone remote:  " + parts.joined(separator: "   ·   "))
    }

    // MARK: Elapsed timer

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        let t = Timer(timeInterval: 0.1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        elapsedTimer = t
    }

    @objc private func tick() {
        // Meters always reflect the engine, so they decay to zero when audio stops.
        operatorController.setMeters(backing: audioEngine.backingLevel, click: audioEngine.clickLevel)
        remoteInfoTick += 1
        if remoteInfoTick >= 50 {   // every ~5s: cheap, and tracks network hops
            remoteInfoTick = 0
            refreshRemoteInfo()
        }
        guard let pi = playingIndex, pi < pieces.count, let pre = pieces[pi].premix else { return }
        let rate = pre.sampleRate > 0 ? pre.sampleRate : audioEngine.sampleRate
        let total = rate > 0 ? Double(pre.frameCount) / rate : 0
        let elapsed = min(audioEngine.elapsedSeconds, total)
        operatorController.setElapsed("\(AppController.fmt(elapsed)) / \(AppController.fmt(total))")
        operatorController.setRemaining("−\(AppController.fmt(max(0, total - elapsed)))")
        operatorController.setProgress(total > 0 ? elapsed / total : 0)
        if !audioEngine.isPlaying {
            playingIndex = nil
            previewLightingIndex = nil
            operatorController.setPlaying(index: nil)
            operatorController.setNowPlaying("— finished —")
            operatorController.setProgress(1)
            operatorController.setRemaining("−00:00")
            updateScrubEnabled()
            updatePlayPauseButton()
        }
    }

    private static func fmt(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Keyboard

    private func installKeyboard() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // Let system/menu shortcuts (Cmd-Q, Cmd-W, …) pass through untouched.
            if event.modifierFlags.contains(.command) { return event }
            switch event.keyCode {
            case 49, 36, 76:  // space, return, keypad-enter → play/pause
                if event.isARepeat { return nil }   // ignore auto-repeat so a held key can't re-toggle
                self.togglePlayPause(); return nil
            case 30:          // ]  → next piece + play
                if event.isARepeat { return nil }
                self.goRelative(+1); return nil
            case 33:          // [  → previous piece + play
                if event.isARepeat { return nil }
                self.goRelative(-1); return nil
            case 125:         // down arrow → move on-deck selection (no play)
                self.selectIndex(self.selectedIndex + 1); return nil
            case 126:         // up arrow → move on-deck selection (no play)
                self.selectIndex(self.selectedIndex - 1); return nil
            case 53:          // escape → STOP / PANIC
                if event.isARepeat { return nil }
                self.stop(); return nil
            case 25: self.nudgeMaster(backing: true,  delta: -1); return nil  // 9  backing down
            case 29: self.nudgeMaster(backing: true,  delta: +1); return nil  // 0  backing up
            case 27: self.nudgeMaster(backing: false, delta: -1); return nil  // -  click down
            case 24: self.nudgeMaster(backing: false, delta: +1); return nil  // =  click up
            default:
                return event
            }
        }
    }

    // MARK: OperatorWindowDelegate

    func operatorDidPressGo() { go() }
    func operatorDidPressPlayPause() { togglePlayPause() }
    func operatorDidPressStop() { stop() }
    func operatorDidPressCloseApplication() { NSApp.terminate(nil) }
    func operatorDidSelect(index: Int) { selectIndex(index) }

    /// Operator "Show window" buttons — re-open a window that was closed (or just bring it forward).
    func operatorDidRequestShowWindow(_ target: OperatorWindowTarget) {
        switch target {
        case .audience:        applyAudienceDisplay(index: config.audienceDisplayIndex)
        case .lighting:        lighting?.showLightingWindow()
        case .lightingPreview: lighting?.showPreviewWindow()
        }
    }

    func operatorDidSeek(toFraction fraction: Double) {
        let index = playingIndex ?? selectedIndex
        guard pieces.indices.contains(index), let pre = pieces[index].premix else { return }
        let total = durationSeconds(for: index) ?? 0
        let clamped = min(1, max(0, fraction))
        let seconds = clamped * total

        if playingIndex == index {
            audioEngine.seek(toSeconds: seconds)
        } else {
            let p = config.pieces[index]
            audioEngine.cue(pre, pieceBackingDb: p.backingGainDb ?? 0, pieceClickDb: p.clickGainDb ?? 0, atSeconds: seconds)
            if previewLightingIndex != index {
                lighting?.pieceDidStart(order: pieces[index].piece.order)
                previewLightingIndex = index
            }
            operatorController.setNowPlaying("PREVIEW  \(pieces[index].piece.order) — \(pieces[index].piece.title)")
        }

        operatorController.setElapsed("\(AppController.fmt(seconds)) / \(AppController.fmt(total))")
        operatorController.setRemaining("−\(AppController.fmt(max(0, total - seconds)))")
        operatorController.setProgress(clamped)
    }

    func operatorDidChangeDevice(index: Int) {
        guard index >= 0, index < availableDevices.count else { return }
        let dev = availableDevices[index]
        let wasPlaying = playingIndex != nil
        if wasPlaying { stop() }
        let rate = config.engineSampleRate ?? 48000
        audioEngine.configure(device: dev, requestedRate: rate)
        applyRoutingFromConfig()
        reloadAudio()
        refreshChannelPopups()
        refreshRows()
        updateStatus()
    }

    func operatorDidChangeBackingPair(index: Int) {
        let pairs = availablePairs()
        guard index >= 0, index < pairs.count else { return }
        if playingIndex != nil { stop() }
        audioEngine.setRouting(backing: pairs[index], click: audioEngine.clickChannels)
        config.backingChannels = [pairs[index].0 + 1, pairs[index].1 + 1]
        updateStatus()
    }

    func operatorDidChangeClickPair(index: Int) {
        let pairs = availablePairs()
        guard index >= 0, index < pairs.count else { return }
        if playingIndex != nil { stop() }
        audioEngine.setRouting(backing: audioEngine.backingChannels, click: pairs[index])
        config.clickChannels = [pairs[index].0 + 1, pairs[index].1 + 1]
        updateStatus()
    }

    func operatorDidChangeDisplay(index: Int) {
        config.audienceDisplayIndex = index
        applyAudienceDisplay(index: index)
        updateStatus()
    }

    func operatorDidSetMasterBacking(db: Double) {
        audioEngine.setMasterGains(backingDb: db, clickDb: audioEngine.masterClickDb)
        config.masterBackingGainDb = db
        scheduleSave()
    }

    func operatorDidSetMasterClick(db: Double) {
        audioEngine.setMasterGains(backingDb: audioEngine.masterBackingDb, clickDb: db)
        config.masterClickGainDb = db
        scheduleSave()
    }

    func operatorDidSetPieceBacking(db: Double) {
        guard selectedIndex < config.pieces.count, config.pieces[selectedIndex].hasAudio else { return }
        config.pieces[selectedIndex].backingGainDb = db
        if playingIndex == selectedIndex {
            audioEngine.setPieceTrim(backingDb: db, clickDb: config.pieces[selectedIndex].clickGainDb ?? 0)
        }
        scheduleSave()
    }

    func operatorDidSetPieceClick(db: Double) {
        guard selectedIndex < config.pieces.count, config.pieces[selectedIndex].hasAudio else { return }
        config.pieces[selectedIndex].clickGainDb = db
        if playingIndex == selectedIndex {
            audioEngine.setPieceTrim(backingDb: config.pieces[selectedIndex].backingGainDb ?? 0, clickDb: db)
        }
        scheduleSave()
    }

    // MARK: Errors

    private func presentFatalConfigError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "ShowRunner could not start"
        alert.informativeText = message
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    func teardown() {
        if let k = keyMonitor { NSEvent.removeMonitor(k) }
        elapsedTimer?.invalidate()
        remoteServer?.stop()
        lighting?.shutdown()   // stop sACN + close the lighting window cleanly (no-op if off)
        audioEngine.stop()
    }
}
