//
//  GeneralSettingsView.swift
//  Telephone
//

import SwiftUI
import UseCases

struct GeneralSettingsView: View {
    @AppStorage(UserDefaultsKeys.formatTelephoneNumbers)
    private var formatsTelephoneNumbers = true

    @AppStorage(SettingsKeys.pauseMedia)
    private var pausesMedia = true

    @AppStorage(UserDefaultsKeys.autoCloseCallWindow)
    private var autoClosesCallWindows = true

    @AppStorage(UserDefaultsKeys.callWaiting)
    private var callWaiting = true

    @AppStorage(UserDefaultsKeys.showCustomerContext)
    private var showsCustomerContext = true

    var body: some View {
        Form {
            Section {
                Toggle(
                    NSLocalizedString(
                        "Automatically format phone numbers",
                        comment: "General settings toggle."
                    ),
                    isOn: $formatsTelephoneNumbers
                )
                Toggle(
                    NSLocalizedString(
                        "Pause media during connected calls",
                        comment: "General settings toggle."
                    ),
                    isOn: $pausesMedia
                )
                Toggle(
                    NSLocalizedString(
                        "Automatically close call windows",
                        comment: "General settings toggle."
                    ),
                    isOn: $autoClosesCallWindows
                )
                Toggle(
                    NSLocalizedString("Call waiting", comment: "General settings toggle."),
                    isOn: $callWaiting
                )
                Toggle(
                    NSLocalizedString(
                        "Show customer context during calls",
                        comment: "General settings toggle."
                    ),
                    isOn: $showsCustomerContext
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.general.content")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
