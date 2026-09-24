//
//  CallCommandAvailability.swift
//  Telephone
//

enum CallCommandAvailability {
    static func mute(_ state: CallCommandState?) -> Bool {
        state?.phase == .active && state?.muteEnabled == true
    }

    static func hold(_ state: CallCommandState?) -> Bool {
        guard let state else { return false }
        return (state.phase == .active || state.phase == .transferActive)
            && state.holdEnabled
    }

    static func transfer(_ state: CallCommandState?) -> Bool {
        state?.phase == .active && state?.transferEnabled == true
    }

    static func redial(_ state: CallCommandState?) -> Bool {
        guard let state else { return false }
        return (state.phase == .ended || state.phase == .transferEnded)
            && state.redialEnabled
    }

    static func answer(_ state: CallCommandState?) -> Bool {
        state?.phase == .incoming && state?.incomingActionsEnabled == true
    }

    static func hangUp(_ state: CallCommandState?) -> Bool {
        guard let state else { return false }

        switch state.phase {
        case .incoming:
            return state.incomingActionsEnabled
        case .active, .transferActive:
            return state.hangUpEnabled
        default:
            return false
        }
    }
}
