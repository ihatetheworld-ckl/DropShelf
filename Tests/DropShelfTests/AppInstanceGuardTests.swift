import XCTest
@testable import DropShelf

final class AppInstanceGuardTests: XCTestCase {
    private let bundleID = "com.local.dropshelf"
    private func instance(_ processID: Int32, time: TimeInterval? = 1,
                          bundleID: String? = "com.local.dropshelf", terminated: Bool = false) -> AppInstanceSnapshot {
        AppInstanceSnapshot(processID: processID, bundleID: bundleID,
                            launchedAt: time.map { Date(timeIntervalSince1970: $0) }, isTerminated: terminated)
    }

    func testOneCopyStartsNormally() {
        XCTAssertNil(AppInstanceGuard.existingProcessID(currentProcessID: 100, bundleID: bundleID,
                                                       instances: [instance(100)]))
    }

    func testStartingSecondCopyYieldsWithoutReplacingExistingProcess() {
        let copies = [instance(100, time: 1), instance(200, time: 2)]
        XCTAssertEqual(AppInstanceGuard.existingProcessID(currentProcessID: 200, bundleID: bundleID,
                                                         instances: copies), 100)
        XCTAssertNil(AppInstanceGuard.existingProcessID(currentProcessID: 100, bundleID: bundleID,
                                                       instances: copies))
    }

    func testSimultaneousLaunchChoosesOneWinnerIndependentOfEnumerationOrder() {
        let copies = [instance(200), instance(100)]
        for order in [copies, Array(copies.reversed())] {
            XCTAssertEqual(AppInstanceGuard.existingProcessID(currentProcessID: 200, bundleID: bundleID,
                                                             instances: order), 100)
            XCTAssertNil(AppInstanceGuard.existingProcessID(currentProcessID: 100, bundleID: bundleID,
                                                           instances: order))
        }
    }

    func testUnrelatedAndTerminatedAppsCannotBlockStartup() {
        let copies = [instance(1, bundleID: "other.app"), instance(2, terminated: true), instance(100)]
        XCTAssertNil(AppInstanceGuard.existingProcessID(currentProcessID: 100, bundleID: bundleID,
                                                       instances: copies))
    }

    func testMissingLaunchDateStillProducesStableKeeper() {
        let copies = [instance(200, time: nil), instance(100, time: nil)]
        XCTAssertEqual(AppInstanceGuard.existingProcessID(currentProcessID: 200, bundleID: bundleID,
                                                         instances: copies), 100)
    }

    func testMissingDateCannotPromoteNewProcessAheadOfExistingKnownDate() {
        let copies = [instance(200, time: nil), instance(100, time: 1)]
        for order in [copies, Array(copies.reversed())] {
            XCTAssertEqual(AppInstanceGuard.existingProcessID(currentProcessID: 200, bundleID: bundleID,
                                                             instances: order), 100)
            XCTAssertNil(AppInstanceGuard.existingProcessID(currentProcessID: 100, bundleID: bundleID,
                                                           instances: order))
        }
    }

    func testCommandLineOrTestProcessWithoutBundleIdentifierIsNotAnotherApp() {
        XCTAssertNil(AppInstanceGuard.existingProcessID(currentProcessID: 100, bundleID: nil,
                                                       instances: [instance(1, bundleID: nil), instance(100, bundleID: nil)]))
    }
}
