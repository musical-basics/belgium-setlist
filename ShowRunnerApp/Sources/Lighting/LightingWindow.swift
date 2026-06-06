import AppKit

/// Actions the Lighting window asks the controller to perform. Kept tiny and one-way.
public protocol LightingWindowDelegate: AnyObject {
    func lightingToggleBlackout()
    func lightingToggleHold()
    func lightingAdvanceCue()
    func lightingPreviousCue()
    func lightingProofOfLife(fixture: String)
    func lightingSetArmProvisional(_ armed: Bool)
    func lightingStatus() -> LightingStatus
}

/// The lighting operator's own window — completely separate from the audio operator window, so
/// nothing here can disturb the sound app's UI. Big BLACKOUT and HOLD safety controls, a
/// proof-of-life trigger, cue advance for the quiet pieces, an arm switch for the provisional
/// movers, a live status readout, and the venue CONFIRM checklist.
public final class LightingWindowController {
    public let window: NSWindow
    private weak var delegate: LightingWindowDelegate?
    private let proofFixtureName: String

    private let statusLabel = NSTextField(labelWithString: "—")
    private let pieceLabel = NSTextField(labelWithString: "—")
    private let cueLabel = NSTextField(labelWithString: "—")
    private let provLabel = NSTextField(labelWithString: "")
    private let blackoutButton = NSButton(title: "BLACKOUT", target: nil, action: nil)
    private let holdButton = NSButton(title: "HOLD", target: nil, action: nil)
    private let proofButton = NSButton(title: "PROOF OF LIFE", target: nil, action: nil)
    private let prevCueButton = NSButton(title: "◀ PREV CUE", target: nil, action: nil)
    private let nextCueButton = NSButton(title: "NEXT CUE ▶", target: nil, action: nil)
    private let armButton = NSButton(title: "ARM MOVERS", target: nil, action: nil)
    private var refreshTimer: Timer?

    public init(delegate: LightingWindowDelegate, confirmChecklist: String, proofFixtureName: String) {
        self.delegate = delegate
        self.proofFixtureName = proofFixtureName

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Lighting"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        // Show on the active Space without stealing key focus from the audio operator window.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        buildLayout(confirmChecklist: confirmChecklist)
    }

    public func show() {
        // Top-left of the main screen, clear of the centered operator window.
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: f.minX + 24, y: f.maxY - 24))
        }
        window.orderFrontRegardless()   // visible, but does NOT become key
        startRefresh()
    }

    public func close() {
        refreshTimer?.invalidate(); refreshTimer = nil
        window.close()
    }

    // MARK: Layout

    private func buildLayout(confirmChecklist: String) {
        let content = NSView()
        window.contentView = content

        let title = NSTextField(labelWithString: "Lighting — sACN")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        pieceLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        cueLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        cueLabel.textColor = .secondaryLabelColor
        provLabel.font = .systemFont(ofSize: 12, weight: .bold)
        provLabel.textColor = .systemOrange
        provLabel.lineBreakMode = .byWordWrapping
        provLabel.maximumNumberOfLines = 2

        styleButton(blackoutButton, color: .systemRed, height: 70, fontSize: 22, action: #selector(blackoutTapped))
        styleButton(holdButton, color: .systemGray, height: 44, fontSize: 16, action: #selector(holdTapped))
        styleButton(proofButton, color: .systemBlue, height: 44, fontSize: 16, action: #selector(proofTapped))
        styleButton(prevCueButton, color: .systemGray, height: 44, fontSize: 15, action: #selector(prevTapped))
        styleButton(nextCueButton, color: .systemGreen, height: 44, fontSize: 15, action: #selector(nextTapped))
        styleButton(armButton, color: .systemGray, height: 40, fontSize: 14, action: #selector(armTapped))

        let cueRow = NSStackView(views: [prevCueButton, nextCueButton])
        cueRow.orientation = .horizontal
        cueRow.distribution = .fillEqually
        cueRow.spacing = 12

        let smallRow = NSStackView(views: [holdButton, proofButton])
        smallRow.orientation = .horizontal
        smallRow.distribution = .fillEqually
        smallRow.spacing = 12

        // CONFIRM checklist (venue's outstanding answers).
        let checklistCaption = NSTextField(labelWithString: "VENUE CONFIRM CHECKLIST")
        checklistCaption.font = .systemFont(ofSize: 11, weight: .heavy)
        checklistCaption.textColor = .secondaryLabelColor
        let checklist = NSTextField(wrappingLabelWithString: confirmChecklist)
        checklist.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        checklist.textColor = .tertiaryLabelColor
        checklist.isSelectable = true

        let stack = NSStackView(views: [
            title, statusLabel, pieceLabel, cueLabel,
            blackoutButton, cueRow, smallRow,
            armButton, provLabel,
            spacer(8), checklistCaption, checklist,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let m: CGFloat = 18
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -m),
            blackoutButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            blackoutButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            cueRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            cueRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            smallRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            smallRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            armButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            armButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            checklist.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    private func styleButton(_ b: NSButton, color: NSColor, height: CGFloat, fontSize: CGFloat, action: Selector) {
        b.bezelStyle = .regularSquare
        b.font = .systemFont(ofSize: fontSize, weight: .bold)
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.contentTintColor = .white
        b.layer?.backgroundColor = color.cgColor
        b.layer?.cornerRadius = 8
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    // MARK: Actions

    @objc private func blackoutTapped() { delegate?.lightingToggleBlackout() }
    @objc private func holdTapped() { delegate?.lightingToggleHold() }
    @objc private func proofTapped() { delegate?.lightingProofOfLife(fixture: proofFixtureName) }
    @objc private func nextTapped() { delegate?.lightingAdvanceCue() }
    @objc private func prevTapped() { delegate?.lightingPreviousCue() }
    @objc private func armTapped() {
        let armed = !(delegate?.lightingStatus().armProvisional ?? false)
        delegate?.lightingSetArmProvisional(armed)
    }

    // MARK: Refresh

    private func startRefresh() {
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 0.1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    @objc private func refresh() {
        guard let s = delegate?.lightingStatus() else { return }

        let net = s.sending ? "SENDING" : "not sending"
        statusLabel.stringValue = "\(net)  ·  universes \(s.universes.map(String.init).joined(separator: ","))"
        statusLabel.textColor = s.sending ? .systemGreen : .systemRed

        pieceLabel.stringValue = "Piece \(s.pieceOrder ?? "—")   ·   mode: \(s.mode)"

        switch s.mode {
        case "timecode": cueLabel.stringValue = String(format: "position %6.2fs%@", s.position, s.hold ? "   (HELD)" : "")
        case "cue":      cueLabel.stringValue = "cue \(s.cueIndex + 1)/\(s.cueCount)  “\(s.cueLabel ?? "")”\(s.hold ? "   (HELD)" : "")"
        case "proof":    cueLabel.stringValue = "PROOF OF LIFE running…"
        default:         cueLabel.stringValue = s.hold ? "(HELD)" : "idle"
        }

        // Reflect latched states in the buttons.
        blackoutButton.title = s.blackout ? "● BLACKOUT (ON)" : "BLACKOUT"
        blackoutButton.layer?.backgroundColor = (s.blackout ? NSColor.systemRed : NSColor.systemRed.withAlphaComponent(0.65)).cgColor
        holdButton.title = s.hold ? "● HOLD (ON)" : "HOLD"
        holdButton.layer?.backgroundColor = (s.hold ? NSColor.systemYellow : NSColor.systemGray).cgColor

        if s.hasProvisional {
            armButton.title = s.armProvisional ? "● MOVERS ARMED" : "ARM MOVERS (Spiider/Dalis)"
            armButton.layer?.backgroundColor = (s.armProvisional ? NSColor.systemOrange : NSColor.systemGray).cgColor
            provLabel.stringValue = s.armProvisional
                ? "⚠︎ Movers ARMED — verify Spiider mode matches the official chart before trusting output."
                : "Movers disarmed (Spiider/Dalis stay dark until their mode is confirmed)."
            armButton.isHidden = false
            provLabel.isHidden = false
        } else {
            armButton.isHidden = true
            provLabel.isHidden = true
        }
    }
}
