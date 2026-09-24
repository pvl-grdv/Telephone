//
//  SIPPortValidationTests.swift
//  TelephoneTests
//

import Testing

struct SIPPortValidationTests {
    @Test func acceptsEmptyPortAsAutomatic() {
        #expect(SIPPortValidation.value("") == 0)
        #expect(SIPPortValidation.value("   ") == 0)
    }

    @Test func acceptsValidPortRange() {
        #expect(SIPPortValidation.value("1") == 1)
        #expect(SIPPortValidation.value("5060") == 5060)
        #expect(SIPPortValidation.value("65535") == 65_535)
    }

    @Test func rejectsInvalidPorts() {
        #expect(SIPPortValidation.value("0") == nil)
        #expect(SIPPortValidation.value("-1") == nil)
        #expect(SIPPortValidation.value("65536") == nil)
        #expect(SIPPortValidation.value("abc") == nil)
    }
}
