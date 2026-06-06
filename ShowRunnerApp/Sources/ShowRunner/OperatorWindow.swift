import AppKit

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
    func operatorDidSelect(index: Int)
    func operatorDidChangeDevice(index: Int)
    func operatorDidChangeDisplay(index: Int)
}

/// The operator's control window: running order, GO/STOP, device + display pickers, elapsed time.
final class OperatorWindowController {
    let window: NSWindow
    weak var delegate: OperatorWindowDelegate?

    private let titleLabel = NSTextField(labelWithString: "ShowRunner")
    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusLabel = NSTextField(labelWithString: "")
    private let listStack = NSStackView()
    private let scrollView = NSScrollView()
    private let goButton = NSButton(title: "GO  (Space)", target: nil, action: nil)
    private let stopButton = NSButton(title: "STOP / PANIC  (Esc)", target: nil, action: nil)
    private let nowPlayingLabel = NSTextField(labelWithString: "—")
    private let elapsedLabel = NSTextField(labelWithString: "")

    private var rowViews: [PieceRowView] = []

    init(headerTitle: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 940),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "ShowRunner"
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 680, height: 600)
        window.center()

        titleLabel.stringValue = headerTitle
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)

        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        devicePopup.target = self
        devicePopup.action = #selector(deviceChanged)
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)

        nowPlayingLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        elapsedLabel.stringValue = "––:–– / ––:––"

        configureButton(goButton, color: .systemGreen, action: #selector(goPressed))
        configureButton(stopButton, color: .systemRed, action: #selector(stopPressed))

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

    private func buildLayout() {
        let content = NSView()
        window.contentView = content

        // Header
        let deviceRow = labeledRow("Audio device:", devicePopup)
        let displayRow = labeledRow("Audience display:", displayPopup)
        let pickerRow = NSStackView(views: [deviceRow, displayRow])
        pickerRow.orientation = .horizontal
        pickerRow.spacing = 24
        pickerRow.alignment = .firstBaseline

        let header = NSStackView(views: [titleLabel, pickerRow, statusLabel])
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

        let playInfo = NSStackView(views: [nowPlayingLabel, elapsedLabel])
        playInfo.orientation = .horizontal
        playInfo.distribution = .equalSpacing
        playInfo.alignment = .centerY

        let footer = NSStackView(views: [playInfo, transport])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(header)
        content.addSubview(scrollView)
        content.addSubview(footer)

        let m: CGFloat = 20
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 14),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            transport.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            playInfo.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            playInfo.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
        ])
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

    func setStatus(_ text: String) { statusLabel.stringValue = text }

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

    // MARK: Actions

    @objc private func goPressed() { delegate?.operatorDidPressGo() }
    @objc private func stopPressed() { delegate?.operatorDidPressStop() }
    @objc private func rowClicked(_ g: NSClickGestureRecognizer) {
        if let v = g.view as? PieceRowView { delegate?.operatorDidSelect(index: v.index) }
    }
    @objc private func deviceChanged() { delegate?.operatorDidChangeDevice(index: devicePopup.indexOfSelectedItem) }
    @objc private func displayChanged() { delegate?.operatorDidChangeDisplay(index: displayPopup.indexOfSelectedItem) }
}
