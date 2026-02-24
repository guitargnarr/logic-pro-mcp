import Foundation
import os

/// Thread-safe one-shot flag for guarding CheckedContinuation resumption.
/// `tryConsume()` returns `true` exactly once, regardless of how many
/// threads call it concurrently.
final class OnceFlag: @unchecked Sendable {
    private var _consumed = false
    private let _lock = OSAllocatedUnfairLock()

    func tryConsume() -> Bool {
        _lock.lock()
        defer { _lock.unlock() }
        if _consumed { return false }
        _consumed = true
        return true
    }
}
