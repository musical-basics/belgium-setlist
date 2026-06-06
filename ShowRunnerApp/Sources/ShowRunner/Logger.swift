import Foundation

/// Simple thread-safe file logger. Writes to ~/Library/Logs/ShowRunner/showrunner.log
/// and mirrors to stderr. NEVER call this from the real-time audio render callback.
final class Logger {
    static let shared = Logger()

    private let queue = DispatchQueue(label: "com.lionelyu.showrunner.logger")
    private var handle: FileHandle?
    private let df: DateFormatter
    let logURL: URL

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ShowRunner", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logURL = logsDir.appendingPathComponent("showrunner.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: logURL)
        handle?.seekToEndOfFile()

        df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.locale = Locale(identifier: "en_US_POSIX")
    }

    private func write(_ message: String, _ level: String) {
        let line = "[\(df.string(from: Date()))] [\(level)] \(message)\n"
        let data = Data(line.utf8)
        queue.async { [weak self] in
            FileHandle.standardError.write(data)
            self?.handle?.write(data)
        }
    }

    func info(_ m: String)  { write(m, "INFO") }
    func warn(_ m: String)  { write(m, "WARN") }
    func error(_ m: String) { write(m, "ERROR") }

    /// Flush any pending log writes (used before exit in self-test).
    func flush() {
        queue.sync {}
        try? handle?.synchronize()
    }
}
