import XCTest

/// Xcode's automated accessibility audit, one screen at a time
/// (docs/ACCESSIBILITY.md). Screens are reached by their labels.
@MainActor
final class AccessibilityAuditTests: XCTestCase {

    private lazy var app: XCUIApplication = {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestResetState", "-HashiScreenshotUnlock"]
        return app
    }()

    private var acceptListFalsePositives = false
    private var acceptUnattributedBoardDigits = false

    private func audit() throws {
        try app.performAccessibilityAudit { issue in
            print("AUDIT | \(issue.compactDescription) | \(issue.element?.elementType.rawValue ?? 0) | \(issue.element?.label ?? "-") | \(issue.element.map { "\($0.frame)" } ?? "") | \(issue.detailedDescription)")
            // Accepted, documented in docs/ACCESSIBILITY.md: the wordmark and
            // island numerals (sized to the disc) are fixed-size drawings.
            if issue.auditType == .dynamicType, let label = issue.element?.label,
               ["JUST", "Hashi", "Just Hashi"].contains(label) || label.hasPrefix("Island ")
                || (!label.isEmpty && label.allSatisfy(\.isNumber)) { return true }
            if self.acceptUnattributedBoardDigits, issue.element == nil, issue.auditType == .dynamicType { return true }
            if self.acceptListFalsePositives, [.dynamicType, .textClipped].contains(issue.auditType) { return true }
            return false
        }
    }

    private func startGame() {
        app.buttons["Play"].tap()
        let island = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Island '")).firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20))
    }

    func testHome() throws {
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        try audit()
    }

    func testBoard() throws {
        app.launch()
        startGame()
        let island = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Island '")).firstMatch
        XCTAssertTrue((island.value as? String)?.contains(" to the ") == true,
                      "an island names its neighbours")
        try audit()
    }

    func testHint() throws {
        app.launch()
        startGame()
        app.buttons["Hint"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Dismiss hint"].waitForExistence(timeout: 5))
        acceptUnattributedBoardDigits = true
        try audit()
    }

    func testLearn() throws {
        app.launch()
        app.buttons["Learn"].tap()
        sleep(1)
        acceptListFalsePositives = true
        try audit()
    }

    func testStats() throws {
        app.launch()
        app.buttons["Stats"].tap()
        sleep(1)
        acceptListFalsePositives = true
        try audit()
    }

    func testPastDailies() throws {
        app.launch()
        app.buttons["Past dailies"].tap()
        sleep(1)
        acceptListFalsePositives = true
        try audit()
    }

    func testSettings() throws {
        app.launch()
        app.buttons["Settings"].tap()
        sleep(1)
        acceptListFalsePositives = true
        try audit()
    }

    func testHomeAtLargestTextSize() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        try audit()
    }
}
