//
//  PresentationContactTests.swift
//  TelephoneTests
//

import Testing
import UseCases

struct PresentationContactTests {
    @Test
    func doesNotRepeatPhoneNumberAsTitleAndDetail() {
        let sut = PresentationContact(
            contact: MatchedContact(
                name: "+7 985 269-35-36",
                address: .phone(
                    number: "+79852693536",
                    label: ""
                )
            )
        )

        #expect(sut.title == "+79852693536")
        #expect(sut.detail.isEmpty)
    }

    @Test
    func showsOrganizationAndAddressBelowPersonName() {
        let sut = PresentationContact(
            contact: MatchedContact(
                name: "Ivan Petrov",
                organization: "Acme",
                address: .phone(
                    number: "+79852693536",
                    label: "work"
                )
            )
        )

        #expect(sut.title == "Ivan Petrov")
        #expect(sut.detail == "work · Acme · +79852693536")
    }

    @Test
    func usesOrganizationAsTitleWhenPersonNameIsMissing() {
        let sut = PresentationContact(
            contact: MatchedContact(
                name: "",
                organization: "Acme",
                address: .phone(
                    number: "+79852693536",
                    label: ""
                )
            )
        )

        #expect(sut.title == "Acme")
        #expect(sut.detail == "+79852693536")
    }
}
