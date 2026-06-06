import AppKit

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

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    ShowRunner — live concert playback
      ShowRunner [path-to-showrunner.json | show-folder]
      ShowRunner --config <path>
      ShowRunner --selftest        Run the headless self-test and exit
      ShowRunner --help            Show this help

    Keys:  Space/Enter = GO    ↑/↓ = move selection    Esc = STOP / PANIC
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
