import Foundation

/// Structured stderr logger. MCP servers must not write to stdout (reserved for JSON-RPC).
enum Log {
    enum Level: String, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    /// Minimum level to emit. Controlled by LOG_LEVEL env var.
    static let minLevel: Level = {
        switch ProcessInfo.processInfo.environment["LOG_LEVEL"]?.lowercased() {
        case "debug": return .debug
        case "warn": return .warn
        case "error": return .error
        default: return .info
        }
    }()

    private nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func shouldLog(_ level: Level) -> Bool {
        let order: [Level] = [.debug, .info, .warn, .error]
        guard let minIdx = order.firstIndex(of: minLevel),
              let lvlIdx = order.firstIndex(of: level) else { return false }
        return lvlIdx >= minIdx
    }

    static func log(_ level: Level, _ message: String, subsystem: String = "main", file: String = #file, line: Int = #line) {
        guard shouldLog(level) else { return }
        let timestamp = dateFormatter.string(from: Date())
        let filename = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(level.rawValue)] [\(subsystem)] \(message) (\(filename):\(line))\n"
        FileHandle.standardError.write(Data(entry.utf8))
    }

    static func debug(_ msg: String, subsystem: String = "main", file: String = #file, line: Int = #line) {
        log(.debug, msg, subsystem: subsystem, file: file, line: line)
    }

    static func info(_ msg: String, subsystem: String = "main", file: String = #file, line: Int = #line) {
        log(.info, msg, subsystem: subsystem, file: file, line: line)
    }

    static func warn(_ msg: String, subsystem: String = "main", file: String = #file, line: Int = #line) {
        log(.warn, msg, subsystem: subsystem, file: file, line: line)
    }

    static func error(_ msg: String, subsystem: String = "main", file: String = #file, line: Int = #line) {
        log(.error, msg, subsystem: subsystem, file: file, line: line)
    }
}
