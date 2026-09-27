//
//  AKSIPCall.swift
//  Telephone
//
//  Swift implementation of a PJSIP call.
//

import Foundation
import UseCases

final class AKSIPCall: NSObject, Call, @unchecked Sendable {
    let sipAccount: AKSIPAccount
    var account: any Account { sipAccount }
    var identifier: Int

    weak var delegate: (any AKSIPCallDelegate)?

    var state: AKSIPCallState
    var stateText: String
    var lastStatus: Int
    var lastStatusText: String
    var transferStatus = -1
    var transferStatusText = ""
    var duration = 0

    let date: Date
    let localURI: AKSIPURI
    let remoteURI: AKSIPURI

    private final let incomingValue: Bool
    private final var missedValue: Bool
    private final var microphoneMutedValue = false

    var isIncoming: Bool {
        incomingValue
    }

    var isMissed: Bool {
        get { missedValue }
        set { missedValue = newValue }
    }

    var remote: URI {
        URI(remoteURI)
    }

    var isActive: Bool {
        guard identifier != kAKSIPUserAgentInvalidIdentifier else { return false }
        return pjsua_call_is_active(pjsua_call_id(identifier)) != 0
    }

    var isConfirmed: Bool {
        state == PJSIP_INV_STATE_CONFIRMED
    }

    var isMicrophoneMuted: Bool {
        get { microphoneMutedValue }
        set { microphoneMutedValue = newValue }
    }

    var isOnLocalHold: Bool {
        mediaStatus == PJSUA_CALL_MEDIA_LOCAL_HOLD
    }

    var isOnRemoteHold: Bool {
        mediaStatus == PJSUA_CALL_MEDIA_REMOTE_HOLD
    }

    var incomingIdentityHeaders: [String: String]

    init(
        account: AKSIPAccount,
        info: PJSUACallInfo
    ) {
        sipAccount = account
        identifier = info.identifier
        state = info.state
        stateText = info.stateText
        lastStatus = info.lastStatus
        lastStatusText = info.lastStatusText
        date = Date()
        localURI = info.localURI
        remoteURI = info.remoteURI
        incomingValue = info.isIncoming
        missedValue = info.isIncoming
        incomingIdentityHeaders = [:]
        super.init()
    }

    override var description: String {
        "\(localURI) <=> \(remoteURI)"
    }

    func answer() {
        let status = pjsua_call_answer(
            pjsua_call_id(identifier),
            200,
            nil,
            nil
        )

        if status == 0 {
            missedValue = false
        } else {
            Log.sip.error("Could not answer call id=\(identifier, privacy: .public) status=\(status, privacy: .public)")
        }
    }

    func hangUp() {
        guard identifier != kAKSIPUserAgentInvalidIdentifier, state != PJSIP_INV_STATE_DISCONNECTED else {
            return
        }

        let status = pjsua_call_hangup(
            pjsua_call_id(identifier),
            0,
            nil,
            nil
        )

        if status == 0 {
            missedValue = false
        } else {
            Log.sip.error("Could not hang up call id=\(identifier, privacy: .public) status=\(status, privacy: .public)")
        }
    }

    func attendedTransfer(to destinationCall: AKSIPCall) {
        transferStatus = -1
        transferStatusText = ""

        let status = pjsua_call_xfer_replaces(
            pjsua_call_id(identifier),
            pjsua_call_id(destinationCall.identifier),
            1,
            nil
        )

        if status != 0 {
            Log.sip.error("Could not transfer call id=\(identifier, privacy: .public) status=\(status, privacy: .public)")
        }
    }

    func sendRingingNotification() {
        let status = pjsua_call_answer(
            pjsua_call_id(identifier),
            180,
            nil,
            nil
        )

        if status != 0 {
            Log.sip.error("Could not send ringing notification call=\(identifier, privacy: .public) status=\(status, privacy: .public)")
        }
    }

    func replyWithTemporarilyUnavailable() {
        let status = pjsua_call_answer(
            pjsua_call_id(identifier),
            480,
            nil,
            nil
        )
        if status != 0 {
            Log.sip.error(
                "Could not reply 480 call=\(identifier, privacy: .public) status=\(status, privacy: .public)"
            )
        }
    }

    func replyWithBusyHere() {
        let status = pjsua_call_answer(
            pjsua_call_id(identifier),
            486,
            nil,
            nil
        )
        if status != 0 {
            Log.sip.error(
                "Could not reply 486 call=\(identifier, privacy: .public) status=\(status, privacy: .public)"
            )
        }
    }

    func sendDTMF(_ digits: String) {
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

    func setMuted(_ muted: Bool) {
        if muted {
            muteMicrophone()
        } else {
            unmuteMicrophone()
        }
    }

    func setHeld(_ held: Bool) {
        if held {
            hold()
        } else {
            unhold()
        }
    }

    func toggleMicrophoneMute() {
        setMuted(!microphoneMutedValue)
    }

    func toggleHold() {
        setHeld(mediaStatus != PJSUA_CALL_MEDIA_LOCAL_HOLD)
    }

    @nonobjc
    private final var mediaStatus: pjsua_call_media_status? {
        firstMediaInfo()?.status
    }

    @nonobjc
    private final func firstMediaInfo() -> pjsua_call_media_info? {
        guard identifier != kAKSIPUserAgentInvalidIdentifier else {
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
        guard !microphoneMutedValue, isConfirmed else {
            return
        }

        guard let media = firstMediaInfo() else {
            return
        }

        if pjsua_conf_disconnect(
            0,
            media.stream.aud.conf_slot
        ) == 0 {
            microphoneMutedValue = true
        } else {
            Log.sip.error("Could not mute microphone call=\(identifier, privacy: .public)")
        }
    }

    @nonobjc
    private final func unmuteMicrophone() {
        guard microphoneMutedValue, isConfirmed else {
            return
        }

        guard let media = firstMediaInfo() else {
            return
        }

        if pjsua_conf_connect(
            0,
            media.stream.aud.conf_slot
        ) == 0 {
            microphoneMutedValue = false
        } else {
            Log.sip.error("Could not unmute microphone call=\(identifier, privacy: .public)")
        }
    }

    @nonobjc
    private final func hold() {
        guard state == PJSIP_INV_STATE_CONFIRMED, mediaStatus != PJSUA_CALL_MEDIA_REMOTE_HOLD else {
            return
        }

        _ = pjsua_call_set_hold(
            pjsua_call_id(identifier),
            nil
        )
    }

    @nonobjc
    private final func unhold() {
        guard state == PJSIP_INV_STATE_CONFIRMED else {
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
                        Log.sip.error("Could not send INFO DTMF call=\(identifier, privacy: .public)")
                    }
                }
            }
        }
    }
}
