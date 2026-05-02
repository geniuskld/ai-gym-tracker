import XCTest
@testable import IronLog

/// CrashReporter is hard to fully test (signal handlers and uncaught
/// exceptions cannot be triggered safely from a unit test without
/// killing the test process). These tests cover the parts that are
/// safe and useful: install is idempotent and `uploadPending` does
/// not crash when there are no reports / no auth.
final class CrashReporterTests: XCTestCase {

    func testInstallIsIdempotent() {
        // Calling install repeatedly should not crash or double-register.
        // We cannot directly observe the signal handlers, but we can at
        // least verify nothing throws or aborts.
        CrashReporter.install()
        CrashReporter.install()
        CrashReporter.install()
        // Implicit pass: no crash.
    }

    func testUploadPendingHandlesEmptyFolderAndNoAuth() async {
        // No reports on disk, no JWT -- should be a clean no-op.
        await CrashReporter.uploadPending()
        // Implicit pass: completes without throwing.
    }
}
