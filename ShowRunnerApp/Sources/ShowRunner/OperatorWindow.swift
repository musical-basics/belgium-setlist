import AppKit

/// A horizontal output-level meter (green → yellow → red) with a fast-rise / slow-fall ballistic
/// so the operator can see at a glance that audio is actually flowing to each output pair.
///
/// Implemented with CALayers + a static caption label — NO custom text drawing in draw(), which
/// is important: drawing a string with freshly-built font attributes on every redraw can throw
/// (`NSInvalidArgumentException`) under rapid updates and crash the app.
final class MeterView: NSView {
    private var level: CGFloat = 0
    private let barLayer = CALayer()
    private let captionLabel = NSTextField(labelWithString: "")

    init(caption: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        barLayer.anchorPoint = .zero
        barLayer.backgroundColor = NSColor.systemGreen.cgColor
        layer?.addSublayer(barLayer)

        captionLabel.stringValue = caption
        captionLabel.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        captionLabel.textColor = .white
        captionLabel.drawsBackground = false
        captionLabel.isBordered = false
        captionLabel.isEditable = false
        captionLabel.isSelectable = false
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionLabel)
        NSLayoutConstraint.activate([
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            captionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        updateBar()
    }

    /// Feed a new peak (0…1). Rises instantly, decays smoothly. Called on the main thread.
    func setLevel(_ newValue: Float) {
        let target = CGFloat(min(1, max(0, newValue)))
        level = target >= level ? target : max(target, level - 0.07)
        updateBar()
    }

    private func updateBar() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayer.backgroundColor = (level > 0.9 ? NSColor.systemRed
                                    : level > 0.7 ? NSColor.systemYellow
                                    : NSColor.systemGreen).cgColor
        barLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * level, height: bounds.height)
        CATransaction.commit()
    }
}

/// A transport scrubber that can be dragged or nudged with a scroll wheel/trackpad.
final class ScrubSlider: NSSlider {
    var isUserScrubbing = false

    override func mouseDown(with event: NSEvent) {
        isUserScrubbing = true
        super.mouseDown(with: event)
        isUserScrubbing = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { super.scrollWheel(with: event); return }
        let primary = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : -event.scrollingDeltaY
        let scale = event.hasPreciseScrollingDeltas ? 0.0025 : 0.04
        doubleValue = min(maxValue, max(minValue, doubleValue + Double(primary) * scale))
        if let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

/// Display info for a single piece row.
struct PieceRowInfo {
    let order: String
    let title: String
    let subtitle: String
    let hasAudio: Bool
    let ready: Bool        // false = a required file is missing
    let statusText: String // e.g. "READY", "NO AUDIO", "MISSING FILE"
}

/// A single big, readable row in the operator's running-order list.
final class PieceRowView: NSView {
    private let orderLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    private let info: PieceRowInfo
    var index: Int = 0
    var isSelected = false { didSet { updateAppearance() } }
    var isPlaying = false { didSet { updateAppearance() } }

    init(info: PieceRowInfo) {
        self.info = info
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 8

        orderLabel.stringValue = info.order
        orderLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        orderLabel.alignment = .center
        orderLabel.textColor = .secondaryLabelColor

        titleLabel.stringValue = info.title
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.stringValue = info.subtitle
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        badgeLabel.stringValue = info.hasAudio ? "AUDIO" : ""
        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 4
        badgeLabel.layer?.backgroundColor = info.hasAudio ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
        badgeLabel.isHidden = !info.hasAudio

        statusLabel.stringValue = info.statusText
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right

        statusDot.wantsLayer = true
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.layer?.cornerRadius = 7
        statusDot.layer?.backgroundColor = dotColor().cgColor

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let rightStack = NSStackView(views: [badgeLabel, statusLabel])
        rightStack.orientation = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 2

        let hstack = NSStackView(views: [statusDot, orderLabel, titleStack, NSView(), rightStack])
        hstack.orientation = .horizontal
        hstack.alignment = .centerY
        hstack.spacing = 14
        hstack.translatesAutoresizingMaskIntoConstraints = false
        hstack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        addSubview(hstack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 66),
            hstack.leadingAnchor.constraint(equalTo: leadingAnchor),
            hstack.trailingAnchor.constraint(equalTo: trailingAnchor),
            hstack.topAnchor.constraint(equalTo: topAnchor),
            hstack.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 14),
            statusDot.heightAnchor.constraint(equalToConstant: 14),
            orderLabel.widthAnchor.constraint(equalToConstant: 52),
            badgeLabel.widthAnchor.constraint(equalToConstant: 56),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func dotColor() -> NSColor {
        if !info.ready { return .systemRed }
        if info.hasAudio { return .systemGreen }
        return NSColor.systemGray
    }

    private func updateAppearance() {
        if isPlaying {
            layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.28).cgColor
        } else if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        titleLabel.textColor = info.ready ? .labelColor : .systemRed
    }
}

protocol OperatorWindowDelegate: AnyObject {
    func operatorDidPressGo()
    func operatorDidPressStop()
    func operatorDidPressCloseApplication()
    func operatorDidSelect(index: Int)
    func operatorDidChangeDevice(index: Int)
    func operatorDidChangeDisplay(index: Int)
    func operatorDidChangeBackingPair(index: Int)
    func operatorDidChangeClickPair(index: Int)
    func operatorDidSetMasterBacking(db: Double)
    func operatorDidSetMasterClick(db: Double)
    func operatorDidSetPieceBacking(db: Double)
    func operatorDidSetPieceClick(db: Double)
    func operatorDidSeek(toFraction fraction: Double)
}

/// The operator's control window: running order, GO/STOP, device + display pickers, elapsed time.
final class OperatorWindowController {
    let window: NSWindow
    weak var delegate: OperatorWindowDelegate?

    private let titleLabel = NSTextField(labelWithString: "ShowRunner")
    private let closeApplicationButton = NSButton(title: "CLOSE APPLICATION", target: nil, action: nil)
    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let backingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let clickPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusLabel = NSTextField(labelWithString: "")
    private let listStack = NSStackView()
    private let scrollView = NSScrollView()
    private let goButton = NSButton(title: "GO  (Space)", target: nil, action: nil)
    private let stopButton = NSButton(title: "STOP / PANIC  (Esc)", target: nil, action: nil)
    private let onDeckLabel = NSTextField(labelWithString: "—")
    private let nowPlayingLabel = NSTextField(labelWithString: "—")
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "")
    private let scrubSlider = ScrubSlider()
    private let backingMeter = MeterView(caption: "BACKING")
    private let clickMeter = MeterView(caption: "CLICK")
    private let backingFader = NSSlider()
    private let clickFader = NSSlider()
    private let backingDbLabel = NSTextField(labelWithString: "0.0 dB")
    private let clickDbLabel = NSTextField(labelWithString: "0.0 dB")
    private let pieceBackingFader = NSSlider()
    private let pieceClickFader = NSSlider()
    private let pieceBackingDbLabel = NSTextField(labelWithString: "0.0 dB")
    private let pieceClickDbLabel = NSTextField(labelWithString: "0.0 dB")
    private let trimCaptionLabel = NSTextField(labelWithString: "Per-piece trim")
    private let remoteLabel = NSTextField(labelWithString: "")

    private var rowViews: [PieceRowView] = []

    init(headerTitle: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 1040),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "ShowRunner"
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 700, height: 720)
        window.isReleasedWhenClosed = false
        // Appear on whatever Space is active (incl. over a full-screen app) instead of
        // opening on a hidden desktop the operator can't see.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()

        titleLabel.stringValue = headerTitle
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)

        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        remoteLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        remoteLabel.textColor = .systemTeal
        remoteLabel.lineBreakMode = .byTruncatingMiddle
        remoteLabel.isSelectable = true

        devicePopup.target = self
        devicePopup.action = #selector(deviceChanged)
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)
        backingPopup.target = self
        backingPopup.action = #selector(backingPairChanged)
        clickPopup.target = self
        clickPopup.action = #selector(clickPairChanged)

        onDeckLabel.font = .systemFont(ofSize: 21, weight: .bold)
        onDeckLabel.lineBreakMode = .byTruncatingTail
        nowPlayingLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nowPlayingLabel.lineBreakMode = .byTruncatingTail
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        elapsedLabel.stringValue = "––:–– / ––:––"
        remainingLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        remainingLabel.textColor = .secondaryLabelColor
        remainingLabel.stringValue = "−––:––"
        scrubSlider.sliderType = .linear
        scrubSlider.minValue = 0
        scrubSlider.maxValue = 1
        scrubSlider.doubleValue = 0
        scrubSlider.isContinuous = false
        scrubSlider.target = self
        scrubSlider.action = #selector(scrubChanged)
        scrubSlider.translatesAutoresizingMaskIntoConstraints = false

        configureFader(backingFader, #selector(masterBackingChanged))
        configureFader(clickFader, #selector(masterClickChanged))
        configureFader(pieceBackingFader, #selector(pieceBackingChanged))
        configureFader(pieceClickFader, #selector(pieceClickChanged))
        for l in [backingDbLabel, clickDbLabel, pieceBackingDbLabel, pieceClickDbLabel] {
            l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            l.alignment = .right
        }
        trimCaptionLabel.font = .systemFont(ofSize: 11, weight: .heavy)
        trimCaptionLabel.textColor = .secondaryLabelColor

        configureButton(goButton, color: .systemGreen, action: #selector(goPressed))
        configureButton(stopButton, color: .systemRed, action: #selector(stopPressed))
        configureCloseButton()

        buildLayout()
    }

    private func configureButton(_ b: NSButton, color: NSColor, action: Selector) {
        b.bezelStyle = .regularSquare
        b.font = .systemFont(ofSize: 22, weight: .bold)
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.contentTintColor = .white
        b.layer?.backgroundColor = color.cgColor
        b.layer?.cornerRadius = 10
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 72).isActive = true
    }

    private func configureCloseButton() {
        closeApplicationButton.bezelStyle = .rounded
        closeApplicationButton.font = .systemFont(ofSize: 12, weight: .bold)
        closeApplicationButton.target = self
        closeApplicationButton.action = #selector(closeApplicationPressed)
        closeApplicationButton.contentTintColor = .systemRed
        closeApplicationButton.translatesAutoresizingMaskIntoConstraints = false
        closeApplicationButton.widthAnchor.constraint(equalToConstant: 164).isActive = true
        closeApplicationButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func buildLayout() {
        let content = NSView()
        window.contentView = content

        // Header
        let titleRow = NSStackView(views: [titleLabel, NSView(), closeApplicationButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 12
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let deviceRow = labeledRow("Audio device:", devicePopup)
        let displayRow = labeledRow("Audience display:", displayPopup)
        let pickerRow = NSStackView(views: [deviceRow, displayRow])
        pickerRow.orientation = .horizontal
        pickerRow.spacing = 24
        pickerRow.alignment = .firstBaseline

        let backingRow = labeledRow("Backing → outputs:", backingPopup)
        let clickRow = labeledRow("Click → outputs:", clickPopup)
        let routeRow = NSStackView(views: [backingRow, clickRow])
        routeRow.orientation = .horizontal
        routeRow.spacing = 24
        routeRow.alignment = .firstBaseline

        let header = NSStackView(views: [titleRow, pickerRow, routeRow, statusLabel, remoteLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        // List
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 6
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

        scrollView.documentView = listStack
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        if let clip = scrollView.contentView as NSClipView? {
            NSLayoutConstraint.activate([
                listStack.topAnchor.constraint(equalTo: clip.topAnchor),
                listStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                listStack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                listStack.widthAnchor.constraint(equalTo: clip.widthAnchor),
            ])
        }

        // Footer
        let transport = NSStackView(views: [goButton, stopButton])
        transport.orientation = .horizontal
        transport.distribution = .fillEqually
        transport.spacing = 16

        // "On deck" banner — exactly what the next GO will fire.
        let onDeckCaption = NSTextField(labelWithString: "ON DECK →")
        onDeckCaption.font = .systemFont(ofSize: 12, weight: .heavy)
        onDeckCaption.textColor = .controlAccentColor
        onDeckCaption.setContentHuggingPriority(.required, for: .horizontal)
        let onDeckRow = NSStackView(views: [onDeckCaption, onDeckLabel])
        onDeckRow.orientation = .horizontal
        onDeckRow.spacing = 10
        onDeckRow.alignment = .firstBaseline

        // Elapsed (big) on the left, time-remaining countdown on the right.
        let timeRow = NSStackView(views: [elapsedLabel, NSView(), remainingLabel])
        timeRow.orientation = .horizontal
        timeRow.alignment = .lastBaseline

        // Mixer: master faders (with level meters beneath) + per-piece trim.
        backingMeter.heightAnchor.constraint(equalToConstant: 10).isActive = true
        clickMeter.heightAnchor.constraint(equalToConstant: 10).isActive = true
        func tag(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: 11, weight: .medium)
            l.textColor = .secondaryLabelColor
            return l
        }
        func section(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: 11, weight: .heavy)
            l.textColor = .secondaryLabelColor
            return l
        }
        let mixer = NSGridView()
        mixer.translatesAutoresizingMaskIntoConstraints = false
        mixer.rowSpacing = 5
        mixer.columnSpacing = 10
        mixer.addRow(with: [section("MASTER VOLUME"), NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        mixer.addRow(with: [tag("Backing"), backingFader, backingDbLabel])
        mixer.addRow(with: [NSGridCell.emptyContentView, backingMeter, NSGridCell.emptyContentView])
        mixer.addRow(with: [tag("Click"), clickFader, clickDbLabel])
        mixer.addRow(with: [NSGridCell.emptyContentView, clickMeter, NSGridCell.emptyContentView])
        mixer.addRow(with: [trimCaptionLabel, NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        mixer.addRow(with: [tag("Backing"), pieceBackingFader, pieceBackingDbLabel])
        mixer.addRow(with: [tag("Click"), pieceClickFader, pieceClickDbLabel])
        mixer.column(at: 0).xPlacement = .leading
        mixer.column(at: 0).width = 64
        mixer.column(at: 1).xPlacement = .fill
        mixer.column(at: 2).xPlacement = .trailing
        for f in [backingFader, clickFader, pieceBackingFader, pieceClickFader] {
            f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        for d in [backingDbLabel, clickDbLabel, pieceBackingDbLabel, pieceClickDbLabel] {
            d.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        }

        let footer = NSStackView(views: [onDeckRow, nowPlayingLabel, timeRow, scrubSlider, mixer, transport])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(header)
        content.addSubview(scrollView)
        content.addSubview(footer)

        let m: CGFloat = 20
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            titleRow.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleRow.trailingAnchor.constraint(equalTo: header.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 14),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            transport.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            onDeckRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            onDeckRow.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            timeRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            timeRow.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            scrubSlider.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            scrubSlider.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            mixer.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            mixer.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
        ])
    }

    private func configureFader(_ slider: NSSlider, _ action: Selector) {
        slider.sliderType = .linear
        slider.minValue = -40
        slider.maxValue = 6
        slider.doubleValue = 0
        slider.isContinuous = true
        slider.target = self
        slider.action = action
        slider.translatesAutoresizingMaskIntoConstraints = false
    }

    static func fmtDb(_ db: Double) -> String {
        if db <= -40 { return "−∞" }
        return String(format: "%+.1f dB", db)
    }

    private func labeledRow(_ text: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .firstBaseline
        return row
    }

    // MARK: Population

    func setPieces(_ infos: [PieceRowInfo]) {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        for (i, info) in infos.enumerated() {
            let row = PieceRowView(info: info)
            let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked(_:)))
            row.addGestureRecognizer(click)
            row.index = i
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            rowViews.append(row)
        }
    }

    func setDevices(_ names: [String], selected: Int) {
        devicePopup.removeAllItems()
        devicePopup.addItems(withTitles: names.isEmpty ? ["No audio device"] : names)
        if selected >= 0 && selected < devicePopup.numberOfItems { devicePopup.selectItem(at: selected) }
    }

    func setDisplays(_ names: [String], selected: Int) {
        displayPopup.removeAllItems()
        displayPopup.addItems(withTitles: names)
        if selected >= 0 && selected < displayPopup.numberOfItems { displayPopup.selectItem(at: selected) }
    }

    func setChannelPairs(_ labels: [String], backingSel: Int, clickSel: Int) {
        backingPopup.removeAllItems(); backingPopup.addItems(withTitles: labels.isEmpty ? ["—"] : labels)
        clickPopup.removeAllItems(); clickPopup.addItems(withTitles: labels.isEmpty ? ["—"] : labels)
        if backingSel >= 0 && backingSel < backingPopup.numberOfItems { backingPopup.selectItem(at: backingSel) }
        if clickSel >= 0 && clickSel < clickPopup.numberOfItems { clickPopup.selectItem(at: clickSel) }
    }

    func setMasterLevels(backingDb: Double, clickDb: Double) {
        backingFader.doubleValue = backingDb
        clickFader.doubleValue = clickDb
        backingDbLabel.stringValue = Self.fmtDb(backingDb)
        clickDbLabel.stringValue = Self.fmtDb(clickDb)
    }

    func setPieceTrim(enabled: Bool, caption: String, backingDb: Double, clickDb: Double) {
        trimCaptionLabel.stringValue = caption
        pieceBackingFader.isEnabled = enabled
        pieceClickFader.isEnabled = enabled
        pieceBackingFader.doubleValue = backingDb
        pieceClickFader.doubleValue = clickDb
        pieceBackingDbLabel.stringValue = enabled ? Self.fmtDb(backingDb) : "—"
        pieceClickDbLabel.stringValue = enabled ? Self.fmtDb(clickDb) : "—"
    }

    func setStatus(_ text: String) { statusLabel.stringValue = text }
    func setRemoteInfo(_ text: String) { remoteLabel.stringValue = text }

    // Read-backs so the phone remote mirrors EXACTLY what the operator window shows.
    var onDeckText: String { onDeckLabel.stringValue }
    var nowPlayingText: String { nowPlayingLabel.stringValue }
    var elapsedText: String { elapsedLabel.stringValue }
    var remainingText: String { remainingLabel.stringValue }
    var progressValue: Double { scrubSlider.doubleValue }

    func setSelected(_ index: Int) {
        for (i, row) in rowViews.enumerated() { row.isSelected = (i == index) }
        if index >= 0 && index < rowViews.count {
            let row = rowViews[index]
            DispatchQueue.main.async { row.scrollToVisible(row.bounds) }
        }
    }

    func setPlaying(index: Int?) {
        for (i, row) in rowViews.enumerated() { row.isPlaying = (i == index) }
    }

    func setNowPlaying(_ text: String) { nowPlayingLabel.stringValue = text }
    func setElapsed(_ text: String) { elapsedLabel.stringValue = text }
    func setOnDeck(_ text: String) { onDeckLabel.stringValue = text }
    func setRemaining(_ text: String) { remainingLabel.stringValue = text }
    func setProgress(_ fraction: Double) {
        guard !scrubSlider.isUserScrubbing else { return }
        scrubSlider.doubleValue = max(0, min(1, fraction))
    }
    func setScrubEnabled(_ enabled: Bool) {
        scrubSlider.isEnabled = enabled
        scrubSlider.alphaValue = enabled ? 1.0 : 0.45
    }
    func setMeters(backing: Float, click: Float) {
        backingMeter.setLevel(backing)
        clickMeter.setLevel(click)
    }

    // MARK: Actions

    @objc private func goPressed() { delegate?.operatorDidPressGo() }
    @objc private func stopPressed() { delegate?.operatorDidPressStop() }
    @objc private func closeApplicationPressed() { delegate?.operatorDidPressCloseApplication() }
    @objc private func rowClicked(_ g: NSClickGestureRecognizer) {
        if let v = g.view as? PieceRowView { delegate?.operatorDidSelect(index: v.index) }
    }
    @objc private func deviceChanged() { delegate?.operatorDidChangeDevice(index: devicePopup.indexOfSelectedItem) }
    @objc private func displayChanged() { delegate?.operatorDidChangeDisplay(index: displayPopup.indexOfSelectedItem) }
    @objc private func backingPairChanged() { delegate?.operatorDidChangeBackingPair(index: backingPopup.indexOfSelectedItem) }
    @objc private func clickPairChanged() { delegate?.operatorDidChangeClickPair(index: clickPopup.indexOfSelectedItem) }
    @objc private func scrubChanged() { delegate?.operatorDidSeek(toFraction: scrubSlider.doubleValue) }
    @objc private func masterBackingChanged() {
        backingDbLabel.stringValue = Self.fmtDb(backingFader.doubleValue)
        delegate?.operatorDidSetMasterBacking(db: backingFader.doubleValue)
    }
    @objc private func masterClickChanged() {
        clickDbLabel.stringValue = Self.fmtDb(clickFader.doubleValue)
        delegate?.operatorDidSetMasterClick(db: clickFader.doubleValue)
    }
    @objc private func pieceBackingChanged() {
        pieceBackingDbLabel.stringValue = Self.fmtDb(pieceBackingFader.doubleValue)
        delegate?.operatorDidSetPieceBacking(db: pieceBackingFader.doubleValue)
    }
    @objc private func pieceClickChanged() {
        pieceClickDbLabel.stringValue = Self.fmtDb(pieceClickFader.doubleValue)
        delegate?.operatorDidSetPieceClick(db: pieceClickFader.doubleValue)
    }
}
