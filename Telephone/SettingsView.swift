//
//  SettingsView.swift
//  Telephone
//

import SwiftUI

struct SettingsRootView: View {
    @Bindable var model: SettingsViewModel
    let selectionChanged: (SettingsSection) -> Void

    var body: some View {
        TabView(selection: $model.selection.animation(.smooth(duration: 0.22))) {
            Tab(value: SettingsSection.general) {
                GeneralSettingsView()
            } label: {
                Label(
                    SettingsSection.general.title,
                    systemImage: SettingsSection.general.systemImage
                )
            }

            Tab(value: SettingsSection.accounts) {
                if model.selection == .accounts {
                    AccountSettingsView(model: model.accountModel)
                } else {
                    Color.clear
                }
            } label: {
                Label(
                    SettingsSection.accounts.title,
                    systemImage: SettingsSection.accounts.systemImage
                )
            }

            Tab(value: SettingsSection.sound) {
                if model.selection == .sound {
                    SoundSettingsView(model: model.soundModel)
                } else {
                    Color.clear
                }
            } label: {
                Label(
                    SettingsSection.sound.title,
                    systemImage: SettingsSection.sound.systemImage
                )
            }

            Tab(value: SettingsSection.network) {
                if model.selection == .network {
                    NetworkSettingsView(model: model.networkModel)
                } else {
                    Color.clear
                }
            } label: {
                Label(
                    SettingsSection.network.title,
                    systemImage: SettingsSection.network.systemImage
                )
            }
        }
        .frame(
            width: model.selection.windowSize.width,
            height: model.selection.windowSize.height
        )
        .windowResizeAnchor(.top)
        .sheet(isPresented: $model.showsAccountSetup) {
            AccountSetupSheet()
        }
        .onChange(of: model.selection, initial: true) { _, selection in
            PerformanceSignposts.settings.emitEvent(
                "SettingsSectionChanged",
                "\(selection.rawValue)"
            )
            PerformanceStateReporting.showSettingsSection(selection)
            selectionChanged(selection)
        }
        .onAppear {
            PerformanceSignposts.settings.emitEvent("SettingsVisible")
            PerformanceStateReporting.showSettingsSection(model.selection)
        }
        .onDisappear {
            PerformanceStateReporting.hideSettings()
            model.prepareToClose()
        }

}
}
