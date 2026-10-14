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
    @Test
    func decodesQuoteEntitiesInSIPAndContacts() {
        let sip = CallerIdentityPresentation.make(
            sipDisplayName: "ООО &quot;Синтетический-Аудит&quot;",
            callSource: "+12025550123",
            contactName: "", organization: "", label: ""
        )
        #expect(sip.primary == "ООО \"Синтетический-Аудит\"")
        #expect(sip.detail == "+12025550123")

        let contact = CallerIdentityPresentation.make(
            sipDisplayName: "", callSource: "+12025550123",
            contactName: "АО &#34;Аудит&#x22;",
            organization: "&laquo;Группа&raquo;", label: "work"
        )
        #expect(contact.primary == "АО \"Аудит\"")
        #expect(contact.detail == "«Группа» · work · +12025550123")
    }

    @Test
    func preservesRawCallSourceWhileNormalizingNames() {
        let identity = CallerIdentityPresentation.make(
            sipDisplayName: "", callSource: "sip:&quot;@example.invalid",
            contactName: "", organization: "", label: ""
        )
        #expect(identity.primary == "sip:&quot;@example.invalid")
    }

    @Test
    func normalizationIsSinglePassAndPreservesOtherEntities() {
        #expect(DisplayNameText.normalized("&amp;quot;") == "&amp;quot;")
        #expect(DisplayNameText.normalized("&lt;script&gt; &#169;") == "&lt;script&gt; &#169;")
        #expect(DisplayNameText.normalized(" &#034;X&#x00022; ") == "\"X\"")
    }

    @Test
    func phonesCompareCanonicallyWithoutMergingDistinctCompanyNames() {
        #expect(CallerIdentityPresentation.sameIdentityValue("+7 (985) 269-35-36", "89852693536"))
        #expect(!CallerIdentityPresentation.sameIdentityValue("ООО Север 12345678", "ООО Юг 12345678"))
        #expect(CallCustomerSummaryIdentity.distinctCompany(
            "ООО Север 12345678",
            displayedName: "ООО Юг 12345678", identityDetail: "+79852693536"
        ) == "ООО Север 12345678")
    }

    @Test
    func encodedCompanyDoesNotRepeatInSummaryOrPromotion() {
        #expect(CallCustomerSummaryIdentity.distinctCompany(
            "ООО &quot;Тест&quot;",
            displayedName: "ООО \"Тест\"", identityDetail: "+79852693536"
        ) == nil)
        let promoted = CallerIdentityPresentation.promotingCompany(
            "ООО &quot;Тест&quot;",
            currentPrimary: "ООО \"Тест\"", currentDetail: "+79852693536"
        )
        #expect(promoted.primary == "ООО \"Тест\"")
        #expect(promoted.detail == "+79852693536")
    }
}
