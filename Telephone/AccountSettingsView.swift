//
//  AccountSettingsView.swift
//  Telephone
//

import Foundation
import SwiftUI

extension AccountSettingsModel {
    convenience init(preferencesController: AnyObject?) {
        self.init(
            preferencesController: preferencesController,
            credentials: CredentialsStore.shared
        )
    }
}

struct AccountSettingsView: View {
    let model: AccountSettingsModel

    var body: some View {
        HStack(spacing: 0) {
            AccountSettingsList(model: model)
            Divider()
            AccountSettingsEditor(model: model)
        }
        .alert(model.removalAlertTitle, isPresented: removalPresented) {
            Button(NSLocalizedString("Delete", comment: "Delete button."), role: .destructive) {
                model.confirmRemoval()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button."), role: .cancel) {
                model.cancelRemoval()
            }
        } message: {
            Text(model.removalAlertMessage)
        }
        .alert(
            NSLocalizedString(
                "Could not save account password.",
                comment: "Account credentials save error."
            ),
            isPresented: credentialsErrorPresented
        ) {
            Button(
                NSLocalizedString("OK", comment: "OK button."),
                role: .cancel
            ) {
                model.dismissCredentialsError()
            }
        }
    }

    private var credentialsErrorPresented: Binding<Bool> {
        Binding(
            get: { model.showsCredentialsError },
            set: { isPresented in
                if !isPresented {
                    model.dismissCredentialsError()
                }
            }
        )
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { model.pendingRemovalID != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelRemoval()
                }
            }
        )
    }
}

private struct AccountSettingsList: View {
    @Bindable var model: AccountSettingsModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach(model.accounts) { account in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(account.isEnabled ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 7, height: 7)

                        Text(account.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .tag(account.id)
                }
                .onMove(perform: model.moveAccounts)
            }
            .listStyle(.sidebar)
            .disabled(model.accountListInteractionDisabled)

            Divider()

            HStack(spacing: 6) {
                Button {
                    model.addAccount()
                } label: {
                    Label(
                        NSLocalizedString(
                            "Add Account",
                            comment: "Add account button."
                        ),
                        systemImage: "plus"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.add-account")
                .disabled(
                    !model.canAddAccount
                        || model.accountListInteractionDisabled
                )
                .help(NSLocalizedString("Add Account", comment: "Add account button."))

                Button {
                    model.requestRemoval()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(
                    !model.hasSelection
                        || model.accountListInteractionDisabled
                )
                .help(NSLocalizedString("Remove Account", comment: "Remove account button."))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(width: 205)
    }

}
