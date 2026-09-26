//
//  AKSIPURI.swift
//  Telephone
//
//  Swift implementation of the legacy SIP URI object.
//

import Foundation
import UseCases

@objc @implementation
extension AKSIPURI {
    public var user: String
    public var host: String
    public var displayName: String
    public var port: Int

    public var sipAddress: String {
        SIPAddress(user: user, host: host).stringValue
    }

    public class func sipURI(
        user: String,
        host: String,
        displayName: String
    ) -> Self {
        self.init(
            user: user,
            host: host,
            displayName: displayName
        )
    }

    public class func sipURI(string: String) -> Self? {
        self.init(string: string)
    }

    public init(
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

    public convenience init(
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

    public override convenience init() {
        self.init(user: "", host: "", displayName: "")
    }

    public convenience init?(string: String) {
        guard let uri = URI(string) else {
            return nil
        }

        self.init(
            user: uri.user,
            host: uri.host,
            displayName: uri.displayName
        )
    }

    public override var description: String {
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

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AKSIPURI else {
            return false
        }

        return port == other.port
            && user == other.user
            && host == other.host
            && displayName == other.displayName
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(user)
        hasher.combine(host)
        hasher.combine(displayName)
        hasher.combine(port)
        return hasher.finalize()
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        AKSIPURI(
            user: user,
            host: host,
            displayName: displayName,
            port: port
        )
    }
}
