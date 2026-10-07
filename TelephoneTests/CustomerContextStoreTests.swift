import Foundation
import SQLite3
import Testing
import UseCases

@Suite @CallHistoryActor
struct CustomerContextStoreTests {
    @Test func noteOnlySaveDoesNotRestoreStaleProfileFromAnotherWindow() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let a = try fixture.load(call: "call-a")
        let b = try fixture.load(call: "call-b")
        _ = try fixture.save(call: "call-a", baseline: a, company: "Fresh company", keys: ["4200"], emails: ["fresh@example.invalid"])
        let saved = try fixture.save(call: "call-b", baseline: b, note: "Separate conversation")
        #expect(saved.company == "Fresh company")
        #expect(saved.keys == ["4200"])
        #expect(saved.emails == ["fresh@example.invalid"])
        #expect(saved.currentCallNote == "Separate conversation")
    }

    @Test func disjointProfileEditsMergeDespiteStaleWindowSnapshot() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let a = try fixture.load(call: "a")
        let b = try fixture.load(call: "b")
        _ = try fixture.save(call: "a", baseline: a, company: "Fresh company")
        let saved = try fixture.save(call: "b", baseline: b, keys: ["4200"])
        #expect(saved.company == "Fresh company")
        #expect(saved.keys == ["4200"])
    }

    @Test func overlappingProfileEditsRejectWholePatchAndPreserveDraftNote() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let a = try fixture.load(call: "a")
        let b = try fixture.load(call: "b")
        _ = try fixture.save(call: "a", baseline: a, company: "First")
        let edit = CustomerContextEdit(baseline: b, company: "Second", keys: ["999"], emails: [], note: "Draft")
        let result = fixture.store.save(address: fixture.address, displayName: "", accountUUID: "account", callIdentifier: "b", edit: edit)
        guard case .conflict(let current) = result else { Issue.record("Expected stale edit conflict"); return }
        #expect(current.company == "First")
        #expect(current.keys.isEmpty)
        #expect(current.currentCallNote.isEmpty)
        let persisted = try fixture.load(call: "b")
        #expect(persisted.company == "First" && persisted.keys.isEmpty && persisted.currentCallNote.isEmpty)
    }

    @Test func notesInTwoWindowsOfSameConversationCannotSilentlyOverwrite() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let a = try fixture.load(call: "a")
        let b = try fixture.load(call: "a")
        _ = try fixture.save(call: "a", baseline: a, note: "First note")
        let edit = CustomerContextEdit(baseline: b, company: "", keys: [], emails: [], note: "Second note")
        guard case .conflict(let current) = fixture.store.save(address: fixture.address, displayName: "", accountUUID: "account", callIdentifier: "a", edit: edit) else {
            Issue.record("Expected same-call note conflict"); return
        }
        #expect(current.currentCallNote == "First note")
    }

    @Test func accountScopeSeparatesIdenticalCallIdentifiers() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let a = try fixture.load(call: "same", account: "a")
        let b = try fixture.load(call: "same", account: "b")
        _ = try fixture.save(call: "same", account: "a", baseline: a, note: "A note")
        _ = try fixture.save(call: "same", account: "b", baseline: b, note: "B note")
        let savedA = try fixture.load(call: "same", account: "a")
        let savedB = try fixture.load(call: "same", account: "b")
        #expect(savedA.currentCallNote == "A note")
        #expect(savedB.currentCallNote == "B note")
        _ = try fixture.save(call: "same", account: "a", baseline: savedA, note: "")
        #expect(try fixture.load(call: "same", account: "a").currentCallNote.isEmpty)
        #expect(try fixture.load(call: "same", account: "b").currentCallNote == "B note")
    }

    @Test func notePrecedesHistoryAndRetainsExplicitIdentityAfterHistoryDeletion() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let initial = try fixture.load(call: "stable")
        _ = try fixture.save(call: "stable", baseline: initial, note: "During the call")
        #expect(try fixture.scalar("SELECT COUNT(*) FROM party_notes WHERE account_uuid='account' AND call_identifier='stable'") == 1)
        try fixture.connection.execute("CREATE TABLE calls(account_uuid TEXT, identifier TEXT, party_id INTEGER, duration INTEGER, date REAL, PRIMARY KEY(account_uuid,identifier))")
        try fixture.connection.execute("INSERT INTO calls SELECT 'account','stable',id,12,100 FROM parties")
        #expect(try fixture.scalar("SELECT COUNT(*) FROM calls JOIN party_notes ON calls.account_uuid=party_notes.account_uuid AND calls.identifier=party_notes.call_identifier") == 1)
        try fixture.connection.execute("DELETE FROM calls")
        #expect(try fixture.scalar("SELECT COUNT(*) FROM party_notes") == 1)
        let nextConversation = try fixture.load(call: "next")
        #expect(nextConversation.currentCallNote.isEmpty)
        #expect(nextConversation.recentNotes.map(\.body) == ["During the call"])
    }

    @Test func legacyMigrationRetainsNotesWithoutGuessingAccountOrCallJoin() throws {
        let fixture = try CustomerStoreFixture(legacy: true)
        defer { fixture.cleanup() }
        let result = try fixture.load(call: "old-random-uuid")
        #expect(result.currentCallNote.isEmpty)
        #expect(result.recentNotes.first?.body == "Historical note")
        #expect(result.recentNotes.first?.id == 31)
        #expect(result.recentNotes.first?.updatedAt == Date(timeIntervalSinceReferenceDate: 22))
        #expect(try fixture.scalar("SELECT COUNT(*) FROM party_notes WHERE account_uuid='' AND call_identifier='old-random-uuid'") == 1)
        _ = try fixture.save(call: "old-random-uuid", baseline: result, note: "New explicitly identified note")
        #expect(try fixture.scalar("SELECT COUNT(*) FROM party_notes") == 2)
    }

    @Test func identicalSubmittedValueIsIdempotentAndUntouchedValuesStayAbsent() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let baseline = try fixture.load(call: "a")
        _ = try fixture.save(call: "a", baseline: baseline, company: "Company", keys: ["1"])
        let second = try fixture.save(call: "a", baseline: baseline, company: "Company", keys: ["1"])
        #expect(second.company == "Company" && second.keys == ["1"])
        let notePatch = CustomerContextEdit(baseline: second, company: second.company, keys: second.keys, emails: second.emails, note: "Note")
        #expect(notePatch.company == nil && notePatch.keys == nil && notePatch.emails == nil)
    }

    @Test func queuedEditRebasesOnlyTouchedFields() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let original = try fixture.load(call: "a")
        let queued = CustomerContextEdit(baseline: original, company: "", keys: [], emails: [], note: "Second note")
        let saved = try fixture.save(call: "a", baseline: original, company: "Company", note: "First note")
        let rebased = queued.rebased(on: saved)
        #expect(rebased.company == nil && rebased.keys == nil && rebased.emails == nil)
        guard case .success(let final) = fixture.store.save(address: fixture.address, displayName: "", accountUUID: "account", callIdentifier: "a", edit: rebased) else {
            Issue.record("Expected serialized edit to save"); return
        }
        #expect(final.company == "Company" && final.currentCallNote == "Second note")
    }

    @Test func queuedProfileEditDoesNotSilentlyAcceptAnotherWindowsChangeFromANoteSave() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let initial = try fixture.load(call: "a")
        let note = CustomerContextEdit(baseline: initial, company: "", keys: [], emails: [], note: "Note")
        let queuedProfile = CustomerContextEdit(baseline: initial, company: "Second company", keys: [], emails: [], note: "")
        var sequence = CustomerContextEditSequence()
        let generation = sequence.generation
        // Another window edits company before this window's note save.
        _ = try fixture.save(call: "b", baseline: initial, company: "First company")
        guard case .success(let noteSaved) = fixture.store.save(address: fixture.address, displayName: "", accountUUID: "account", callIdentifier: "a", edit: note) else {
            Issue.record("Expected note save"); return
        }
        sequence.record(edit: note, saved: noteSaved)
        let rebased = sequence.rebased(queuedProfile, since: generation)
        #expect(rebased.baseline.company.isEmpty)
        #expect(rebased.baseline.currentCallNote == "Note")
        guard case .conflict(let actual) = fixture.store.save(address: fixture.address, displayName: "", accountUUID: "account", callIdentifier: "a", edit: rebased) else {
            Issue.record("Expected queued profile edit to conflict"); return
        }
        #expect(actual.company == "First company" && actual.currentCallNote == "Note")
    }

    @Test func reopeningPreservesProfileAndExplicitConversationNote() throws {
        let fixture = try CustomerStoreFixture()
        defer { fixture.cleanup() }
        let initial = try fixture.load(call: "a")
        _ = try fixture.save(call: "a", baseline: initial, company: "Company", keys: ["1"], note: "Persistent note")
        let reopened = try CustomerContextStore(databaseURL: fixture.url)
        guard case .success(let result) = reopened.load(address: fixture.address, displayName: "", accountUUID: "account", callIdentifier: "a") else {
            Issue.record("Expected reopened data"); return
        }
        #expect(result.company == "Company" && result.keys == ["1"] && result.currentCallNote == "Persistent note")
    }
}

@CallHistoryActor
private struct CustomerStoreFixture {
    let directory: URL
    let url: URL
    let connection: SQLiteConnection
    let store: CustomerContextStore
    let address = CustomerPartyAddress(user: "+70005550123", host: "")

    init(legacy: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TelephoneCustomerStoreTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("Telephone.sqlite3")
        connection = try SQLiteConnectionPool.shared.connection(at: url)
        if legacy {
            try TelephoneDatabaseSchema.createPartyTables(execute: connection.execute)
            try connection.execute("CREATE TABLE party_notes(id INTEGER PRIMARY KEY,party_id INTEGER NOT NULL,call_identifier TEXT NOT NULL,body TEXT NOT NULL,created_at REAL NOT NULL,updated_at REAL NOT NULL,FOREIGN KEY(party_id) REFERENCES parties(id) ON DELETE CASCADE,UNIQUE(party_id,call_identifier))")
            try connection.execute("INSERT INTO parties(id,display_name) VALUES (1,'Legacy')")
            try connection.execute("INSERT INTO party_addresses(party_id,kind,value,normalized_value) VALUES (1,'phone','+70005550123','70005550123')")
            try connection.execute("INSERT INTO party_notes VALUES (31,1,'old-random-uuid','Historical note',11,22)")
            try connection.execute("PRAGMA user_version=3")
        }
        store = try CustomerContextStore(databaseURL: url)
    }

    func load(call: String, account: String = "account") throws -> CustomerContextSnapshot {
        guard case .success(let snapshot) = store.load(address: address, displayName: "", accountUUID: account, callIdentifier: call) else {
            throw SQLiteStoreError.sqlite("Expected customer snapshot")
        }
        return snapshot
    }

    func save(call: String, account: String = "account", baseline: CustomerContextSnapshot, company: String? = nil, keys: [String]? = nil, emails: [String]? = nil, note: String? = nil) throws -> CustomerContextSnapshot {
        let edit = CustomerContextEdit(baseline: baseline, company: company ?? baseline.company, keys: keys ?? baseline.keys, emails: emails ?? baseline.emails, note: note ?? baseline.currentCallNote)
        guard case .success(let snapshot) = store.save(address: address, displayName: "", accountUUID: account, callIdentifier: call, edit: edit) else {
            throw SQLiteStoreError.sqlite("Expected customer save")
        }
        return snapshot
    }

    func scalar(_ sql: String) throws -> Int {
        let statement = try connection.prepare(sql)
        guard statement.step() == SQLITE_ROW else { throw SQLiteStoreError.sqlite("Expected scalar") }
        return Int(statement.int64(at: 0))
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
struct CustomerContextPendingWritesTests {
    @Test func drainRetainsHeldWriteAfterWindowOwnerGoesAway() async {
        let writes = CustomerContextPendingWrites()
        let gate = HeldCustomerWriteGate()
        let probe = CustomerWriteProbe()
        let write = Task {
            await gate.wait()
            probe.saved = true
        }
        writes.track(write)
        let draining = Task {
            await writes.drain()
            probe.drained = true
        }
        await gate.waitUntilStarted()
        await Task.yield()
        #expect(!probe.saved && !probe.drained)
        await gate.release()
        await draining.value
        #expect(probe.saved && probe.drained)
    }

    @Test func drainIncludesWriteTrackedWhileItWaitsForEarlierTail() async {
        let writes = CustomerContextPendingWrites()
        let firstGate = HeldCustomerWriteGate()
        let secondGate = HeldCustomerWriteGate()
        let probe = CustomerWriteProbe()
        let first = Task { await firstGate.wait() }
        writes.track(first)
        let draining = Task {
            await writes.drain()
            probe.drained = true
        }
        await firstGate.waitUntilStarted()
        await Task.yield()
        let second = Task {
            await secondGate.wait()
            probe.saved = true
        }
        writes.track(second)
        await secondGate.waitUntilStarted()
        await firstGate.release()
        await first.value
        await Task.yield()
        #expect(!probe.saved && !probe.drained)
        await secondGate.release()
        await draining.value
        #expect(probe.saved && probe.drained)
    }
}

@MainActor
private final class CustomerWriteProbe {
    var saved = false
    var drained = false
}

private actor HeldCustomerWriteGate {
    private var started = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            started = true
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
