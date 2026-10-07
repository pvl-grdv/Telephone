//
//  SIPURISnapshot.swift
//  Telephone
//
//  Immutable URI fields copied before a PJSIP callback returns.
//

struct SIPURISnapshot: Sendable, Equatable {
    let user: String
    let host: String
    let displayName: String
    let port: Int

    init(_ uri: AKSIPURI?) {
        user = uri?.user ?? ""
        host = uri?.host ?? ""
        displayName = uri?.displayName ?? ""
        port = uri?.port ?? 0
    }

    // Each consuming call owns its legacy mutable URI. No object is shared
    // with the callback parser or another consumer of the snapshot.
    func makeURI() -> AKSIPURI {
        AKSIPURI(
            user: user,
            host: host,
            displayName: displayName,
            port: port
        )
    }
}
