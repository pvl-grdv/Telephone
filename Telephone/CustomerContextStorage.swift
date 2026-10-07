import Foundation

// Only edited fields participate in an atomic optimistic comparison. A note
// save therefore cannot replace profile values loaded by a different window.
struct CustomerContextEdit: Sendable {
    let baseline: CustomerContextSnapshot
    let company: String?
    let keys: [String]?
    let emails: [String]?
    let note: String?

    init(baseline: CustomerContextSnapshot, company: String, keys: [String], emails: [String], note: String) {
        self.baseline = baseline
        self.company = company == baseline.company ? nil : company
        self.keys = keys == baseline.keys ? nil : keys
        self.emails = emails == baseline.emails ? nil : emails
        self.note = note == baseline.currentCallNote ? nil : note
    }

    private init(baseline: CustomerContextSnapshot, company: String?, keys: [String]?, emails: [String]?, note: String?) {
        self.baseline = baseline
        self.company = company
        self.keys = keys
        self.emails = emails
        self.note = note
    }

    // A window's own queued save may finish before its next edit. Update the
    // comparison baseline, preserving which fields that next edit touched.
    func rebased(on baseline: CustomerContextSnapshot) -> CustomerContextEdit {
        CustomerContextEdit(baseline: baseline, company: company, keys: keys, emails: emails, note: note)
    }

    var isEmpty: Bool { company == nil && keys == nil && emails == nil && note == nil }

    func conflicts(with current: CustomerContextSnapshot) -> Bool {
        (company.map { current.company != baseline.company && current.company != $0 } ?? false)
        || (keys.map { current.keys != baseline.keys && current.keys != $0 } ?? false)
        || (emails.map { current.emails != baseline.emails && current.emails != $0 } ?? false)
        || (note.map { current.currentCallNote != baseline.currentCallNote && current.currentCallNote != $0 } ?? false)
    }
}

protocol CustomerContextStoring: Sendable {
    func load(address: CustomerPartyAddress, displayName: String, accountUUID: String, callIdentifier: String) async -> CustomerContextLoadResult
    func save(address: CustomerPartyAddress, displayName: String, accountUUID: String, callIdentifier: String, edit: CustomerContextEdit) async -> CustomerContextSaveResult
}

// The UI can construct this dependency without opening SQLite on MainActor.
struct DefaultCustomerContextStorage: CustomerContextStoring {
    func load(address: CustomerPartyAddress, displayName: String, accountUUID: String, callIdentifier: String) async -> CustomerContextLoadResult {
        await CustomerContextStore.shared.load(address: address, displayName: displayName, accountUUID: accountUUID, callIdentifier: callIdentifier)
    }

    func save(address: CustomerPartyAddress, displayName: String, accountUUID: String, callIdentifier: String, edit: CustomerContextEdit) async -> CustomerContextSaveResult {
        await CustomerContextStore.shared.save(address: address, displayName: displayName, accountUUID: accountUUID, callIdentifier: callIdentifier, edit: edit)
    }
}

// Queued persistence retains this session after its window is invalidated.
// Only fields actually written by this window advance older queued edits.
// Fresh values from another window must still conflict with a stale draft.
struct CustomerContextEditSequence: Sendable {
    private(set) var generation = 0
    private var company: (Int, String)?
    private var keys: (Int, [String])?
    private var emails: (Int, [String])?
    private var note: (Int, String)?

    func rebased(_ edit: CustomerContextEdit, since savedGeneration: Int) -> CustomerContextEdit {
        var baseline = edit.baseline
        if let company, company.0 > savedGeneration { baseline.company = company.1 }
        if let keys, keys.0 > savedGeneration { baseline.keys = keys.1 }
        if let emails, emails.0 > savedGeneration { baseline.emails = emails.1 }
        if let note, note.0 > savedGeneration { baseline.currentCallNote = note.1 }
        return edit.rebased(on: baseline)
    }

    mutating func record(edit: CustomerContextEdit, saved: CustomerContextSnapshot) {
        generation += 1
        if edit.company != nil { company = (generation, saved.company) }
        if edit.keys != nil { keys = (generation, saved.keys) }
        if edit.emails != nil { emails = (generation, saved.emails) }
        if edit.note != nil { note = (generation, saved.currentCallNote) }
    }
}

// App-owned bookkeeping waits for saves even after their windows disappear.
// Tracking is synchronous with enqueue; completed tails release their tasks.
@MainActor
final class CustomerContextPendingWrites {
    private var tail: Task<Void, Never>?
    private var generation = 0

    func track(_ write: Task<Void, Never>) {
        let previous = tail
        generation += 1
        let enqueuedGeneration = generation
        tail = Task { [weak self] in
            if let previous { await previous.value }
            await write.value
            if let self, self.generation == enqueuedGeneration { self.tail = nil }
        }
    }

    func drain() async {
        while let pending = tail {
            let drainingGeneration = generation
            await pending.value
            // A write registered while awaiting the old tail also belongs to
            // this drain. Finishing an old tail cannot clear a newer one.
            if generation == drainingGeneration {
                tail = nil
                return
            }
        }
    }
}
