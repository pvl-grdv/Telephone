//
//  AKSIPCall.swift
//  Telephone
//
//  Swift implementation of a PJSIP call.
//

import Foundation
import UseCases

@objc @implementation
extension AKSIPCall {
    public let account: AKSIPAccount
    public var identifier: Int

    public weak var delegate: (any AKSIPCallDelegate)? {
        didSet {
            if let oldValue {
                unsubscribe(oldValue, from: self)
            }
            if let delegate {
                subscribe(delegate, to: self)
            }
        }
    }

    public var state: AKSIPCallState
    public var stateText: String
    public var lastStatus: Int
    public var lastStatusText: String
    public var transferStatus = -1
    public var transferStatusText = ""
    public var duration = 0

    public let date: Date
    public let localURI: AKSIPURI
    public let remoteURI: AKSIPURI

    private final let incomingState: Bool
    private final var missedState: Bool

    public var incoming: Bool {
        @objc(isIncoming) get { incomingState }
    }

    public var missed: Bool {
        @objc(isMissed) get { missedState }
        set { missedState = newValue }
    }

    public var remote: URI {
        URI(remoteURI)
    }

    public var active: Bool {
        @objc(isActive) get {
        guard identifier >= 0 else { return false }
            return pjsua_call_is_active(pjsua_call_id(identifier)) != 0
        }
    }

    public var confirmed: Bool {
        @objc(confirmed) get { state.rawValue == 5 }
    }

    private final var microphoneMutedState = false

    public var microphoneMuted: Bool {
        @objc(microphoneMuted) get { microphoneMutedState }
        set { microphoneMutedState = newValue }
    }

    public var onLocalHold: Bool {
        @objc(onLocalHold) get { mediaStatusRawValue == 2 }
    }

    public var onRemoteHold: Bool {
        @objc(onRemoteHold) get { mediaStatusRawValue == 3 }
    }

    public var incomingIdentityHeaders: [String: String]

    @objc(initWithSIPAccount:info:)
    public init(
        account: AKSIPAccount,
        info: PJSUACallInfo
    ) {
        self.account = account
        identifier = info.identifier
        state = info.state
        stateText = info.stateText
        lastStatus = info.lastStatus
        lastStatusText = info.lastStatusText
        date = Date()
        localURI = info.localURI
        remoteURI = info.remoteURI
        incomingState = info.isIncoming
        missedState = info.isIncoming
        incomingIdentityHeaders = [:]
        super.init()
    }

    deinit {
        if let delegate {
            unsubscribe(delegate, from: self)
        }
    }

    public override var description: String {
        "\(localURI) <=> \(remoteURI)"
    }

    public func answer() {
        let status = pjsua_call_answer(
            pjsua_call_id(identifier),
            200,
            nil,
            nil
        )

        if status == 0 {
            missed = false
        } else {
            NSLog("Error answering call %@", self)
        }
    }

    public func hangUp() {
        guard identifier >= 0, state.rawValue != 6 else {
            return
        }

        let status = pjsua_call_hangup(
            pjsua_call_id(identifier),
            0,
            nil,
            nil
        )

        if status == 0 {
            missed = false
        } else {
            NSLog("Error hanging up call %@", self)
        }
    }

    @objc(attendedTransferToCall:)
    public func attendedTransfer(to destinationCall: AKSIPCall) {
        transferStatus = -1
        transferStatusText = ""

        let status = pjsua_call_xfer_replaces(
            pjsua_call_id(identifier),
            pjsua_call_id(destinationCall.identifier),
            1,
            nil
        )

        if status != 0 {
            NSLog("Error transferring call %@", self)
        }
    }

    public func sendRingingNotification() {
        let status = pjsua_call_answer(
            pjsua_call_id(identifier),
            180,
            nil,
            nil
        )

        if status != 0 {
            NSLog("Error sending ringing notification in call %@", self)
        }
    }

    public func replyWithTemporarilyUnavailable() {
        if pjsua_call_answer(
            pjsua_call_id(identifier),
            480,
            nil,
            nil
        ) != 0 {
            NSLog("Error replying with 480 Temporarily Unavailable")
        }
    }

    public func replyWithBusyHere() {
        if pjsua_call_answer(
            pjsua_call_id(identifier),
            486,
            nil,
            nil
        ) != 0 {
            NSLog("Error replying with 486 Busy Here")
        }
    }

    @objc(sendDTMFDigits:)
    public func sendDTMF(_ digits: String) {
        let status = withPJString(digits) { pjDigits in
            pjsua_call_dial_dtmf(
                pjsua_call_id(identifier),
                &pjDigits
            )
        }

        guard status != 0 else {
            return
        }

        for digit in digits {
            sendInfoDTMF(digit)
        }
    }

    public func setMuted(_ muted: Bool) {
        if muted {
            muteMicrophone()
        } else {
            unmuteMicrophone()
        }
    }

    public func setHeld(_ held: Bool) {
        if held {
            hold()
        } else {
            unhold()
        }
    }

    public func toggleMicrophoneMute() {
        setMuted(!microphoneMuted)
    }

    public func toggleHold() {
        setHeld(!onLocalHold)
    }

    @nonobjc
    private final var mediaStatusRawValue: UInt32? {
        guard let media = firstMediaInfo() else {
            return nil
        }

        return media.status.rawValue
    }

    @nonobjc
    private final func firstMediaInfo() -> pjsua_call_media_info? {
        guard identifier >= 0 else {
            return nil
        }

        var info = pjsua_call_info()
        guard pjsua_call_get_info(
            pjsua_call_id(identifier),
            &info
        ) == 0 else {
            return nil
        }

        let media: [pjsua_call_media_info] = Array(tuple: info.media)
        return media.first
    }

    @nonobjc
    private final func muteMicrophone() {
        guard !microphoneMuted, confirmed else {
            return
        }

        guard let media = firstMediaInfo() else {
            return
        }

        if pjsua_conf_disconnect(
            0,
            media.stream.aud.conf_slot
        ) == 0 {
            microphoneMuted = true
        } else {
            NSLog("Error muting microphone in call %@", self)
        }
    }

    @nonobjc
    private final func unmuteMicrophone() {
        guard isMicrophoneMuted, confirmed else {
            return
        }

        guard let media = firstMediaInfo() else {
            return
        }

        if pjsua_conf_connect(
            0,
            media.stream.aud.conf_slot
        ) == 0 {
            microphoneMuted = false
        } else {
            NSLog("Error unmuting microphone in call %@", self)
        }
    }

    @nonobjc
    private final func hold() {
        guard confirmed, !onRemoteHold else {
            return
        }

        _ = pjsua_call_set_hold(
            pjsua_call_id(identifier),
            nil
        )
    }

    @nonobjc
    private final func unhold() {
        guard confirmed else {
            return
        }

        _ = pjsua_call_reinvite(
            pjsua_call_id(identifier),
            1,
            nil
        )
    }

    @nonobjc
    private final func sendInfoDTMF(_ digit: Character) {
        let messageBody = "Signal=\(digit)\r\nDuration=300"

        withPJString("INFO") { method in
            withPJString("application/dtmf-relay") { contentType in
                withPJString(messageBody) { body in
                    var message = pjsua_msg_data()
                    pjsua_msg_data_init(&message)
                    message.content_type = contentType
                    message.msg_body = body

                    if pjsua_call_send_request(
                        pjsua_call_id(identifier),
                        &method,
                        &message
                    ) != 0 {
                        NSLog("Error sending DTMF")
                    }
                }
            }
        }
    }
}

private let callDelegateSubscriptions: [(Selector, Notification.Name)] = [
    (NSSelectorFromString("SIPCallCalling:"), .AKSIPCallCalling),
    (NSSelectorFromString("SIPCallIncoming:"), .AKSIPCallIncoming),
    (NSSelectorFromString("SIPCallEarly:"), .AKSIPCallEarly),
    (NSSelectorFromString("SIPCallConnecting:"), .AKSIPCallConnecting),
    (NSSelectorFromString("SIPCallDidConfirm:"), .AKSIPCallDidConfirm),
    (NSSelectorFromString("SIPCallDidDisconnect:"), .AKSIPCallDidDisconnect),
    (
        NSSelectorFromString("SIPCallMediaDidBecomeActive:"),
        .AKSIPCallMediaDidBecomeActive
    ),
    (NSSelectorFromString("SIPCallDidLocalHold:"), .AKSIPCallDidLocalHold),
    (NSSelectorFromString("SIPCallDidRemoteHold:"), .AKSIPCallDidRemoteHold),
    (
        NSSelectorFromString("SIPCallTransferStatusDidChange:"),
        .AKSIPCallTransferStatusDidChange
    ),
]

private func subscribe(
    _ delegate: any AKSIPCallDelegate,
    to call: AKSIPCall
) {
    let center = NotificationCenter.default

    for (selector, name) in callDelegateSubscriptions
    where delegate.responds(to: selector) {
        center.addObserver(
            delegate,
            selector: selector,
            name: name,
            object: call
        )
    }
}

private func unsubscribe(
    _ delegate: any AKSIPCallDelegate,
    from call: AKSIPCall
) {
    NotificationCenter.default.removeObserver(
        delegate,
        name: nil,
        object: call
    )
}
