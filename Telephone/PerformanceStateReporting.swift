//
//  PerformanceStateReporting.swift
//  Telephone
//

import Foundation
import StateReporting

@MainActor
enum PerformanceStateReporting {
    static let settingsDomain = "com.tlphn.Telephone.settings"
    static let callDomain = "com.tlphn.Telephone.call"

    private enum CallState {
        case incoming
        case active
        case held
        case ended

        var label: String {
            switch self {
            case .incoming:
                "Incoming"
            case .active:
                "Active"
            case .held:
                "Held"
            case .ended:
                "Ended"
            }
        }
    }

    private static var callStates: [String: CallState] = [:]

    static func showSettingsSection(_ section: SettingsSection) {
        if #available(macOS 27.0, *) {
            PerformanceStateReporting27.showSettingsSection(section)
        }
    }

    static func hideSettings() {
        if #available(macOS 27.0, *) {
            PerformanceStateReporting27.hideSettings()
        }
    }

    static func showIncomingCall(id: String) {
        updateCall(id: id, state: .incoming)
    }

    static func showActiveCall(id: String, isHeld: Bool) {
        updateCall(id: id, state: isHeld ? .held : .active)
    }

    static func showEndedCall(id: String) {
        updateCall(id: id, state: .ended)
    }

    static func removeCall(id: String) {
        callStates.removeValue(forKey: id)
        reportAggregateCallState()
    }

    private static func updateCall(id: String, state: CallState) {
        callStates[id] = state
        reportAggregateCallState()
    }

    private static func reportAggregateCallState() {
        if #available(macOS 27.0, *) {
            PerformanceStateReporting27.showCallState(
                aggregateCallState?.label
            )
        }
    }

    private static var aggregateCallState: CallState? {
        if callStates.values.contains(where: { $0 == .incoming }) {
            return .incoming
        }
        if callStates.values.contains(where: { $0 == .active }) {
            return .active
        }
        if callStates.values.contains(where: { $0 == .held }) {
            return .held
        }
        if callStates.values.contains(where: { $0 == .ended }) {
            return .ended
        }
        return nil
    }
}

@available(macOS 27.0, *)
@MainActor
private enum PerformanceStateReporting27 {
    private static let settingsReporter:
        StateReporter<Never, Never> = .reporter(
            for: PerformanceStateReporting.settingsDomain
        )

    private static let callReporter:
        StateReporter<Never, Never> = .reporter(
            for: PerformanceStateReporting.callDomain
        )

    static func showSettingsSection(_ section: SettingsSection) {
        settingsReporter.reportTransition(
            to: section.stateReportingLabel
        )
    }

    static func hideSettings() {
        settingsReporter.reportTransition(to: nil)
    }

    static func showCallState(_ label: String?) {
        callReporter.reportTransition(to: label)
    }
}

private extension SettingsSection {
    var stateReportingLabel: String {
        switch self {
        case .general:
            "General"
        case .accounts:
            "Accounts"
        case .sound:
            "Sound"
        case .network:
            "Network"
        }
    }
}
