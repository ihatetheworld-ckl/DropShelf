import AppKit
import Foundation

struct AppInstanceSnapshot {
    let processID: Int32
    let bundleID: String?
    let launchedAt: Date?
    let isTerminated: Bool
}

enum AppInstanceGuard {
    /// Keep the first process. Starting another copy must never discard an
    /// existing shelf or start a second set of global event monitors.
    static func existingProcessID(currentProcessID: Int32, bundleID: String?,
                                  instances: [AppInstanceSnapshot]) -> Int32? {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return nil }
        let matching = instances.filter { !$0.isTerminated && $0.bundleID == bundleID }
        // Mixing a missing date with real dates must not make a newly started
        // process look older than the existing app. Use one consistent ordering.
        let datesAvailable = matching.allSatisfy { $0.launchedAt != nil }
        let keeper = matching.min {
            guard datesAvailable else { return $0.processID < $1.processID }
            let left = $0.launchedAt!
            let right = $1.launchedAt!
            return left == right ? $0.processID < $1.processID : left < right
        }
        guard let keeper = keeper, keeper.processID != currentProcessID else { return nil }
        return keeper.processID
    }

    static func existingApplication() -> NSRunningApplication? {
        let current = NSRunningApplication.current
        let applications = NSWorkspace.shared.runningApplications
        let snapshots = applications.map {
            AppInstanceSnapshot(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier,
                                launchedAt: $0.launchDate, isTerminated: $0.isTerminated)
        }
        guard let processID = existingProcessID(currentProcessID: current.processIdentifier,
                                               bundleID: current.bundleIdentifier,
                                               instances: snapshots) else { return nil }
        return applications.first { $0.processIdentifier == processID }
    }
}
