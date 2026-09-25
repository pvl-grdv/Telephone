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
