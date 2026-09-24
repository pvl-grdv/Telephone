//
//  CallerIdentityPresentationTests.swift
//  TelephoneTests
//

import Testing

struct CallerIdentityPresentationTests {
    @Test
    func usesOnePhoneNumberWhenSIPDisplayNameRepeatsIt() {
        let sut = CallerIdentityPresentation.make(
            sipDisplayName: "+7 985 269-35-36",
            callSource: "+79852693536",
            contactName: "",
            organization: "",
            label: ""
        )

        #expect(sut.primary == "+79852693536")
        #expect(sut.detail.isEmpty)
    }

    @Test
    func prefersContactThenShowsOrganizationLabelAndNumber() {
        let sut = CallerIdentityPresentation.make(
            sipDisplayName: "",
            callSource: "+79852693536",
            contactName: "Ivan Petrov",
            organization: "Acme",
            label: "work"
        )

        #expect(sut.primary == "Ivan Petrov")
        #expect(sut.detail == "Acme · work · +79852693536")
    }

    @Test
    func fallsBackToOrganizationBeforePhoneNumber() {
        let sut = CallerIdentityPresentation.make(
            sipDisplayName: "+79852693536",
            callSource: "+79852693536",
            contactName: "",
            organization: "Acme",
            label: ""
        )

        #expect(sut.primary == "Acme")
        #expect(sut.detail == "+79852693536")
    }

    @Test
    func crmCompanyBecomesPrimaryWithoutRepeatingExistingCompany() {
        let sut = CallerIdentityPresentation.promotingCompany(
            "Acme",
            currentPrimary: "Ivan Petrov",
            currentDetail: "Acme · work · +79852693536"
        )

        #expect(sut.primary == "Acme")
        #expect(sut.detail == "Ivan Petrov · work · +79852693536")
    }

    @Test
    func usesMeaningfulSIPDisplayNameWithoutContactsMatch() {
        let sut = CallerIdentityPresentation.make(
            sipDisplayName: "Support Queue",
            callSource: "+79852693536",
            contactName: "",
            organization: "",
            label: ""
        )

        #expect(sut.primary == "Support Queue")
        #expect(sut.detail == "+79852693536")
    }
}
