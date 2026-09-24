//
//  TelephoneAppIntentsTests.swift
//  TelephoneAppIntentsTests
//

import AppIntentsTesting
import XCTest

final class TelephoneAppIntentsTests: XCTestCase {
    private let definitions = IntentDefinitions(
        bundleIdentifier: "com.tlphn.Telephone"
    )

    func testOpenSettingsIntentExecutesThroughAppIntentsStack() async throws {
        _ = try await definitions.intents[
            "OpenTelephoneSettingsIntent"
        ]
        .makeIntent()
        .run()
    }

    func testAccountEntitySuggestedQueryExecutesThroughAppIntentsStack()
        async throws
    {
        _ = try await definitions.entities[
            "TelephoneAccountEntity"
        ]
        .suggestedEntities()
    }

    func testCallIntentDefinitionAcceptsDestinationParameter() {
        _ = definitions.intents[
            "CallWithTelephoneIntent"
        ]
        .makeIntent(destination: "100")
    }

    func testAvailabilityIntentDefinitionAcceptsEntityAndEnumParameters() {
        let account = definitions.entities[
            "TelephoneAccountEntity"
        ]
        .makeReference(identifier: "test-account")
        let availability = definitions.enums[
            "TelephoneAvailability"
        ]
        .makeCase("offline")

        _ = definitions.intents[
            "SetTelephoneAccountAvailabilityIntent"
        ]
        .makeIntent(
            account: account,
            availability: availability
        )
    }
}
