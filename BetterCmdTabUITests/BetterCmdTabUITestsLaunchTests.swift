import XCTest

/// Launch-time metrics. Accessory app — no window screenshot worth keeping.
final class BetterCmdTabUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Reasonable target for an accessory app: <500ms cold-start on M-series.
        // Measure picks up regressions when SwitcherController boot path grows.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
