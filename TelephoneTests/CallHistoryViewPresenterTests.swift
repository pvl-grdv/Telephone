//
//  CallHistoryViewPresenterTests.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import UseCases
import UseCasesTestDoubles
import XCTest

@MainActor
final class CallHistoryViewPresenterTests: XCTestCase {
    func testShowsRecordsOnRecordsUpdate() async {
        let factory = CallHistoryRecordTestFactory()
        let record1 = factory.makeRecord(number: 1)
        let record2 = factory.makeRecord(number: 2)
        let contact1 = makeContact(number: 1)
        let contact2 = makeContact(number: 2)
        let didCallShow = expectation(description: "Did call show on view")
        var invokedRecords: [PresentationCallHistoryRecord]?
        let view = CallHistoryViewSpy { records in
            invokedRecords = records
            didCallShow.fulfill()
        }
        let sut = CallHistoryViewPresenter(
            view: view, dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter()
        )
        let expected1 = makePresentationCallHistoryRecord(contact: contact1, record: record1)
        let expected2 = makePresentationCallHistoryRecord(contact: contact2, record: record2)

        await sut.update(
            records: [
                ContactCallHistoryRecord(origin: record1, contact: contact1),
                ContactCallHistoryRecord(origin: record2, contact: contact2)
            ]
        )

        await fulfillment(of: [didCallShow], timeout: 1)
        XCTAssertEqual(invokedRecords, [expected1, expected2])
    }

    func testMissedStateIsPreserved() async {
        let record = CallHistoryRecord(
            uri: URI(user: "any-user", host: "any-host", displayName: "any-name"),
            date: Date(),
            duration: 0,
            isIncoming: false,
            isMissed: true
        )
        let contact = makeContact(number: 1)
        let didCallShow = expectation(description: "Did call show on view")
        var invokedRecords: [PresentationCallHistoryRecord]?
        let view = CallHistoryViewSpy { records in
            invokedRecords = records
            didCallShow.fulfill()
        }
        let sut = CallHistoryViewPresenter(
            view: view, dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter()
        )

        await sut.update(records: [ContactCallHistoryRecord(origin: record, contact: contact)])

        await fulfillment(of: [didCallShow], timeout: 1)
        XCTAssertTrue(invokedRecords!.first!.isMissed)
    }

    func testTitleIsEmailAddressOrPhoneNumberAndTooltipIsEmptyWhenNameIsEmpty() async {
        let factory = CallHistoryRecordTestFactory()
        let record1 = factory.makeRecord(number: 1)
        let record2 = factory.makeRecord(number: 2)
        let address = "any-address"
        let number = "any-number"
        let contact1 = MatchedContact(name: "", address: .email(address: address, label: "any-label-1"))
        let contact2 = MatchedContact(name: "", address: .phone(number: number, label: "any-label-2"))
        let didCallShow = expectation(description: "Did call show on view")
        var invokedRecords: [PresentationCallHistoryRecord]?
        let view = CallHistoryViewSpy { records in
            invokedRecords = records
            didCallShow.fulfill()
        }
        let sut = CallHistoryViewPresenter(
            view: view, dateFormatter: ShortRelativeDateTimeFormatter(), durationFormatter: DurationFormatter()
        )

        await sut.update(
            records: [
                ContactCallHistoryRecord(origin: record1, contact: contact1),
                ContactCallHistoryRecord(origin: record2, contact: contact2)
            ]
        )

        await fulfillment(of: [didCallShow], timeout: 1)
        XCTAssertEqual(invokedRecords![0].contact.title, address)
        XCTAssertTrue(invokedRecords![0].contact.tooltip.isEmpty)
        XCTAssertEqual(invokedRecords![1].contact.title, number)
        XCTAssertTrue(invokedRecords![1].contact.tooltip.isEmpty)
    }

    func testPresentationContactDetailCombinesLabelAndTooltip() {
        let contact = PresentationContact(
            title: "Alice",
            tooltip: "+1 555 123 4567",
            label: "Mobile",
            address: "+1 555 123 4567"
        )

        XCTAssertEqual(contact.detail, "Mobile · +1 555 123 4567")
    }

    func testCallHistorySearchIgnoresPhoneNumberFormatting() {
        let contact = PresentationContact(
            title: "Alice",
            tooltip: "+1 (555) 123-4567",
            label: "Mobile",
            address: "+1 (555) 123-4567"
        )
        let record = PresentationCallHistoryRecord(
            identifier: "any",
            contact: contact,
            date: "Today, 12:00",
            duration: "1 min",
            isIncoming: true,
            isMissed: false
        )

        XCTAssertTrue(record.matchesSearch("5551234567"))
        XCTAssertTrue(record.matchesSearch("+1 555 123"))
        XCTAssertFalse(record.matchesSearch("Alice 555"))
    }

    func testCustomerPartyAddressNormalizesPhoneFormatting() {
        let formatted = CustomerPartyAddress(
            user: "+1 (555) 123-4567",
            host: "example.com"
        )
        let plain = CustomerPartyAddress(
            user: "15551234567",
            host: "another.example"
        )

        XCTAssertEqual(formatted.kind, "phone")
        XCTAssertEqual(formatted.normalizedValue, plain.normalizedValue)
    }

    func testCustomerPartyAddressNormalizesSIPAddress() {
        let address = CustomerPartyAddress(
            user: "Sales",
            host: "Example.COM"
        )

        XCTAssertEqual(address.kind, "sip")
        XCTAssertEqual(address.normalizedValue, "sales@example.com")
    }

    func testCustomerPartyAddressKeepsShortNumericSIPExtensionScopedToHost() {
        let first = CustomerPartyAddress(user: "1234", host: "pbx.example.com")
        let second = CustomerPartyAddress(user: "1234", host: "other.example.com")

        XCTAssertEqual(first.kind, "sip")
        XCTAssertNotEqual(first.normalizedValue, second.normalizedValue)
    }

    func testCustomerPartyAddressNormalizesEmail() {
        let address = CustomerPartyAddress(
            email: " Sales@Example.COM "
        )

        XCTAssertEqual(address.kind, "email")
        XCTAssertEqual(address.normalizedValue, "sales@example.com")
    }

    func testCallHistoryFiltersMatchExpectedRecords() {
        let contact = PresentationContact(
            title: "Any",
            tooltip: "",
            label: "",
            address: "123"
        )
        let missed = PresentationCallHistoryRecord(
            identifier: "missed",
            contact: contact,
            date: "",
            duration: "",
            isIncoming: true,
            isMissed: true
        )
        let incoming = PresentationCallHistoryRecord(
            identifier: "incoming",
            contact: contact,
            date: "",
            duration: "",
            isIncoming: true,
            isMissed: false
        )
        let outgoing = PresentationCallHistoryRecord(
            identifier: "outgoing",
            contact: contact,
            date: "",
            duration: "",
            isIncoming: false,
            isMissed: false
        )

        XCTAssertTrue(CallHistoryFilter.all.matches(missed))
        XCTAssertTrue(CallHistoryFilter.missed.matches(missed))
        XCTAssertTrue(CallHistoryFilter.incoming.matches(missed))
        XCTAssertTrue(CallHistoryFilter.incoming.matches(incoming))
        XCTAssertTrue(CallHistoryFilter.outgoing.matches(outgoing))
        XCTAssertFalse(CallHistoryFilter.missed.matches(incoming))
        XCTAssertFalse(CallHistoryFilter.outgoing.matches(incoming))
    }


}

private func makeContact(number: Int) -> MatchedContact {
    return MatchedContact(
        name: "any-name-\(number)", address: .email(address: "any-address\(number)", label: "any-label-\(number)")
    )
}

private func makePresentationCallHistoryRecord(contact: MatchedContact, record: CallHistoryRecord) -> PresentationCallHistoryRecord {
    return PresentationCallHistoryRecord(
        identifier: record.identifier,
        contact: makePresentationContact(contact: contact),
        date: ShortRelativeDateTimeFormatter().string(from: record.date),
        duration: DurationFormatter().string(from: TimeInterval(record.duration))!,
        isIncoming: record.isIncoming,
        isMissed: record.isMissed
    )
}

private func makePresentationContact(contact: MatchedContact) -> PresentationContact {
    switch contact.address {
    case let .phone(number, label):
        return PresentationContact(title: contact.name, tooltip: number, label: label, address: number)
    case let .email(address, label):
        return PresentationContact(title: contact.name, tooltip: address, label: label, address: address)
    }
}
