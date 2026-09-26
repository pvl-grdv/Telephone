//
//  AKSIPAccount.swift
//  Telephone
//
//  Swift implementation of a SIP account.
//

import Foundation
import UseCases

@objc @implementation
extension AKSIPAccount {
    public weak var delegate: (any AKSIPAccountDelegate)?

    public let uuid: String
    public let uri: URI
    public let fullName: String
    private final let sipAddressValue: String

    public var SIPAddress: String {
        sipAddressValue
    }
    public let registrar: ServiceAddress
    public let realm: String
    public private(set) var username: String
    public let domain: String
    public let proxyHost: String
    public let proxyPort: UInt
    public let reregistrationTime: UInt
    public let transport: Transport
    public let usesIPv6: Bool
    public let updatesContactHeader: Bool
    public let updatesViaHeader: Bool
    public let updatesSDP: Bool

    public private(set) var identifier = -1
    public var thread: Thread?

    private let parser: AKSIPURIParser
    private var calls: [AKSIPCall] = []

    public var registered: Bool {
        get {
            registrationStatus / 100 == 2
                && registrationExpireTime != -1
        }
        set {
            guard identifier >= 0 else { return }

            if newValue {
                _ = pjsua_acc_set_registration(
                    pjsua_acc_id(identifier),
                    1
                )
                online = true
            } else {
                online = false
                _ = pjsua_acc_set_registration(
                    pjsua_acc_id(identifier),
                    0
                )
            }
        }
    }

    public var registrationStatus: Int {
        accountInfo.map { Int($0.status.rawValue) } ?? 0
    }

    public var registrationErrorCode: Int {
        accountInfo.map { Int($0.reg_last_err) } ?? 0
    }

    public var registrationStatusText: String {
        accountInfo.map { string(from: $0.status_text) } ?? ""
    }

    public var registrationExpireTime: Int {
        accountInfo.map { Int($0.expires) } ?? -1
    }

    public var online: Bool {
        get {
            accountInfo.map { $0.online_status != 0 } ?? false
        }
        set {
            guard identifier >= 0 else { return }

            _ = pjsua_acc_set_online_status(
                pjsua_acc_id(identifier),
                newValue ? 1 : 0
            )
        }
    }

    public var onlineStatusText: String {
        accountInfo.map { string(from: $0.online_status_text) } ?? ""
    }

    public var hasUnansweredIncomingCalls: Bool {
        calls.contains { call in
            call.isActive
                && call.isIncoming
                && (call.state.rawValue == 2 || call.state.rawValue == 3)
        }
    }

    @objc(initWithDictionary:parser:)
    public init(
        dictionary: [AnyHashable: Any],
        parser: AKSIPURIParser
    ) {
        let uuid = stringValue(
            dictionary[AKSIPAccountKeys.uuid]
        )
        let fullName = stringValue(
            dictionary[AKSIPAccountKeys.fullName]
        )
        let username = stringValue(
            dictionary[AKSIPAccountKeys.username]
        )
        let domain = stringValue(
            dictionary[AKSIPAccountKeys.domain]
        )

        precondition(!uuid.isEmpty)
        precondition(dictionary[AKSIPAccountKeys.fullName] != nil)
        precondition(dictionary[AKSIPAccountKeys.realm] != nil)
        precondition(dictionary[AKSIPAccountKeys.username] != nil)
        precondition(dictionary[AKSIPAccountKeys.domain] != nil)

        let configuredAddress = stringValue(
            dictionary[AKSIPAccountKeys.sipAddress]
        )
        let address = configuredAddress.isEmpty
            ? SIPAddress(user: username, host: domain)
            : SIPAddress(configuredAddress)

        let transportValue = stringValue(
            dictionary[AKSIPAccountKeys.transport]
        )
        let transport: Transport
        switch transportValue {
        case AKSIPAccountKeys.transportTCP:
            transport = .tcp
        case AKSIPAccountKeys.transportTLS:
            transport = .tls
        default:
            transport = .udp
        }

        self.uuid = uuid
        self.fullName = fullName
        self.username = username
        self.domain = domain
        self.transport = transport
        uri = URI(
            user: address.user,
            host: address.host,
            displayName: fullName,
            transport: transport
        )
        sipAddressValue = address.stringValue

        let configuredRegistrar = stringValue(
            dictionary[AKSIPAccountKeys.registrar]
        )
        registrar = ServiceAddress(
            configuredRegistrar.isEmpty
                ? domain
                : configuredRegistrar
        )

        realm = stringValue(
            dictionary[AKSIPAccountKeys.realm]
        )

        let usesProxy = boolValue(
            dictionary[AKSIPAccountKeys.useProxy]
        )
        proxyHost = usesProxy
            ? stringValue(dictionary[AKSIPAccountKeys.proxyHost])
            : ""

        let requestedProxyPort = integerValue(
            dictionary[AKSIPAccountKeys.proxyPort]
        )
        proxyPort = UInt(
            (0...65_535).contains(requestedProxyPort)
                ? requestedProxyPort
                : 0
        )

        let requestedReregistration = integerValue(
            dictionary[AKSIPAccountKeys.reregistrationTime]
        )
        switch requestedReregistration {
        case 0:
            reregistrationTime = 300
        case ..<60:
            reregistrationTime = 60
        case 3601...:
            reregistrationTime = 3_600
        default:
            reregistrationTime = UInt(requestedReregistration)
        }

        usesIPv6 = stringValue(
            dictionary[AKSIPAccountKeys.ipVersion]
        ) == AKSIPAccountKeys.ipVersion6

        updatesContactHeader = boolValue(
            dictionary[AKSIPAccountKeys.updateContactHeader]
        )
        updatesViaHeader = boolValue(
            dictionary[AKSIPAccountKeys.updateViaHeader]
        )
        updatesSDP = boolValue(
            dictionary[AKSIPAccountKeys.updateSDP]
        )

        self.parser = parser
        super.init()
    }

    public override var description: String {
        sipAddressValue
    }

    public func updateUsername(_ username: String) {
        self.username = username
    }

    public func updateIdentifier(_ identifier: Int) {
        self.identifier = identifier
    }

    @MainActor
    @objc(makeCallTo:label:)
    public func makeCall(to uri: URI, label: String) {
        NSLog("Not calling %@", uri)
    }

    @objc(makeCallTo:completion:)
    public func makeCall(
        to destination: AKSIPURI,
        completion: @escaping (AKSIPCall?) -> Void
    ) {
        guard let thread else {
            assertionFailure("SIP control thread is unavailable")
            completion(nil)
            return
        }

        let destination = URI(
            uri: destination,
            transport: transport
        )

        let request = SIPCallRequest(
            destination: destination,
            accountIdentifier: pjsua_acc_id(identifier),
            parser: parser
        ) { [weak self] info in
            guard let self, let info else {
                completion(nil)
                return
            }

            completion(addCall(info: info))
        }

        perform(
            #selector(threadMakeCall(_:)),
            on: thread,
            with: request,
            waitUntilDone: false
        )
    }

    @objc(addCallWithInfo:)
    public func addCall(info: PJSUACallInfo) -> AKSIPCall {
        if let existing = call(identifier: info.identifier) {
            return existing
        }

        let call = AKSIPCall(account: self, info: info)
        calls.append(call)
        return call
    }

    @objc(callWithIdentifier:)
    public func call(identifier: Int) -> AKSIPCall? {
        calls.first { $0.identifier == identifier }
    }

    @objc(removeCall:)
    public func remove(_ call: AKSIPCall) {
        calls.removeAll { $0 === call }
    }

    public func removeAllCalls() {
        calls.removeAll()
    }

    public func activeCallsCount() -> Int {
        calls.lazy.filter(\.isActive).count
    }

    @objc
    private final func threadMakeCall(_ request: SIPCallRequest) {
        autoreleasepool {
            var callIdentifier = pjsua_call_id(-1)

            let didMakeCall = withPJString(
                request.destination.stringValue
            ) { destination in
                pjsua_call_make_call(
                    request.accountIdentifier,
                    &destination,
                    nil,
                    nil,
                    nil,
                    &callIdentifier
                ) == 0
            }

            var snapshot: PJSUACallInfo?

            if didMakeCall {
                var info = pjsua_call_info()
                if pjsua_call_get_info(
                    callIdentifier,
                    &info
                ) == 0 {
                    snapshot = PJSUACallInfo(
                        info: info,
                        parser: request.parser
                    )
                }
            }

            DispatchQueue.main.async {
                request.completion(snapshot)
            }
        }
    }

    @nonobjc
    private final var accountInfo: pjsua_acc_info? {
        guard identifier >= 0 else {
            return nil
        }

        var info = pjsua_acc_info()
        guard pjsua_acc_get_info(
            pjsua_acc_id(identifier),
            &info
        ) == 0 else {
            return nil
        }

        return info
    }
}

private final class SIPCallRequest: NSObject, @unchecked Sendable {
    let destination: URI
    let accountIdentifier: pjsua_acc_id
    let parser: AKSIPURIParser
    let completion: @MainActor @Sendable (PJSUACallInfo?) -> Void

    init(
        destination: URI,
        accountIdentifier: pjsua_acc_id,
        parser: AKSIPURIParser,
        completion: @escaping @MainActor @Sendable (PJSUACallInfo?) -> Void
    ) {
        self.destination = destination
        self.accountIdentifier = accountIdentifier
        self.parser = parser
        self.completion = completion
    }
}

private func stringValue(_ value: Any?) -> String {
    value as? String ?? ""
}

private func integerValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let value = value as? Int {
        return value
    }
    if let value = value as? String {
        return Int(value) ?? 0
    }
    return 0
}

private func boolValue(_ value: Any?) -> Bool {
    if let number = value as? NSNumber {
        return number.boolValue
    }
    if let value = value as? Bool {
        return value
    }
    return false
}
