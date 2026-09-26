//
//  AKSIPURI.swift
//  Telephone
//
//  Swift implementation of the legacy SIP URI object.
//

import Foundation
import UseCases

final class AKSIPURI: NSObject, NSCopying {
    var user: String
    var host: String
    var displayName: String
    var port: Int

    var sipAddress: String {
        SIPAddress(user: user, host: host).stringValue
    }

    static func sipURI(
        user: String,
        host: String,
        displayName: String
    ) -> AKSIPURI {
        AKSIPURI(
            user: user,
            host: host,
            displayName: displayName
        )
    }

    static func sipURI(string: String) -> AKSIPURI? {
        AKSIPURI(string: string)
    }

    init(
        user: String,
        host: String,
        displayName: String,
        port: Int
    ) {
        self.user = user
        self.host = host
        self.displayName = displayName
        self.port = port
        super.init()
    }

    convenience init(
        user: String,
        host: String,
        displayName: String
    ) {
        self.init(
            user: user,
            host: host,
            displayName: displayName,
            port: 0
        )
    }

    override convenience init() {
        self.init(user: "", host: "", displayName: "")
    }

    convenience init?(string: String) {
        guard let uri = URI(string) else {
            return nil
        }

        self.init(
            user: uri.user,
            host: uri.host,
            displayName: uri.displayName
        )
    }

    override var description: String {
        let address = ServiceAddress(
            host: host,
            port: port > 0 ? String(port) : ""
        )

        return URI(
            user: user,
            address: address,
            displayName: displayName,
            transport: .udp
        ).stringValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AKSIPURI else {
            return false
        }

        return port == other.port
            && user == other.user
            && host == other.host
            && displayName == other.displayName
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(user)
        hasher.combine(host)
        hasher.combine(displayName)
        hasher.combine(port)
        return hasher.finalize()
    }

    func copy(with zone: NSZone? = nil) -> Any {
        AKSIPURI(
            user: user,
            host: host,
            displayName: displayName,
            port: port
        )
    }
}
