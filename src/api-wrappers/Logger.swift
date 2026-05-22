import SwiftyBeaver
import Foundation

class Logger {
    private static let logger = SwiftyBeaver.self
    static let flag = "--logs="
    static let longDateTimeFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    static let shortDateTimeFormat = "HH:mm:ss.SSS"

    static func initialize() {
        let console = ConsoleDestination()
        console.useTerminalColors = true
        configureDestination(console)
        console.format = "$C$D\(shortDateTimeFormat)$d $L$c $N.swift:$l $F $M"
        console.minLevel = decideLevel()
        logger.addDestination(console)

        // Persist logs to disk — console output is lost when launched from Finder/Dock
        let exec = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "alt-tab-macos"
        let logsDir = "\(NSHomeDirectory())/Library/Logs/\(exec)"
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        let file = FileDestination()
        file.logFileURL = URL(fileURLWithPath: "\(logsDir)/app.log")
        configureDestination(file)
        file.minLevel = .info
        logger.addDestination(file)
        PerfDebug.initialize()
    }

    static func configureDestination(_ dest: BaseDestination) {
        dest.levelString.verbose = "VERB"
        dest.levelString.debug = "DEBG"
        dest.levelString.info = "INFO"
        dest.levelString.warning = "WARN"
        dest.levelString.error = "ERRO"
        dest.format = "$D\(shortDateTimeFormat)$d $L $N.swift:$l $F $M"
    }

    @discardableResult
    static func addDestination(_ dest: BaseDestination) -> Bool {
        logger.addDestination(dest)
    }

    @discardableResult
    static func removeDestination(_ dest: BaseDestination) -> Bool {
        logger.removeDestination(dest)
    }

    static func decideLevel() -> SwiftyBeaver.Level {
        if let level = (CommandLine.arguments.first { $0.starts(with: flag) })?.dropFirst(flag.count) {
            switch level {
                case "verbose": return .verbose
                case "debug": return .debug
                case "info": return .info
                case "warning": return .warning
                case "error": return .error
                default: break
            }
        }
        return .error
    }

    static func debug(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .debug, file: file, function: function, line: line, context: context, message)
    }

    static func info(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .info, file: file, function: function, line: line, context: context, message)
    }

    static func warning(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .warning, file: file, function: function, line: line, context: context, message)
    }

    static func error(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .error, file: file, function: function, line: line, context: context, message)
    }

    private static func custom(level: SwiftyBeaver.Level, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil, _ message: @escaping () -> Any?) {
        logger.custom(level: level, message: { "[\(threadName())] \(message())" }(), file: file, function: function, line: line, context: context)
    }


    private static func threadName() -> String {
        if Thread.isMainThread {
            return "main"
        } else if let name = Thread.current.name, !name.isEmpty {
            return name
        } else {
            let name = __dispatch_queue_get_label(nil)
            return String(cString: name, encoding: .utf8) ?? Thread.current.description
        }
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
            BackgroundWork.screenshotsQueue,
            BackgroundWork.accessibilityCommandsQueue,
            BackgroundWork.permissionsCheckOnTimerQueue,
            BackgroundWork.permissionsSystemCallsQueue,
            BackgroundWork.repeatingKeyQueue,
            AXCallScheduler.shared.fastQueue,
            AXCallScheduler.shared.retryQueue,
        ].compactMap { $0 }
        return Dictionary(uniqueKeysWithValues: queues.map { queue in
            let executing = queue.operations.reduce(0) { $0 + ($1.isExecuting ? 1 : 0) }
            return (queue.underlyingQueue?.label ?? "unknown", ["queued": queue.operationCount, "executing": executing, "callbacks": queue.activeCallbacks])
        })
    }
}

/// custom destination to display logs in the debug window
class DebugWindowDestination: BaseDestination {
    var onNewEntry: ((SwiftyBeaver.Level, String) -> Void)?

    override var defaultHashValue: Int { return 2 }

    override init() {
        super.init()
        Logger.configureDestination(self)
        minLevel = .debug
    }

    override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String,
                       file: String, function: String, line: Int, context: Any? = nil) -> String? {
        let formattedString = super.send(level, msg: msg, thread: thread,
                                         file: file, function: function, line: line, context: context)
        guard let formatted = formattedString else { return nil }
        let callback = onNewEntry
        DispatchQueue.main.async { callback?(level, formatted) }
        return formattedString
    }
}
