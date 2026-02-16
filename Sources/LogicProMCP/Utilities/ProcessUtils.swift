import Foundation
import AppKit

/// Utilities for finding and interacting with the Logic Pro process.
enum ProcessUtils {
    /// Returns the PID of Logic Pro if running, nil otherwise.
    static func logicProPID() -> pid_t? {
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: ServerConfig.logicProBundleID
        )
        return apps.first?.processIdentifier
    }

    /// Whether Logic Pro is currently running.
    static var isLogicProRunning: Bool {
        logicProPID() != nil
    }

    /// Bring Logic Pro to front (used sparingly — most operations don't need focus).
    static func activateLogicPro() -> Bool {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: ServerConfig.logicProBundleID
        ).first else { return false }
        return app.activate()
    }
}
