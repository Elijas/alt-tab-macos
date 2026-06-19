import Cocoa
import AppCenter
import AppCenterCrashes

class AppCenterCrash: NSObject {
    static let secret = Bundle.main.object(forInfoDictionaryKey: "AppCenterSecret") as! String

    // Local-time formatter matching app.log's timestamp format, so a logged crash time can be
    // lined up by eye against the surrounding breadcrumbs.
    static let crashDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Logger.longDateTimeFormat
        return formatter
    }()

    override init() {
        super.init()
        // Enable catching uncaught exceptions thrown on the main thread
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
//        AppCenter.logLevel = .verbose
        // without this, appcenter makes network call just from AppCenter.start; we only want networking when sending reports
        AppCenter.networkRequestsAllowed = false
        AppCenter.start(withAppSecret: AppCenterCrash.secret, services: [Crashes.self])
        Crashes.delegate = self
        Crashes.userConfirmationHandler = confirmationHandler
    }

    // at launch, the crash report handler can be called before some things are not yet ready; we ensure they are
    func initNecessaryFacilities() {
        if UserDefaults.standard.string(forKey: "crashPolicy") == nil {
            UserDefaults.standard.register(defaults: ["crashPolicy": "1"])
        }
    }

    // periphery:ignore
    func confirmationHandler(_ errorReports: [ErrorReport]) -> Bool {
        logCrashReports(errorReports)
        initNecessaryFacilities()
        let shouldSend = checkIfShouldSend()
        BackgroundWork.startCrashReportsQueue()
        BackgroundWork.crashReportsQueue.addOperation {
            AppCenter.networkRequestsAllowed = shouldSend
            Crashes.notify(with: shouldSend ? .send : .dontSend)
            AppCenter.networkRequestsAllowed = false
        }
        return true
    }

    // Persist the previous session's crash details to app.log. Without this, crashes are routinely
    // lost: macOS frequently writes no .ips file, AppCenter purges the PLCrashReporter .plcrash
    // during this very processing pass (so it's already gone by the time the dialog appears), the
    // AppCenterSecret is the placeholder "#APPCENTER_SECRET#" so reports never upload, and the
    // on-disk AppCenter crash buffer is emptied too. app.log is the only durable sink that survives
    // a Finder/Dock launch. exceptionName/exceptionReason pin NSException crashes (e.g. the known
    // cross-thread Dictionary race: "unrecognized selector ... NSIndirectTaggedPointerString");
    // appProcessIdentifier + appErrorTime locate the exact crashed session in app.log. Grep with
    // "CRASH IN PREVIOUS SESSION".
    func logCrashReports(_ errorReports: [ErrorReport]) {
        for report in errorReports {
            Logger.error {
                "CRASH IN PREVIOUS SESSION"
                    + " incidentId:\(report.incidentIdentifier ?? "?")"
                    + " pid:\(report.appProcessIdentifier)"
                    + " signal:\(report.signal ?? "?")"
                    + " isAppKill:\(report.isAppKill)"
                    + " exception:\(report.exceptionName ?? "<none>")"
                    + " reason:\(report.exceptionReason ?? "<none>")"
                    + " appStart:\(report.appStartTime.map { AppCenterCrash.crashDateFormatter.string(from: $0) } ?? "?")"
                    + " appError:\(report.appErrorTime.map { AppCenterCrash.crashDateFormatter.string(from: $0) } ?? "?")"
            }
        }
    }

    func checkIfShouldSend() -> Bool {
        if Preferences.crashPolicy == .ask {
            App.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString("Send a crash report?", comment: "")
            alert.informativeText = NSLocalizedString("AltTab crashed last time you used it. Sending a crash report will help get the issue fixed", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Send", comment: "")).setAccessibilityFocused(true)
            let cancelButton = alert.addButton(withTitle: NSLocalizedString("Don’t send", comment: ""))
            cancelButton.keyEquivalent = "\u{1b}"
            let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Remember my choice", comment: ""), target: nil, action: nil)
            alert.accessoryView = checkbox
            let userChoice = alert.runModal()
            let id = crashButtonIdToUpdate(userChoice, checkbox)
            if let buttons = GeneralTab.crashPolicyDropdown, buttons.numberOfItems > id {
                buttons.selectItem(at: id)
            }
            Preferences.set("crashPolicy", String(id))
            return userChoice == .alertFirstButtonReturn
        }
        return Preferences.crashPolicy == .always
    }

    func crashButtonIdToUpdate(_ userChoice: NSApplication.ModalResponse, _ checkbox: NSButton) -> Int {
        if userChoice == .alertFirstButtonReturn {
            if checkbox.state == .on {
                return 2
            }
            return 1
        }
        if checkbox.state == .on {
            return 0
        }
        return 1
    }
}

extension AppCenterCrash: CrashesDelegate {
    func attachments(with crashes: Crashes, for errorReport: ErrorReport) -> [ErrorAttachmentLog]? {
        return [ErrorAttachmentLog.attachment(withText: DebugProfile.make(), filename: "debug-profile.md")!]
    }
}
