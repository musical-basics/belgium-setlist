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
        let folder = root.appendingPathComponent(piece.folder, isDirectory: true)
        self.titleCardURL = folder.appendingPathComponent(piece.titleCard)
        self.backingURL = piece.backing.map { folder.appendingPathComponent($0) }
        self.clickURL = piece.click.map { folder.appendingPathComponent($0) }
    }
}

final class AppController: NSObject, OperatorWindowDelegate {
    private let configPath: String?
    private var config: ShowConfig!
    private var root: URL!

    private let audioEngine = AudioEngine()
    private var audienceWindow: AudienceWindow!
    private var operatorController: OperatorWindowController!

    private var pieces: [PieceModel] = []
    private var availableDevices: [AudioDeviceInfo] = []
    private var selectedIndex = 0
    private var playingIndex: Int?

    private var keyMonitor: Any?
    private var elapsedTimer: Timer?

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
        if let dev = AudioEngine.findDevice(named: config.audioDeviceName) {
            audioEngine.configure(device: dev, requestedRate: rate)
        } else {
            Logger.shared.warn("Audio device '\(config.audioDeviceName)' not found — pick one from the menu.")
        }
        reloadAudio()

        // Populate UI
        refreshDevicePopup()
        refreshDisplayPopup()
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
    }

    private func preloadImages() {
        for m in pieces {
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
            if !m.imageReady {
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

    private func updateStatus() {
        var parts: [String] = []
        if audioEngine.deviceReady {
            parts.append("Audio: \(audioEngine.deviceName) · \(audioEngine.deviceChannels)ch @ \(Int(audioEngine.sampleRate))Hz")
            parts.append(audioEngine.clickRouted ? "Backing→1·2  Click→3·4" : "⚠︎ <4 outputs: click NOT routed")
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
        let m = pieces[selectedIndex]
        Logger.shared.info("GO [\(m.piece.order)] \(m.piece.title)")

        audienceWindow.showCard(m.imageReady ? m.image : nil)
        audioEngine.stop()
        operatorController.setProgress(0)
        operatorController.setRemaining("−––:––")

        if m.piece.hasAudio {
            // Refuse to play an EDM piece if the current device can't route the click to
            // outs 3·4 — better a clear warning than blasting backing out the wrong output.
            if !audioEngine.deviceReady || !audioEngine.clickRouted {
                playingIndex = nil
                operatorController.setPlaying(index: nil)
                let reason = audioEngine.deviceReady ? "device has <4 outputs" : "no audio device"
                operatorController.setNowPlaying("⛔ \(m.piece.title) — \(reason). Select the Audient iD44.")
                operatorController.setElapsed("––:–– / ––:––")
                Logger.shared.error("Blocked GO [\(m.piece.order)] — \(reason); click cannot route.")
            } else if let pre = m.premix {
                audioEngine.play(pre)
                playingIndex = selectedIndex
                operatorController.setPlaying(index: selectedIndex)
                operatorController.setNowPlaying("▶  \(m.piece.order) — \(m.piece.title)")
            } else {
                playingIndex = nil
                operatorController.setPlaying(index: nil)
                operatorController.setNowPlaying("⚠︎  \(m.piece.title) — audio missing")
                operatorController.setElapsed("––:–– / ––:––")
                Logger.shared.warn("GO with missing audio for [\(m.piece.order)]")
            }
        } else {
            playingIndex = nil
            operatorController.setPlaying(index: nil)
            operatorController.setNowPlaying("\(m.piece.order) — \(m.piece.title)  (no audio)")
            operatorController.setElapsed("––:–– / ––:––")
        }
    }

    private func stop() {
        Logger.shared.info("STOP / PANIC")
        audioEngine.stop()
        audienceWindow.clear()
        playingIndex = nil
        operatorController.setPlaying(index: nil)
        operatorController.setNowPlaying("— stopped —")
        operatorController.setElapsed("––:–– / ––:––")
        operatorController.setRemaining("−––:––")
        operatorController.setProgress(0)
    }

    private func selectIndex(_ i: Int) {
        guard !pieces.isEmpty else { return }
        selectedIndex = min(max(0, i), pieces.count - 1)
        operatorController.setSelected(selectedIndex)
        let m = pieces[selectedIndex]
        let tag = m.piece.hasAudio ? "  ♪" : ""
        operatorController.setOnDeck("\(m.piece.order) — \(m.piece.title)\(tag)")
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
        guard let pi = playingIndex, pi < pieces.count, let pre = pieces[pi].premix else { return }
        let total = audioEngine.sampleRate > 0 ? Double(pre.frameCount) / audioEngine.sampleRate : 0
        let elapsed = min(audioEngine.elapsedSeconds, total)
        operatorController.setElapsed("\(AppController.fmt(elapsed)) / \(AppController.fmt(total))")
        operatorController.setRemaining("−\(AppController.fmt(max(0, total - elapsed)))")
        operatorController.setProgress(total > 0 ? elapsed / total : 0)
        if !audioEngine.isPlaying {
            playingIndex = nil
            operatorController.setPlaying(index: nil)
            operatorController.setNowPlaying("— finished —")
            operatorController.setProgress(1)
            operatorController.setRemaining("−00:00")
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
            case 49, 36, 76:  // space, return, keypad-enter
                if event.isARepeat { return nil }   // ignore auto-repeat so a held key can't re-fire GO
                self.go(); return nil
            case 125:         // down arrow
                self.selectIndex(self.selectedIndex + 1); return nil
            case 126:         // up arrow
                self.selectIndex(self.selectedIndex - 1); return nil
            case 53:          // escape
                if event.isARepeat { return nil }
                self.stop(); return nil
            default:
                return event
            }
        }
    }

    // MARK: OperatorWindowDelegate

    func operatorDidPressGo() { go() }
    func operatorDidPressStop() { stop() }
    func operatorDidSelect(index: Int) { selectIndex(index) }

    func operatorDidChangeDevice(index: Int) {
        guard index >= 0, index < availableDevices.count else { return }
        let dev = availableDevices[index]
        let wasPlaying = playingIndex != nil
        if wasPlaying { stop() }
        let rate = config.engineSampleRate ?? 48000
        audioEngine.configure(device: dev, requestedRate: rate)
        reloadAudio()
        refreshRows()
        updateStatus()
    }

    func operatorDidChangeDisplay(index: Int) {
        config.audienceDisplayIndex = index
        applyAudienceDisplay(index: index)
        updateStatus()
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
        audioEngine.stop()
    }
}
