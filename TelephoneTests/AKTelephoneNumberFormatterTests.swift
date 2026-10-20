import Testing

struct AKTelephoneNumberFormatterTests {
    @Test func onlyASCIIDigitsAndOneOptionalPlusMakeAPlainPhoneNumber() {
        for value in ["0", "001", "1234567", "+12025550123", "+79852693536"] {
            #expect(isTelephoneNumber(value), "Expected a plain number: \(value)")
        }
        for value in ["", "+", "++123", "123+", "12 34", "(202) 555-0100",
                      "123-4567", "sip:alice@example.invalid", "alice", "12#",
                      "١٢٣", "１２３"] {
            #expect(!isTelephoneNumber(value), "Expected non-plain input: \(value)")
        }
    }

    @Test func formattingRespectsTheLastFourDigitsPreference() {
        let formatter = AKTelephoneNumberFormatter()
        #expect(formatter.string(for: "1234567") == "123-4567")
        formatter.splitsLastFourDigits = true
        #expect(formatter.string(for: "1234567") == "123-45-67")
        #expect(formatter.string(for: "+12025550123") == "+1 (202) 555-01-23")
    }

    @Test func sipURIPresentationFormatsOnlyPlainNumericUsers() {
        let formatter = AKSIPURIFormatter()
        formatter.formatsTelephoneNumbers = true
        formatter.telephoneNumberFormatterSplitsLastFourDigits = true

        let phone = AKSIPURI(user: "1234567", host: "example.invalid", displayName: "")
        #expect(formatter.string(for: phone) == "123-45-67")

        let username = AKSIPURI(user: "alice", host: "example.invalid", displayName: "")
        #expect(formatter.string(for: username) == username.sipAddress)

        let named = AKSIPURI(user: "+12025550123", host: "example.invalid", displayName: "Alice")
        #expect(formatter.string(for: named) == "Alice")

        formatter.formatsTelephoneNumbers = false
        #expect(formatter.string(for: phone) == "1234567")
    }
}
