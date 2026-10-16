import XCTest

final class FernUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Abre o app e garante que ele está em primeiro plano. Com vários monitores, o
    /// macOS às vezes abre a janela sem ativar o app, e as teclas iriam para outro app.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        XCTAssertTrue(app.textFields["addressBar"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testLaunchShowsAddressBar() {
        _ = launchApp()
    }

    /// Carrega uma página `data:` (sem rede) e confere que o título da janela muda.
    @MainActor
    func testTypingAnAddressLoadsThePage() {
        let app = launchApp()
        let addressBar = app.textFields["addressBar"]
        addressBar.click()
        addressBar.typeText("data:text/html,<title>Hello-Fern</title><p>ok</p>\n")

        XCTAssertTrue(app.windows["Hello-Fern"].waitForExistence(timeout: 10))
    }

    /// ⌘T abre uma aba na barra lateral e ⌘W fecha a aba, não a janela.
    @MainActor
    func testNewTabAndCloseTab() {
        let app = launchApp()
        let tabList = app.descendants(matching: .any)["tabList"]
        XCTAssertTrue(tabList.waitForExistence(timeout: 5))
        XCTAssertEqual(tabList.buttons.count, 1)
        app.textFields["addressBar"].click()

        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(tabList.buttons.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(tabList.buttons.count, 2)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(tabList.buttons.element(boundBy: 1).waitForNonExistence(timeout: 5))
        XCTAssertEqual(tabList.buttons.count, 1)
        XCTAssertEqual(app.windows.count, 1)
    }
}
