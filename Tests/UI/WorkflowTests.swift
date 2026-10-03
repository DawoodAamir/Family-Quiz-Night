import XCTest

@MainActor final class WorkflowTests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  func testNativeWorkflow() {
    let app = XCUIApplication()
    app.launch()
    #if os(tvOS)
      let start = app.buttons["remotePlay"]
      XCTAssertTrue(start.waitForExistence(timeout: 30), app.debugDescription)
      select(start, in: app)
      for (index, answer) in [1, 0, 2, 3, 1, 0].enumerated() {
        XCTAssertTrue(
          app.staticTexts["questionPrompt"].waitForExistence(timeout: 10), app.debugDescription)
        select(app.buttons["answer-\(answer)"], in: app)
        let next = app.buttons["nextQuestion"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["\((index + 1) * 100) points"].exists, app.debugDescription)
        if index == 0 { capture(app, name: "Revealed round") }
        select(next, in: app)
      }
      XCTAssertTrue(app.staticTexts["That's a wrap."].waitForExistence(timeout: 10))
      capture(app, name: "Final scores")
    #else
      XCTAssertTrue(app.textFields["teamName"].waitForExistence(timeout: 20))
      app.textFields["teamName"].tap()
      app.textFields["teamName"].typeText(" family")
      XCTAssertTrue(app.textFields["roomCode"].exists)
      XCTAssertTrue(app.buttons["Find local rooms"].exists)
      capture(app, name: "Phone controller")
    #endif
  }
  private func capture(_ app: XCUIApplication, name: String) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
  }
  #if os(tvOS)
    private func select(_ target: XCUIElement, in app: XCUIApplication) {
      for _ in 0..<24 {
        if target.hasFocus {
          XCUIRemote.shared.press(.select)
          return
        }
        let focused = app.buttons.matching(
          NSPredicate(format: "hasFocus == true")
        ).firstMatch
        guard focused.exists else {
          XCUIRemote.shared.press(.down)
          Thread.sleep(forTimeInterval: 0.3)
          continue
        }
        let dx = target.frame.midX - focused.frame.midX
        let dy = target.frame.midY - focused.frame.midY
        if abs(dy) > 70 {
          XCUIRemote.shared.press(dy > 0 ? .down : .up)
        } else {
          XCUIRemote.shared.press(dx > 0 ? .right : .left)
        }
        Thread.sleep(forTimeInterval: 0.3)
      }
      XCTFail("Could not focus \(target.identifier): \(app.debugDescription)")
    }
  #endif
}
