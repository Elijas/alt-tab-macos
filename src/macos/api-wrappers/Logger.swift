import Foundation

enum LogLevel: Int, Comparable {
    case debug = 0
    case info
    case warning
    case error

    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var word: String {
        switch self {
            case .debug: return "DEBG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERRO"
        }
    }

    /// xterm-256 color codes that match SwiftyBeaver's defaults (useTerminalColors = true).
    var ansiColorStart: String {
        switch self {
            case .debug: return "\u{001B}[38;5;35m"
            case .info: return "\u{001B}[38;5;38m"
            case .warning: return "\u{001B}[38;5;178m"
            case .error: return "\u{001B}[38;5;197m"
        }
    }
}

class Logger {
    static let flag = "--logs="
    static let longDateTimeFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    static var minLevel: LogLevel = .error
    private static var tap: ((LogLevel, String) -> Void)?
    private static let ansiReset = "\u{001B}[0m"
    private static let writeQueue = DispatchQueue(label: "Logger.writeQueue", qos: .utility)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func initialize() {
        minLevel = decideLevel()
        PerfDebug.initialize()
    }

    static func decideLevel() -> LogLevel {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix(flag) }) else { return .error }
        switch String(arg.dropFirst(flag.count)) {
            case "debug", "verbose": return .debug
            case "info": return .info
            case "warning": return .warning
            case "error": return .error
            default: return .error
        }
    }

    static func setTap(_ tap: ((LogLevel, String) -> Void)?) { self.tap = tap }

    static func debug(_ message: @escaping () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.debug, message, file, function, line)
    }

    static func info(_ message: @escaping () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.info, message, file, function, line)
    }

    static func warning(_ message: @escaping () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.warning, message, file, function, line)
    }

    static func error(_ message: @escaping () -> Any?, file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.error, message, file, function, line)
    }

    @inline(__always)
    private static func emit(_ level: LogLevel, _ message: () -> Any?, _ file: String, _ function: String, _ line: Int) {
        // Compile-cheap gate: skip the closure call entirely when this level is suppressed.
        guard level >= minLevel else { return }
        let rendered = "\(message() ?? "nil")"
        let now = Date()
        let thread = threadName()
        // Move formatting + IO off the calling thread (typically main on the hot path).
        writeQueue.async {
            let fileName = (file as NSString).lastPathComponent
            // SwiftyBeaver console.format was: "$C$D{HH:mm:ss.SSS}$d $L$c $N.swift:$l $F $M"
            // with $M wrapped as "[\(threadName())] \(message())".
            let timestamp = dateFormatter.string(from: now)
            let head = "\(timestamp) \(level.word)"
            let body = "\(fileName):\(line) \(cleanFunctionName(function)) [\(thread)] \(rendered)"
            // Always emit ANSI colors — matches SwiftyBeaver's useTerminalColors=true behavior.
            // Modern terminals (Terminal.app, iTerm2, VS Code, etc.) all render them; logs piped
            // to files keep the codes harmlessly inline.
            print("\(level.ansiColorStart)\(head)\(ansiReset) \(body)")
            if let tap {
                // DebugWindow already does its own per-level coloring; pass the uncolored line.
                tap(level, "\(head) \(body)")
            }
        }
    }

    /// Swift's #function returns the full signature, including "_:" placeholders for unnamed
    /// parameters (e.g. "init(_:_:_:_:)"). Strip those — the log already has file:line, the
    /// arity is noise. Functions with labeled arguments keep their labels.
    private static func cleanFunctionName(_ s: String) -> String {
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")"), open < close else { return s }
        let args = s[s.index(after: open)..<close]
        if args.isEmpty || args.allSatisfy({ $0 == "_" || $0 == ":" }) {
            return "\(s[..<open])()"
        }
        return s
    }

    private static func threadName() -> String {
        if Thread.isMainThread { return "main" }
        if let name = Thread.current.name, !name.isEmpty { return name }
        let label = __dispatch_queue_get_label(nil)
        return String(cString: label, encoding: .utf8) ?? Thread.current.description
    }
}

class PerfDebug {
    struct Span {
        fileprivate let operation: String
        fileprivate let fields: [String: Any]
        fileprivate let startNs: UInt64

        func finish(_ fields: [String: Any] = [:]) {
            PerfDebug.finish(operation, self.fields, fields, startNs)
        }
    }

    private struct Stats {
        var count = 0
        var totalMs = 0.0
        var maxMs = 0.0
        var changed = 0
        var errors = 0
    }

    private static let flag = "--perfdebug"
    private static let writeQueue = DispatchQueue(label: "perfdebug")
    private static var fileHandle: FileHandle?
    private static var summaryTimer: DispatchSourceTimer?
    private static var stats = [String: Stats]()
    private static var cachedEnabled: Bool?

    static var enabled: Bool {
        if let cachedEnabled { return cachedEnabled }
        let enabled = CommandLine.arguments.contains(flag) || UserDefaults.standard.bool(forKey: "perfdebug")
        cachedEnabled = enabled
        return enabled
    }

    static func initialize() {
        guard enabled else { return }
        writeQueue.async {
            startSummaryTimer()
            writePayload(["type": "start", "ts": timestamp(), "pid": Int(ProcessInfo.processInfo.processIdentifier), "path": logFileUrl().path], false)
        }
    }

    static func shutdown() {
        guard enabled else { return }
        writeQueue.sync {
            flushSummary()
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }

    static func start(_ operation: String, fields: [String: Any] = [:]) -> Span? {
        guard enabled else { return nil }
        return Span(operation: operation, fields: fields, startNs: DispatchTime.now().uptimeNanoseconds)
    }

    static func record(_ operation: String, fields: [String: Any] = [:]) {
        guard enabled else { return }
        var payload = basePayload(operation, fields)
        payload["duration_ms"] = 0.0
        writeQueue.async { writePayload(payload, true) }
    }

    private static func finish(_ operation: String, _ startFields: [String: Any], _ finishFields: [String: Any], _ startNs: UInt64) {
        guard enabled else { return }
        let endNs = DispatchTime.now().uptimeNanoseconds
        var fields = startFields
        finishFields.forEach { fields[$0.key] = $0.value }
        var payload = basePayload(operation, fields)
        payload["duration_ms"] = Double(endNs - startNs) / 1_000_000
        writeQueue.async { writePayload(payload, true) }
    }

    private static func basePayload(_ operation: String, _ fields: [String: Any]) -> [String: Any] {
        var payload = fields
        payload["type"] = "event"
        payload["ts"] = timestamp()
        payload["operation"] = operation
        payload["thread"] = threadName()
        return payload
    }

    private static func timestamp() -> Double {
        Date().timeIntervalSince1970
    }

    private static func threadName() -> String {
        if Thread.isMainThread { return "main" }
        if let name = Thread.current.name, !name.isEmpty { return name }
        let name = __dispatch_queue_get_label(nil)
        return String(cString: name, encoding: .utf8) ?? Thread.current.description
    }

    private static func startSummaryTimer() {
        guard summaryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: writeQueue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { flushSummary() }
        summaryTimer = timer
        timer.resume()
    }

    private static func flushSummary() {
        guard !stats.isEmpty else { return }
        let operations = stats.map { key, stat in
            [
                "operation": key,
                "count": stat.count,
                "total_ms": stat.totalMs,
                "max_ms": stat.maxMs,
                "avg_ms": stat.totalMs / Double(max(stat.count, 1)),
                "changed": stat.changed,
                "errors": stat.errors,
            ] as [String: Any]
        }.sorted { ($0["total_ms"] as? Double ?? 0) > ($1["total_ms"] as? Double ?? 0) }
        stats.removeAll()
        writePayload(["type": "summary", "ts": timestamp(), "operations": operations, "queues": queueSnapshot(), "active_captures": ActiveWindowCaptures.value()], false)
    }

    private static func writePayload(_ payload: [String: Any], _ shouldUpdateStats: Bool) {
        if shouldUpdateStats { updateStats(payload) }
        guard let handle = openHandle(),
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let newline = "\n".data(using: .utf8) else { return }
        handle.write(data)
        handle.write(newline)
    }

    private static func updateStats(_ payload: [String: Any]) {
        guard let operation = payload["operation"] as? String,
              let durationMs = payload["duration_ms"] as? Double else { return }
        var stat = stats[operation] ?? Stats()
        stat.count += 1
        stat.totalMs += durationMs
        stat.maxMs = max(stat.maxMs, durationMs)
        if payload["changed"] as? Bool == true { stat.changed += 1 }
        if payload["success"] as? Bool == false || payload["error"] != nil { stat.errors += 1 }
        stats[operation] = stat
    }

    private static func openHandle() -> FileHandle? {
        if let fileHandle { return fileHandle }
        let url = logFileUrl()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
        return fileHandle
    }

    private static func logFileUrl() -> URL {
        let exec = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "alt-tab-macos"
        return URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Logs/\(exec)/perfdebug.jsonl")
    }

    private static func queueSnapshot() -> [String: [String: Int]] {
        let queues = [
            AXCallScheduler.shared.axQueryFirstTryQueue,
            AXCallScheduler.shared.axQueryScanQueue,
            AXCallScheduler.shared.axQueryRetryQueue,
            BackgroundWork.screenshotsQueue,
            BackgroundWork.accessibilityCommandsQueue,
            BackgroundWork.permissionsCheckOnTimerQueue,
            BackgroundWork.permissionsSystemCallsQueue,
            BackgroundWork.repeatingKeyQueue,
        ].compactMap { $0 }
        return Dictionary(uniqueKeysWithValues: queues.map { queue in
            let executing = queue.operations.reduce(0) { $0 + ($1.isExecuting ? 1 : 0) }
            return (queue.underlyingQueue?.label ?? "unknown", ["queued": queue.operationCount, "executing": executing, "callbacks": queue.activeCallbacks])
        })
    }
}
