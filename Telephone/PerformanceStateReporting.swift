//
//  PerformanceStateReporting.swift
//  Telephone
//

import StateReporting

@MainActor
enum PerformanceStateReporting {
    private static let settingsDomain =
        "com.tlphn.Telephone.settings"

    private static let settingsReporter:
        StateReporter<Never, Never> = .reporter(
            for: settingsDomain
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
