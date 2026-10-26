//
//  TelephoneUISmokeTests.swift
//  TelephoneAppIntentsTests
//

import Foundation
import XCTest

@MainActor
final class TelephoneUISmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEnglishSmoke() throws {
        try runSmoke(
            LocaleFixture(
                language: "en",
                locale: "en_US",
                general: "General",
                accounts: "Accounts",
                network: "Network",
                localSIPPort: "Local SIP Port",
                addAccount: "Add Account",
                accountSetup: "SIP Account Setup",
                cancel: "Cancel",
                done: "Done",
                answer: "Answer",
                endCall: "End Call"
            )
        )
    }

    func testGermanSmoke() throws {
        try runSmoke(
            LocaleFixture(
                language: "de",
                locale: "de_DE",
                general: "Allgemein",
                accounts: "Accounts",
                network: "Netzwerk",
                localSIPPort: "Lokaler SIP-Port",
                addAccount: "Account hinzufügen",
                accountSetup: "SIP-Account einrichten",
                cancel: "Abbrechen",
                done: "Fertig",
                answer: "Annehmen",
                endCall: "Anruf beenden"
            )
        )
    }

    func testRussianSmoke() throws {
        try runSmoke(
            LocaleFixture(
                language: "ru",
                locale: "ru_RU",
                general: "Основные",
                accounts: "Аккаунты",
                network: "Сеть",
                localSIPPort: "Локальный SIP-порт",
                addAccount: "Добавить аккаунт",
                accountSetup: "Новый SIP-аккаунт",
                cancel: "Отмена",
                done: "Добавить",
                answer: "Ответить",
                endCall: "Завершить звонок"
            )
        )
    }

    private func runSmoke(_ locale: LocaleFixture) throws {
        let settings = launch(
            scenario: "settings",
            locale: locale
        )

        XCTAssertTrue(
            element("settings.general.content", in: settings)
                .waitForExistence(timeout: 5),
            "Settings content should be visible after launching the settings scenario."
        )

        let generalTab = labeledElement(
            locale.general,
            in: settings
        )
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5))
        XCTAssertEqual(generalTab.label, locale.general)

        let networkTab = labeledElement(
            locale.network,
            in: settings
        )
        XCTAssertTrue(networkTab.waitForExistence(timeout: 2))
        XCTAssertEqual(networkTab.label, locale.network)
        networkTab.click()

        XCTAssertTrue(
            settings.staticTexts[locale.localSIPPort]
                .waitForExistence(timeout: 3)
        )

        let accountsTab = labeledElement(
            locale.accounts,
            in: settings
        )
        XCTAssertTrue(accountsTab.waitForExistence(timeout: 2))
        XCTAssertEqual(accountsTab.label, locale.accounts)
        accountsTab.click()

        let addAccount = labeledElement(
            locale.addAccount,
            in: settings
        )
        XCTAssertTrue(addAccount.waitForExistence(timeout: 3))
        XCTAssertEqual(addAccount.label, locale.addAccount)

        settings.terminate()

        let accountSetup = launch(
            scenario: "account-setup",
            locale: locale
        )

        XCTAssertTrue(
            accountSetup.staticTexts[locale.accountSetup]
                .waitForExistence(timeout: 5)
        )

        for identifier in [
            "account-setup.full-name",
            "account-setup.domain",
            "account-setup.username",
            "account-setup.password",
        ] {
            XCTAssertTrue(
                element(identifier, in: accountSetup)
                    .waitForExistence(timeout: 2),
                "\(identifier) should be accessible."
            )
        }

        let cancel = labeledElement(
            locale.cancel,
            in: accountSetup
        )
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        XCTAssertEqual(cancel.label, locale.cancel)

        let done = labeledElement(
            locale.done,
            in: accountSetup
        )
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        XCTAssertEqual(done.label, locale.done)

        accountSetup.typeKey(
            XCUIKeyboardKey.escape,
            modifierFlags: []
        )
        XCTAssertTrue(
            cancel.waitForNonExistence(timeout: 3),
            "Escape should cancel first-run account setup."
        )

        let call = launch(
            scenario: "incoming-call",
            locale: locale
        )

        let answer = element("call.answer", in: call)
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertEqual(answer.label, locale.answer)

        call.typeKey(
            XCUIKeyboardKey.return,
            modifierFlags: []
        )

        let endCall = element("call.end", in: call)
        XCTAssertTrue(
            endCall.waitForExistence(timeout: 3),
            "Return should activate the default Answer action."
        )
        XCTAssertEqual(endCall.label, locale.endCall)

        for identifier in ["call.mute", "call.hold", "call.transfer"] {
            let control = element(identifier, in: call)
            XCTAssertTrue(control.waitForExistence(timeout: 2))
            XCTAssertFalse(
                control.label.isEmpty,
                "\(identifier) should expose an accessibility label."
            )
        }

        endCall.click()
        XCTAssertTrue(
            endCall.waitForNonExistence(timeout: 3),
            "Ending the synthetic call should close the call window."
        )

        call.terminate()
    }

    func testCRMWorkspaceSearchesByKeyWithoutAnActiveCall() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TELEPHONE_UI_TEST_SCENARIO"] = "crm-workspace"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        // Key number is the primary field; email and registration search remain visible.
        let key = element("customer.crm.keyNumber", in: app)
        XCTAssertTrue(key.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("customer.crm.email", in: app).exists)
        XCTAssertTrue(element("customer.crm.organizationCode", in: app).exists)

        key.click()
        key.typeText("1")
        let find = element("customer.crm.search", in: app)
        XCTAssertTrue(find.isEnabled)
        find.click()
        XCTAssertTrue(element("crm.inventory.programs", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("call.end", in: app).exists)
    }

    func testCRMWorkspaceSearchesByEmailWithoutAnActiveCall() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TELEPHONE_UI_TEST_SCENARIO"] = "crm-workspace"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        // All manual search fields must be available without switching modes.
        XCTAssertTrue(element("customer.crm.keyNumber", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("customer.crm.organizationCode", in: app).exists)

        let email = element("customer.crm.email", in: app)
        XCTAssertTrue(email.waitForExistence(timeout: 3), app.debugDescription)
        email.click()
        email.typeText("example@example.test")

        let find = element("customer.crm.searchEmail", in: app)
        XCTAssertTrue(find.isEnabled)
        find.click()
        XCTAssertTrue(element("crm.inventory.programs", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("crm.inventory.keyFilter", in: app).exists)
        XCTAssertFalse(element("call.end", in: app).exists)
    }

    func testCRMOnlyClientDetailsDoesNotAnswerOrDeclineTheCall() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TELEPHONE_UI_TEST_SCENARIO"] = "incoming-call-details"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        let answer = element("call.answer", in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let openDetails = element("call.customerDetails", in: app)
        XCTAssertTrue(openDetails.waitForExistence(timeout: 3), app.debugDescription)
        openDetails.click()

        XCTAssertFalse(element("call.customerDetails.section", in: app).exists)
        XCTAssertFalse(app.textFields["Organization"].exists)
        XCTAssertFalse(app.textFields["Reference keys"].exists)
        XCTAssertFalse(app.textFields["Email addresses"].exists)

        let otherSearch = app.buttons["Search organization…"]
        XCTAssertTrue(otherSearch.waitForExistence(timeout: 3), app.debugDescription)
        otherSearch.click()
        XCTAssertTrue(element("customer.crm.email", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("customer.crm.organizationCode", in: app).exists)
        let key = element("customer.crm.keyNumber", in: app)
        XCTAssertTrue(key.waitForExistence(timeout: 3), app.debugDescription)
        key.click()
        key.typeText("1")
        key.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(answer.exists, "Return in CRM lookup must not answer the call.")
        XCTAssertFalse(element("call.end", in: app).exists)

        let search = element("crm.inventory.search", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.click()
        search.typeText("Air")
        XCTAssertEqual(search.value as? String, "Air", "Inventory search is usable.")
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(search.isHittable)
        XCTAssertTrue(element("crm.inventory.keyFilter", in: app).exists)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(answer.exists, "Closing CRM must not decline a ringing call.")
        openDetails.click()
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        XCTAssertEqual(search.value as? String, "Air", "Search persists while a live call is active.")

        // Return focus to the call window without closing CRM.
        app.typeKey("`", modifierFlags: .command)
        answer.click()
        let endCall = element("call.end", in: app)
        XCTAssertTrue(endCall.waitForExistence(timeout: 3))
        endCall.click()
        XCTAssertTrue(endCall.waitForNonExistence(timeout: 3))
    }

    func testHistoryLooksUpVisibleRowsAndKeepsUnknownSeparateFromUnanswered() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TELEPHONE_UI_TEST_SCENARIO"] = "call-history"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        let answered = element("call-history.row.answered", in: app)
        let unanswered = element("call-history.row.unanswered", in: app)
        let unknown = element("call-history.row.unknown", in: app)
        XCTAssertTrue(answered.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(unanswered.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(unknown.waitForExistence(timeout: 3), app.debugDescription)
        waitForText("Answered by: Synthetic Employee", in: answered)
        waitForText("No One Answered", in: unanswered)
        XCTAssertFalse(accessibleText(of: unanswered).contains("Answered by:"))
        XCTAssertTrue(accessibleText(of: unknown).contains("Not Answered Here"), app.debugDescription)
        XCTAssertFalse(accessibleText(of: unknown).contains("Answered by:"))
        XCTAssertFalse(accessibleText(of: unknown).contains("No One Answered"))

        let search = app.textFields["Search Call History"]
        XCTAssertTrue(search.waitForExistence(timeout: 3), app.debugDescription)
        search.click()
        search.typeText("Synthetic unanswered")
        XCTAssertTrue(answered.waitForNonExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(unknown.waitForNonExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(unanswered.exists)
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        XCTAssertTrue(answered.waitForExistence(timeout: 3), app.debugDescription)
        waitForText("Answered by: Synthetic Employee", in: answered)
        let refresh = app.buttons["Refresh Call Answers"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3), app.debugDescription)
        refresh.click()
        waitForText("Answered by: Synthetic Employee", in: answered)
    }

    private func accessibleText(of element: XCUIElement) -> String {
        element.label + " " + (element.value as? String ?? "")
    }

    private func waitForText(_ text: String, in element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
            "Expected \(text) in \(element.debugDescription)")
    }

    private func launch(
        scenario: String,
        locale: LocaleFixture
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TELEPHONE_UI_TEST_SCENARIO"] = scenario
        app.launchArguments += [
            "-AppleLanguages",
            "(\(locale.language))",
            "-AppleLocale",
            locale.locale,
        ]
        app.launch()
        return app
    }

    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func labeledElement(
        _ label: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    label
                )
            )
            .firstMatch
    }
}

private struct LocaleFixture {
    let language: String
    let locale: String
    let general: String
    let accounts: String
    let network: String
    let localSIPPort: String
    let addAccount: String
    let accountSetup: String
    let cancel: String
    let done: String
    let answer: String
    let endCall: String
}
