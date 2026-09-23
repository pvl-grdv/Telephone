//
//  PerformanceStateReporting.swift
//  Telephone
//

import Foundation
import StateReporting

@MainActor
enum PerformanceStateReporting {
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
}

@available(macOS 27.0, *)
@MainActor
private enum PerformanceStateReporting27 {
    private static let settingsReporter:
        StateReporter<Never, Never> = .reporter(
            for: "com.tlphn.Telephone.settings"
        )

    static func showSettingsSection(_ section: SettingsSection) {
        settingsReporter.reportTransition(
            to: section.stateReportingLabel
        )
    }

    static func hideSettings() {
        settingsReporter.reportTransition(to: nil)
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
