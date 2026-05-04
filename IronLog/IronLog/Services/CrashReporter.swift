import Foundation
import UIKit

/// Captures uncaught Obj-C exceptions and POSIX signals, persists a JSON
/// report to disk, and (on next launch) ships it to the sync server.
///
/// Notes on safety:
/// - Inside a signal handler only async-signal-safe APIs are formally allowed.
///   We use Foundation (JSONSerialization, FileManager) which is technically
///   not safe but in practice works for the common crash signals in iOS apps
///   that are not allocator-corrupted. This is a deliberate trade-off: a tiny
///   pure-C reporter would catch more cases but is disproportionate here.
/// - Re-entrancy is blocked via a flag so a crash inside the handler does not
///   loop. After we capture, we re-raise the signal with the default handler
///   so the OS still records the crash in its own logs.
enum CrashReporter {

    private static let folderName = "CrashReports"
    private static var didInstall = false
    private static var isHandling = false
    private static var previousExceptionHandler: (@convention(c) (NSException) -> Void)?

    private static let trappedSignals: [Int32] = [
        SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE,
    ]

    // MARK: - Install

    static func install() {
        guard !didInstall else { return }
        didInstall = true

        _ = ensureFolder()
        signal(SIGPIPE, SIG_IGN)

        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.handleException(exception)
            CrashReporter.previousExceptionHandler?(exception)
        }

        for sig in trappedSignals {
            signal(sig) { sig in
                CrashReporter.handleSignal(sig)
                // Re-raise with default handler so the OS still records it.
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
    }

    // MARK: - Upload pending reports

    /// Walks the reports folder and ships each file to the server.
    /// Files are removed only on successful upload; otherwise they remain
    /// for the next launch.
    static func uploadPending() async {
        let folder = ensureFolder()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in urls where url.pathExtension == "json" {
            await sendOne(url)
        }
    }

    private static func sendOne(_ url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            try await SyncService.uploadCrashReport(rawJSON: data)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // Keep file for next attempt.
        }
    }

    // MARK: - Handlers

    private static func handleException(_ exception: NSException) {
        guard !isHandling else { return }
        isHandling = true

        let report = makeReport(
            kind: "exception",
            name: exception.name.rawValue,
            reason: exception.reason ?? "",
            stack: exception.callStackSymbols
        )
        write(report)
    }

    private static func handleSignal(_ sig: Int32) {
        guard !isHandling else { return }
        isHandling = true

        let report = makeReport(
            kind: "signal",
            name: signalName(sig),
            reason: "Signal \(sig) (\(signalName(sig)))",
            stack: Thread.callStackSymbols
        )
        write(report)
    }

    // MARK: - Report assembly

    private static func makeReport(
        kind: String,
        name: String,
        reason: String,
        stack: [String]
    ) -> [String: Any] {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let appBuild = info?["CFBundleVersion"] as? String ?? "?"
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"

        return [
            "id": UUID().uuidString,
            "created_at": iso8601Now(),
            "app_version": appVersion,
            "app_build": appBuild,
            "os": os,
            "device_model": deviceModel(),
            "kind": kind,
            "name": name,
            "reason": reason,
            "stack": stack,
        ]
    }

    private static func write(_ report: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        let id = (report["id"] as? String) ?? UUID().uuidString
        let url = ensureFolder().appendingPathComponent("\(id).json")
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Helpers

    private static func ensureFolder() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private static func deviceModel() -> String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        var model = ""
        for child in mirror.children {
            guard let value = child.value as? Int8, value != 0 else { continue }
            model.append(Character(UnicodeScalar(UInt8(value))))
        }
        return model.isEmpty ? "unknown" : model
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS:  return "SIGBUS"
        case SIGILL:  return "SIGILL"
        case SIGTRAP: return "SIGTRAP"
        case SIGFPE:  return "SIGFPE"
        case SIGPIPE: return "SIGPIPE"
        default:      return "SIG(\(sig))"
        }
    }
}
