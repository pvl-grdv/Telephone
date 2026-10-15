//
//  TelephoneDatabaseSchema.swift
//  Telephone
//

/// The only persisted Telephone data is call history (including the legacy
/// import marker). CRM inventories and local customer drafts are not stored.
enum TelephoneDatabaseSchema {
    static let currentVersion = 6

    /// Purge all legacy Telephone-only customer data. This is deliberate:
    /// saved profiles, keys, emails and notes have been retired and are not
    /// synchronized with CRM. The caller's normal history is preserved.
    static func removeRetiredTables(execute: (String) throws -> Void) throws {
        for name in [
            "party_notes", "party_keys", "party_addresses",
            "legacy_party_notes", "parties",
            "call_crm_snapshots", "party_attributes", "external_refs",
            "crm_sync_state"
        ] {
            try execute("DROP TABLE IF EXISTS \(name)")
        }
    }
}
