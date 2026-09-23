//
//  CallWindowModel.swift
//  Telephone
//

import Foundation
import Observation

@MainActor
@Observable
final class CallWindowModel {
    enum Phase: Equatable {
        case incoming
        case active
        case ended
        case transferDestination
        case transferActive
        case transferEnded
    }

    var phase: Phase
    var displayedName = ""
    var status = ""

    var showsProgress = false
    var incomingActionsEnabled = true
    var answerFocusRequest = 0

    var hangUpEnabled = true
    var muteEnabled = false
    var muted = false
    var holdEnabled = false
    var held = false
    var transferEnabled = false

    var transferActionEnabled = false
    var transferCancelEnabled = true
    var redialEnabled = true
    var usesDTMFDisplay = false

    var accountDescription = ""
    var showsAccountInfo = false
    let isTransfer: Bool

    var customerCompany = ""
    var customerKeys = ""
    var customerEmails = ""
    var customerNote = ""
    var previousConversationCount = 0
    var lastCallDate: Date?
    var recentCustomerNotes: [CustomerContextNote] = []
    var customerContextLoaded = false

    init(isTransfer: Bool) {
        self.isTransfer = isTransfer
        phase = isTransfer ? .transferDestination : .active
    }
}
