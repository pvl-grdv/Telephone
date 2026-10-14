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

    func testTypingInClientDetailsDoesNotAnswerOrDeclineTheCall() throws {
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
        let selector = element("call.customerDetails.section", in: app)
        XCTAssertTrue(selector.waitForExistence(timeout: 3), app.debugDescription)
        let crm = selector.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "CRM")).firstMatch
        let localDetails = selector.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Local details")).firstMatch
        XCTAssertTrue(crm.isHittable, app.debugDescription)
        XCTAssertTrue(localDetails.isHittable, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Local notes"].exists)

        let key = element("customer.crm.keyNumber", in: app)
        XCTAssertTrue(key.waitForExistence(timeout: 3))
        key.click()
        key.typeText("1")
        key.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(answer.exists, "Return in CRM lookup must not answer the call.")
        XCTAssertFalse(element("call.end", in: app).exists)
        // Native .searchable is exposed as an AppKit search field, not the old
        // custom TextField accessibility identifier.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(search.isHittable, "Inventory search must be usable in the CRM pane.")
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Air")
        XCTAssertEqual(search.value as? String, "Air", "⌘F must focus the native CRM search field.")

        localDetails.click()
        let company = app.textFields["Organization"]
        XCTAssertTrue(company.waitForExistence(timeout: 3))
        XCTAssertTrue(company.isHittable)
        XCTAssertTrue(app.textFields["Reference keys"].isHittable)
        XCTAssertTrue(app.textFields["Email addresses"].isHittable)
        XCTAssertFalse(element("customer.local.note", in: app).exists)
        XCTAssertFalse(app.staticTexts["Notes for this call"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Saved synthetic")).firstMatch.exists)
        company.click()
        company.typeText("Synthetic organization")
        company.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(answer.exists, "Return in local details must leave the call ringing.")
        XCTAssertFalse(element("call.end", in: app).exists)
        XCTAssertFalse(search.exists, "Inactive CRM controls must leave the accessibility tree.")
        crm.click()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "Air", "Inventory filter survives changing sections.")
        XCTAssertFalse(company.exists, "Inactive local controls must leave the accessibility tree.")
        localDetails.click()
        XCTAssertTrue(company.waitForExistence(timeout: 3))
        XCTAssertTrue((company.value as? String)?.contains("Synthetic organization") == true)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let closeDetails = element("call.closeCustomerDetails", in: app)
        XCTAssertTrue(closeDetails.waitForNonExistence(timeout: 3))
        XCTAssertTrue(answer.exists, "Escape closes details without declining the incoming call.")

        openDetails.click()
        XCTAssertTrue(company.waitForExistence(timeout: 3))
        XCTAssertTrue((company.value as? String)?.contains("Synthetic organization") == true)
        XCTAssertFalse(element("customer.local.note", in: app).exists)
        // The details window can cover the call controls. Use macOS's normal
        // Next Window shortcut, leaving details open, before clicking Answer.
        app.typeKey("`", modifierFlags: .command)
        answer.click()
        let endCall = element("call.end", in: app)
        XCTAssertTrue(endCall.waitForExistence(timeout: 3))
        XCTAssertTrue(closeDetails.exists, "Answering preserves the open details window.")
        XCTAssertTrue((company.value as? String)?.contains("Synthetic organization") == true)
        endCall.click()
        XCTAssertTrue(endCall.waitForNonExistence(timeout: 3))
        XCTAssertTrue(closeDetails.waitForNonExistence(timeout: 3))
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
