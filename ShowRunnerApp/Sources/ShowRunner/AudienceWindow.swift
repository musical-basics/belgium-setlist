import AppKit
import QuartzCore

/// A black, layer-backed view that displays a title card letterboxed (aspect-preserved)
/// with a fade in/out. The image layer sits over a black background; areas outside the
/// image's aspect-fit rectangle show the black background (letterbox bars).
final class LetterboxView: NSView {
    let imageLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.opacity = 0          // start black
        imageLayer.frame = bounds
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
}

/// Owns the audience-facing window: borderless full-screen on a chosen display, or a
/// resizable windowed preview when only one display is present (home testing).
final class AudienceWindow {
    let window: NSWindow
    private let view: LetterboxView
    private let fadeSeconds: Double

    init(fadeSeconds: Double) {
        self.fadeSeconds = fadeSeconds
        let initialFrame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        view = LetterboxView(frame: initialFrame)
        window = NSWindow(contentRect: initialFrame,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false)
        window.contentView = view
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary]
    }

    /// Place the window on a screen. `fullscreen` = borderless cover (audience display);
    /// otherwise a titled windowed preview centered on that screen.
    func place(on screen: NSScreen, fullscreen: Bool) {
        if fullscreen {
            window.styleMask = .borderless
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver           // covers menu bar / dock on that screen
            window.ignoresMouseEvents = true
            window.backgroundColor = .black
        } else {
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.title = "ShowRunner — Audience Preview"
            let w: CGFloat = 1280, h: CGFloat = 720
            let f = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - h / 2, width: w, height: h)
            window.setFrame(f, display: true)
            window.level = .floating   // stay visible above the operator window for home testing
            window.ignoresMouseEvents = false
        }
        window.orderFrontRegardless()             // show WITHOUT stealing key focus from operator
    }

    /// Show a title card, fading opacity 0 → 1 over `fadeSeconds` (per the brief). The card
    /// is swapped in instantly while black, then faded up — a single, coordinated animation
    /// (no competing content-transition), so there is no flicker.
    func showCard(_ image: NSImage?) {
        let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.imageLayer.frame = view.bounds   // keep frame current (covers any pending resize)
        view.imageLayer.opacity = 0           // start from black, no animation
        view.imageLayer.contents = cg
        CATransaction.commit()
        setOpacity(cg == nil ? 0 : 1)
    }

    /// Fade the current card out to black.
    func clear() {
        setOpacity(0)
    }

    private func setOpacity(_ target: Float) {
        let layer = view.imageLayer
        let from = layer.presentation()?.opacity ?? layer.opacity
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = target
        anim.duration = fadeSeconds
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.isRemovedOnCompletion = true
        layer.add(anim, forKey: "fade")
        layer.opacity = target
    }
}
