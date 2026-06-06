import Foundation

/// One piece of the running order, decoded from showrunner.json.
struct Piece: Codable {
    let order: String
    let title: String
    let subtitle: String
    let folder: String
    let titleCard: String
    let hasAudio: Bool
    let backing: String?
    let click: String?
}

/// Top-level show configuration.
struct ShowConfig: Codable {
    var audienceDisplayIndex: Int
    var audioDeviceName: String
    var fadeSeconds: Double
    /// Fixed engine/device sample rate. All audio is resampled to this at load so the
    /// device never relocks mid-show. Defaults to 48000 if absent.
    var engineSampleRate: Double?
    var pieces: [Piece]
}

enum ConfigError: Error, CustomStringConvertible {
    case notFound([String])
    case decode(String)

    var description: String {
        switch self {
        case .notFound(let tried):
            return "showrunner.json not found. Tried:\n  " + tried.joined(separator: "\n  ")
        case .decode(let msg):
            return "Failed to parse showrunner.json: \(msg)"
        }
    }
}

enum ConfigLoader {
    /// Hard-coded safety net so the app always finds the show even if launched oddly.
    static let defaultShowRoot = "/Users/lionelyu/Music/Belgium Concert Program"

    /// Resolve the showrunner.json URL using a robust search order.
    static func locate(explicit: String?) -> (url: URL, tried: [String]) {
        let fm = FileManager.default
        var tried: [String] = []

        func resolve(_ raw: String) -> URL? {
            var path = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {
                    path = (path as NSString).appendingPathComponent("showrunner.json")
                }
                if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            }
            return nil
        }

        var candidates: [String] = []
        if let e = explicit { candidates.append(e) }
        if let env = ProcessInfo.processInfo.environment["SHOWRUNNER_CONFIG"] { candidates.append(env) }
        candidates.append(fm.currentDirectoryPath + "/showrunner.json")
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("showrunner.json").path)
        // 'swift run': exe at <pkg>/.build/release/ShowRunner — json is one level above <pkg>
        candidates.append(exeDir.appendingPathComponent("../../../../showrunner.json").path)
        // App bundle: ShowRunner.app/Contents/MacOS/ShowRunner — json sits alongside the .app
        candidates.append(exeDir.appendingPathComponent("../../../showrunner.json").path)
        candidates.append(defaultShowRoot + "/showrunner.json")

        for c in candidates {
            tried.append((c as NSString).expandingTildeInPath)
            if let url = resolve(c) { return (url, tried) }
        }
        // Return the default path even if missing, so the error lists it.
        return (URL(fileURLWithPath: defaultShowRoot + "/showrunner.json"), tried)
    }

    /// Load config and return it alongside the resolved show-root directory.
    static func load(explicit: String?) throws -> (config: ShowConfig, root: URL) {
        let (url, tried) = locate(explicit: explicit)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.notFound(tried)
        }
        do {
            let data = try Data(contentsOf: url)
            let cfg = try JSONDecoder().decode(ShowConfig.self, from: data)
            return (cfg, url.deletingLastPathComponent())
        } catch let e as DecodingError {
            throw ConfigError.decode(String(describing: e))
        } catch {
            throw ConfigError.decode(error.localizedDescription)
        }
    }
}
