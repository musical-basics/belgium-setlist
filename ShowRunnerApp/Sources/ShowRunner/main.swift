import AppKit
import Lighting

// MARK: - Argument parsing

func parseConfigArg(_ args: [String]) -> String? {
    var i = 1
    while i < args.count {
        let a = args[i]
        if a == "--config", i + 1 < args.count { return args[i + 1] }
        if a.hasPrefix("--config=") { return String(a.dropFirst("--config=".count)) }
        if !a.hasPrefix("-") { return a }   // bare path to json or show folder
        i += 1
    }
    return nil
}

let arguments = CommandLine.arguments
let configArg = parseConfigArg(arguments)

if arguments.contains("--selftest") {
    let code = SelfTest.run(configPath: configArg)
    exit(code)
}

// Lighting module's own headless validation (sACN packet layout, config, profiles). Separate
// from the audio --selftest so the sound app's test is unchanged.
if arguments.contains("--lighting-selftest") {
    let root: URL
    if let loaded = try? ConfigLoader.load(explicit: configArg) { root = loaded.root }
    else { root = URL(fileURLWithPath: ConfigLoader.defaultShowRoot) }
    let result = LightingSelfTest.run(showRoot: root)
    print(result.lines.joined(separator: "\n"))
    exit(result.failures == 0 ? 0 : 1)
}

// Headless render of the abstract stage preview to a PNG:
//   ShowRunner --lighting-preview <out.png> [pieceOrder=4] [seconds=42]
if let i = arguments.firstIndex(of: "--lighting-preview") {
    let out = (i + 1 < arguments.count) ? arguments[i + 1] : "lighting-preview.png"
    let piece = (i + 2 < arguments.count) ? arguments[i + 2] : "4"
    let seconds = (i + 3 < arguments.count) ? (Double(arguments[i + 3]) ?? 42) : 42
    let root: URL = (try? ConfigLoader.load(explicit: configArg))?.root ?? URL(fileURLWithPath: ConfigLoader.defaultShowRoot)
    if let data = LightingPreview.renderPNG(showRoot: root, pieceOrder: piece, seconds: seconds) {
        do { try data.write(to: URL(fileURLWithPath: out)); print("Wrote preview \(out) (piece \(piece) @ \(seconds)s)"); exit(0) }
        catch { print("Failed to write \(out): \(error)"); exit(1) }
    }
    print("Failed to render preview."); exit(1)
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    ShowRunner — live concert playback
      ShowRunner [path-to-showrunner.json | show-folder]
      ShowRunner --config <path>
      ShowRunner --selftest          Run the headless audio self-test and exit
      ShowRunner --lighting-selftest Validate the lighting module (sACN/config) and exit
      ShowRunner --help              Show this help

    Keys:  Space/Enter = GO    ↑/↓ = move selection    Esc = STOP / PANIC
           Cmd-Q = quit    ⌃⌥⌘Q = PANIC QUIT (works even when the app isn't focused)
    Phone remote:  open the http://<mac-ip>:8088 URL shown in the operator window
    (see PHONE_REMOTE.md for the venue network plan)
    """)
    exit(0)
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        controller.bootstrap()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.teardown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ShowRunner", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ShowRunner", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit ShowRunner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}

// MARK: - Launch

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = AppController(configPath: configArg)
let delegate = AppDelegate(controller: controller)
app.delegate = delegate
app.run()
