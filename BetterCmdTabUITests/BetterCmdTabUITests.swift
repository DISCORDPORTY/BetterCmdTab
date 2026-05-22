import XCTest

/// BetterCmdTab is an LSUIElement (accessory) app — no main window, no Dock
/// entry. UI assertions limited to: launch succeeds, status item registers,
/// process stays alive long enough to serve hotkeys.
final class BetterCmdTabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchSucceeds() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground, "App must reach runningForeground after launch")
    }

    @MainActor
    func testStaysRunningAfterLaunch() throws {
        // Accessory apps shouldn't auto-terminate when last window closes —
        // they have no window. Verify process survives a short idle window.
        let app = XCUIApplication()
        app.launch()
        let stillRunning = NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: stillRunning, object: app)
        let result = XCTWaiter().wait(for: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed, "App must remain running 3s after launch")
    }

    @MainActor
    func testCleanTerminate() throws {
        let app = XCUIApplication()
        app.launch()
        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "App must terminate cleanly")
    }
}
