import XCTest

final class FlowUITests: XCTestCase {
    private let app = XCUIApplication()

    private enum Language: String, CaseIterable {
        case english = "en"
        case simplified = "zh-Hans"
        case traditional = "zh-Hant"

        var locale: String {
            switch self {
            case .english: "en_US"
            case .simplified: "zh_CN"
            case .traditional: "zh_TW"
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    private func launch(_ flags: [String] = [], language: Language = .simplified,
                        environment: [String: String] = [:]) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-ui-testing", "-reset", "-AppleLanguages", "(\(language.rawValue))",
                               "-AppleLocale", language.locale] + flags
        app.launchEnvironment = environment
        app.launch()
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons[id], file: file, line: line)
    }

    private func tap(_ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = button.waitForExistence(timeout: 8)
        for _ in 0..<3 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable, button.debugDescription, file: file, line: line)
        button.tap()
    }

    private func matching(_ prefix: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func text(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reasonField() -> XCUIElement {
        let single = app.textFields["capture.reason"]
        let multiline = app.textViews["capture.reason"]
        return single.exists ? single : multiline
    }

    private func shot(_ name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] {
            let path = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: path.appendingPathComponent(name + ".png"))
        }
    }

    func testTwoTapsSaveAndReasonPersistsAcrossLaunch() {
        launch(["-empty"])
        tap("home.capture")
        tap("verdict.skip")
        XCTAssertTrue(text("capture.saved").waitForExistence(timeout: 8))
        let field = reasonField()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Too dark")
        if app.buttons["capture.done"].isHittable { tap("capture.done") }
        let saved = text("capture.saved")
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-reset" }
        app.launch()
        tap("tab.records")
        XCTAssertTrue(matching("records.record.").firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(matching("records.record.").count, 1)
        tap(matching("records.record.").firstMatch)
        XCTAssertTrue(app.staticTexts["Too dark"].waitForExistence(timeout: 8))
    }

    func testLookupCandidatesFilterAndAppendHistory() {
        launch()
        tap("home.lookup")
        XCTAssertTrue(app.descendants(matching: .any)["match.verify"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(matching("match.record.").count, 2)
        tap(matching("match.record.").firstMatch)
        XCTAssertEqual(matching("history.trial.").count, 2)
        tap("detail.append")
        tap("verdict.retry")
        XCTAssertTrue(text("capture.saved").waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(matching("history.trial.").element(boundBy: 2).waitForExistence(timeout: 8))
    }

    func testExactMatchAndNoMatchFallback() {
        launch(environment: ["TRIALREBUY_OCR": "雾岛\n丝绒唇膏\n05 栗棕"])
        tap("home.lookup")
        XCTAssertTrue(app.descendants(matching: .any)["match.exact"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(matching("match.record.").count, 1)
        launch(environment: ["TRIALREBUY_OCR": "Unrelated Package"])
        tap("home.lookup")
        tap("verdict.buy")
        XCTAssertTrue(text("capture.saved").waitForExistence(timeout: 8))
    }

    func testManualAfterCameraDenialAndTextSearch() {
        launch(["-camera-denied"])
        tap("home.capture")
        XCTAssertTrue(text("camera.message").waitForExistence(timeout: 8))
        tap("home.manual")
        tap("verdict.retry")
        XCTAssertTrue(text("capture.saved").waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let search = app.textFields["search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("June")
        XCTAssertTrue(matching("search.record.").firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(matching("search.record.").count, 1)
    }

    func testExpiredKeepsRecordingHistoryShareAndBackup() {
        launch(["-expired"])
        tap("tab.records")
        tap("records.filter.skip")
        XCTAssertEqual(matching("records.record.").count, 1)
        tap(matching("records.record.").firstMatch)
        XCTAssertTrue(matching("history.trial.").firstMatch.waitForExistence(timeout: 8))
        tap("detail.share")
        tap("share.image")
        XCTAssertTrue(app.descendants(matching: .any)["share.requested"].firstMatch.waitForExistence(timeout: 12))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("tab.settings")
        tap("settings.backup")
        tap("backup.export")
        XCTAssertTrue(text("backup.status").waitForExistence(timeout: 8))
        tap("backup.restore")
        XCTAssertTrue(text("backup.preview").waitForExistence(timeout: 8))
        tap("backup.confirm")
        XCTAssertTrue(text("backup.status").waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("settings.stats")
        XCTAssertTrue(text("pay.status").waitForExistence(timeout: 8))
        tap("pay.continue")
        tap("tab.home")
        tap("home.manual")
        tap("verdict.buy")
        XCTAssertTrue(text("capture.saved").waitForExistence(timeout: 8))
    }

    func testStyleCodePreviewApplyAndCSV() {
        launch(["-purchased"], environment: [
            "TRIALREBUY_CODE": "TRY1:eyJwYWxldHRlIjoic2FuZCIsInByZWZlclBob3RvcyI6dHJ1ZX0=",
            "TRIALREBUY_CSV": "brand,product,shade,verdict,reason\nJune,New Cream,,buy,Light feel"
        ])
        tap("tab.settings")
        tap("settings.code")
        tap("code.paste")
        tap("code.apply")
        XCTAssertTrue(text("code.applied").waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("settings.csv")
        tap("csv.choose")
        XCTAssertTrue(text("csv.preview").waitForExistence(timeout: 8))
        tap("csv.confirm")
        XCTAssertTrue(text("csv.status").waitForExistence(timeout: 8))
    }

    func testEditExistingProductAndUndoDelete() {
        launch()
        tap("tab.records")
        tap(matching("records.record.").firstMatch)
        tap("detail.edit")
        let field = app.textFields["edit.product"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let existing = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        field.typeText("Updated Lipstick")
        tap("edit.save")
        let renamed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Updated Lipstick")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 8))
        tap("detail.delete")
        let delete = app.alerts.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 8))
        delete.tap()
        tap("record.undo")
        XCTAssertEqual(matching("records.record.").count, 4)
    }

    func testMilestoneRemainsAvailableAfterDismissal() {
        launch()
        tap("home.capture")
        tap("verdict.buy")
        XCTAssertTrue(text("capture.saved").waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("milestone.dismiss")
        tap("tab.settings")
        tap("settings.milestones")
        tap("milestone.5")
        tap("share.image")
        XCTAssertTrue(app.descendants(matching: .any)["share.requested"].firstMatch.waitForExistence(timeout: 12))
    }

    func testStoreScreenshots() throws {
        for language in Language.allCases {
            launch(language: language)
            XCTAssertTrue(matching("home.record.").firstMatch.waitForExistence(timeout: 8))
            try shot("store-\(language.rawValue)-01-home")
            tap("home.capture")
            XCTAssertTrue(app.buttons["verdict.skip"].waitForExistence(timeout: 8))
            XCTAssertTrue(text("capture.photo").waitForExistence(timeout: 8))
            try shot("store-\(language.rawValue)-02-verdict")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            tap("home.lookup")
            XCTAssertTrue(matching("match.record.").element(boundBy: 1).waitForExistence(timeout: 8))
            try shot("store-\(language.rawValue)-03-match")
            tap(matching("match.record.").firstMatch)
            XCTAssertTrue(matching("history.trial.").firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(text("detail.photo").waitForExistence(timeout: 8))
            try shot("store-\(language.rawValue)-04-history")
            tap("detail.share")
            let picker = app.segmentedControls["share.collection"]
            XCTAssertTrue(picker.waitForExistence(timeout: 8))
            tap(picker.buttons.element(boundBy: 1))
            let button = app.buttons["share.image"]
            let enabled = NSPredicate(format: "exists == true AND enabled == true")
            expectation(for: enabled, evaluatedWith: button)
            waitForExpectations(timeout: 10)
            try shot("store-\(language.rawValue)-05-share")
        }
    }

    func testPaidScreenshotAndRestoreEntry() throws {
        launch(["-paywall"])
        XCTAssertTrue(app.buttons["pay.restore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["pay.claim"].exists)
        try shot("paid-01-paywall")
        tap("pay.restore")
        XCTAssertTrue(text("pay.message").waitForExistence(timeout: 8))
        tap("pay.buy")
        XCTAssertTrue(text("pay.unlocked").waitForExistence(timeout: 8))
    }
}
