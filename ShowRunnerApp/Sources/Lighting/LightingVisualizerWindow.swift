import AppKit

/// An ABSTRACT stage preview — a "what the hall roughly looks like" visualizer so colour and scale
/// can be checked at home before the rig exists. It is NOT photoreal and not a renderer of the
/// real beam optics: it reads the same per-fixture look the engine computes each frame and paints
/// a front-of-house cartoon — a cyclorama wash (Dalis), front-light pools (Fargos), and aerial
/// mover beams (Spiiders) — with each fixture's live colour, intensity and zoom/spread.
///
/// It is purely a reader: it polls a lock-protected snapshot on the main thread and draws. It never
/// touches the renderer state or the audio path. Fixtures that are not actually emitting live
/// (blackout, or a provisional mover that hasn't been armed) are shown with their INTENDED colour
/// (so the design can be judged) but marked with a dashed ring + a caption note.
public final class LightingVisualizerWindowController {
    public let window: NSWindow
    private let stage = StageView()
    private let caption = NSTextField(labelWithString: "")
    private let snapshot: () -> [FixtureVisual]
    private let statusFn: () -> LightingStatus
    private var timer: Timer?

    public init(snapshot: @escaping () -> [FixtureVisual], status: @escaping () -> LightingStatus) {
        self.snapshot = snapshot
        self.statusFn = status

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Lighting — Stage Preview (abstract)"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 560, height: 360)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = content

        stage.translatesAutoresizingMaskIntoConstraints = false
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        content.addSubview(stage)
        content.addSubview(caption)
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: content.topAnchor),
            stage.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -4),
            caption.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            caption.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            caption.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    public func show() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: f.minX + 24, y: f.maxY - 24 - 660))
        }
        window.orderFrontRegardless()   // visible without stealing key focus from the operator
        startRefresh()
    }

    public func close() {
        timer?.invalidate(); timer = nil
        window.close()
    }

    private func startRefresh() {
        timer?.invalidate()
        // ~30 fps preview; the engine publishes at 40 fps.
        let t = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func refresh() {
        guard window.isVisible else { return }
        let s = statusFn()
        stage.update(snapshot(), s)
        var parts: [String] = ["Piece \(s.pieceOrder ?? "—")", s.mode]
        if s.mode == "timecode" { parts.append(String(format: "%.1fs", s.position)) }
        if s.mode == "cue", let c = s.cueLabel { parts.append("“\(c)”") }
        if s.blackout { parts.append("BLACKOUT") }
        if s.hold { parts.append("HELD") }
        if s.hasProvisional { parts.append(s.armProvisional ? "movers ARMED" : "movers preview (disarmed)") }
        caption.stringValue = parts.joined(separator: "   ·   ") + "   —   abstract preview, not photoreal"
    }
}

// MARK: - Stage view

final class StageView: NSView {
    private var visuals: [FixtureVisual] = []
    private var status = LightingStatus()
    // Cache label attributes once — building fresh font attributes every redraw can throw.
    private let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.55),
    ]

    override var isFlipped: Bool { false }
    override var wantsDefaultClipping: Bool { true }

    func update(_ v: [FixtureVisual], _ s: LightingStatus) {
        visuals = v; status = s
        needsDisplay = true
    }

    /// Extract a display colour + brightness (0…1) from a fixture state. RGBW → RGB (white lifts
    /// all channels); brightness is the master intensity.
    private func display(_ s: FixtureState) -> (NSColor, CGFloat) {
        let w = s.white
        let r = min(1.0, s.red + w), g = min(1.0, s.green + w), b = min(1.0, s.blue + w)
        return (NSColor(srgbRed: r, green: g, blue: b, alpha: 1), CGFloat(max(0, min(1, s.intensity))))
    }

    override func draw(_ dirtyRect: NSRect) {
        let W = bounds.width, H = bounds.height
        guard W > 10, H > 10 else { return }
        NSColor.black.setFill(); bounds.fill()

        let fargos   = visuals.filter { $0.kind == "fargo_9ch" }.sorted { $0.address < $1.address }
        let spiiders = visuals.filter { $0.kind == "spiider_mode2" }.sorted { $0.address < $1.address }
        let dalis    = visuals.filter { $0.kind == "dalis_stub" }

        drawCyc(W: W, H: H, dalis: dalis)
        drawFloor(W: W, H: H)
        for (i, s) in spiiders.enumerated() { drawSpiiderBeam(s, index: i, count: spiiders.count, W: W, H: H) }
        for (i, f) in fargos.enumerated()   { drawFargoPool(f, index: i, count: fargos.count, W: W, H: H) }

        drawFixtureMarkers(fargos: fargos, spiiders: spiiders, dalis: dalis, W: W, H: H)
    }

    // The upstage cyclorama, washed by the Dalis fixtures (their intended colours blended).
    private func drawCyc(W: CGFloat, H: CGFloat, dalis: [FixtureVisual]) {
        let rect = NSRect(x: 0.06 * W, y: 0.42 * H, width: 0.88 * W, height: 0.50 * H)
        // base unlit cyc
        NSColor(white: 0.06, alpha: 1).setFill(); NSBezierPath(rect: rect).fill()

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, wsum: CGFloat = 0
        for d in dalis {
            let (c, br) = display(d.state)
            r += c.redComponent * br; g += c.greenComponent * br; b += c.blueComponent * br; wsum += br
        }
        guard wsum > 0.001 else { return }
        let level = min(1.0, wsum / CGFloat(max(1, dalis.count)))
        let col = NSColor(srgbRed: r / wsum, green: g / wsum, blue: b / wsum, alpha: 1)
        // vertical gradient: brighter toward the bottom (where the Dalis battens sit)
        let grad = NSGradient(colors: [col.withAlphaComponent(level * 0.35), col.withAlphaComponent(level)])
        grad?.draw(in: NSBezierPath(rect: rect), angle: 90)
    }

    private func drawFloor(W: CGFloat, H: CGFloat) {
        let floor = NSRect(x: 0.04 * W, y: 0.08 * H, width: 0.92 * W, height: 0.09 * H)
        NSColor(white: 0.10, alpha: 1).setFill(); NSBezierPath(roundedRect: floor, xRadius: 4, yRadius: 4).fill()
    }

    // Fargo front-light pool: a soft elliptical glow on the stage. Size grows with zoom (beam width).
    private func drawFargoPool(_ f: FixtureVisual, index: Int, count: Int, W: CGFloat, H: CGFloat) {
        let (col, bright) = display(f.state)
        let cx = W * (0.16 + 0.68 * (count <= 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)))
        let cy = H * 0.30
        let rx = W * (0.05 + 0.11 * CGFloat(f.state.zoom))
        let ry = rx * 0.52
        let rect = NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
        let a = bright * (f.emitting ? 1.0 : 0.8)
        if a > 0.01 {
            let grad = NSGradient(colors: [col.withAlphaComponent(a), col.withAlphaComponent(0)])
            grad?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: 0, y: 0))
        }
    }

    // Spiider aerial beam: a translucent cone from the mover (top) toward a target set by pan/tilt.
    private func drawSpiiderBeam(_ s: FixtureVisual, index: Int, count: Int, W: CGFloat, H: CGFloat) {
        let (col, bright) = display(s.state)
        let mountX = W * (count <= 1 ? 0.5 : 0.16 + 0.68 * CGFloat(index) / CGFloat(count - 1))
        let mount = NSPoint(x: mountX, y: H * 0.92)
        // pan → horizontal aim across the stage; tilt → vertical aim (high = toward cyc).
        let tx = W * (0.12 + 0.76 * CGFloat(s.state.pan))
        let ty = H * (0.20 + 0.50 * CGFloat(s.state.tilt))
        let halfW = W * (0.02 + 0.10 * CGFloat(s.state.zoom))
        // perpendicular spread at the target
        let dx = tx - mount.x, dy = ty - mount.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        let px = -dy / len * halfW, py = dx / len * halfW
        let path = NSBezierPath()
        path.move(to: mount)
        path.line(to: NSPoint(x: tx + px, y: ty + py))
        path.line(to: NSPoint(x: tx - px, y: ty - py))
        path.close()
        let a = bright * (s.emitting ? 0.55 : 0.40)
        if a > 0.01 {
            col.withAlphaComponent(a).setFill(); path.fill()
            // bright core line
            let core = NSBezierPath(); core.move(to: mount); core.line(to: NSPoint(x: tx, y: ty))
            core.lineWidth = 2
            col.withAlphaComponent(min(1, a + 0.25)).setStroke(); core.stroke()
            // pool where the beam lands
            let pr = halfW
            let prect = NSRect(x: tx - pr, y: ty - pr * 0.5, width: pr * 2, height: pr)
            let grad = NSGradient(colors: [col.withAlphaComponent(a), col.withAlphaComponent(0)])
            grad?.draw(in: NSBezierPath(ovalIn: prect), relativeCenterPosition: .zero)
        }
    }

    private func drawFixtureMarkers(fargos: [FixtureVisual], spiiders: [FixtureVisual], dalis: [FixtureVisual], W: CGFloat, H: CGFloat) {
        func marker(at p: NSPoint, _ v: FixtureVisual, label: String) {
            let (col, bright) = display(v.state)
            let r: CGFloat = 5
            let dot = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            (bright > 0.02 ? col.withAlphaComponent(0.5 + 0.5 * bright) : NSColor(white: 0.3, alpha: 1)).setFill()
            dot.fill()
            if !v.emitting {   // provisional & disarmed (or blacked out): dashed "preview / not live" ring
                let ring = NSBezierPath(ovalIn: NSRect(x: p.x - r - 3, y: p.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2))
                ring.lineWidth = 1
                ring.setLineDash([2, 2], count: 2, phase: 0)
                NSColor.systemOrange.withAlphaComponent(0.8).setStroke()
                ring.stroke()
            }
            (label as NSString).draw(at: NSPoint(x: p.x - r, y: p.y - r - 12), withAttributes: labelAttrs)
        }
        for (i, f) in fargos.enumerated() {
            let cx = W * (0.16 + 0.68 * (fargos.count <= 1 ? 0.5 : CGFloat(i) / CGFloat(fargos.count - 1)))
            marker(at: NSPoint(x: cx, y: H * 0.40), f, label: f.name)
        }
        for (i, s) in spiiders.enumerated() {
            let mx = W * (spiiders.count <= 1 ? 0.5 : 0.16 + 0.68 * CGFloat(i) / CGFloat(spiiders.count - 1))
            marker(at: NSPoint(x: mx, y: H * 0.92), s, label: s.name)
        }
        for (i, d) in dalis.enumerated() {
            let cx = W * (0.18 + 0.64 * (dalis.count <= 1 ? 0.5 : CGFloat(i) / CGFloat(dalis.count - 1)))
            marker(at: NSPoint(x: cx, y: H * 0.44), d, label: d.name)
        }
    }
}
