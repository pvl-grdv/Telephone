import Foundation
import Testing

struct CRMPhoneNumberTests {
    @Test func russianRepresentationsHaveOneCanonicalIdentity() {
        for value in ["+7 (000) 555-01-01", "70005550101", "8 (000) 555-01-01", "0005550101"] {
            #expect(CRMPhoneNumber.normalize(value) == "+70005550101")
        }
        #expect(CRMPhoneNumber.contains("70005550101", in: "+1 202 555 0100, 8 (000) 555-01-01"))
        #expect(!CRMPhoneNumber.contains("70005550101", in: "70005550102"))
    }

    @Test func explicitInternationalPrefixIsNotReinterpretedAsRussian() {
        #expect(CRMPhoneNumber.normalize("+80055501010") == "+80055501010")
        #expect(CRMPhoneNumber.normalize("+2025550100") == "+2025550100")
        #expect(CRMPhoneNumber.normalize("+1 (202) 555-0100") == "+12025550100")
    }

    @Test func arbitrarySIPUsersAndShortNumbersAreNotCallerPhones() {
        for value in ["alice123", "sip:70005550101@example.invalid", "12345", "5550101", "12+34567890", "70005550101,70005550102", "70005550101 ext 7", "１２３４５６７８９０", "00000000"] {
            #expect(CRMPhoneNumber.normalize(value) == nil)
        }
    }
}
