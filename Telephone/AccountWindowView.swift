//
//  AccountWindowView.swift
//  Telephone
//

import Foundation
import Observation
import SwiftUI

enum AccountWindowDisplayState: Equatable {
    case offline
    case connecting
    case available
    case unavailable

    var title: String {
        switch self {
        case .offline:
            NSLocalizedString(
                "Offline",
                comment: "Account registration Offline menu item."
            )
        case .connecting:
            NSLocalizedString(
                "Connecting...",
                comment: "Account registration Connecting... menu item."
            )
        case .available:
            NSLocalizedString(
                "Available",
                comment: "Account registration Available menu item."
            )
        case .unavailable:
            NSLocalizedString(
                "Unavailable",
                comment: "Account registration Unavailable menu item."
            )
        }
    }
}

struct RegistrarConnectionError: Equatable {
    let registrar: String
    let details: String?

    var title: String {
        String(
            format: NSLocalizedString(
                "Could not register with %@.",
                comment: "Registrar connection error."
            ),
            registrar
        )
    }

    var informativeText: String {
        details ?? NSLocalizedString(
            "Please check network connection and Registry Server settings.",
            comment: "Registrar connection error informative text."
        )
    }
}

@MainActor
@Observable
final class AccountWindowModel {
    var state: AccountWindowDisplayState = .offline
    var showsCallComposer = false
    var authenticationFailure: AuthenticationFailureModel?
    var registrarConnectionError: RegistrarConnectionError?
}

struct AccountWindowRootView: View {
    @Bindable var model: AccountWindowModel
    @State private var pendingAuthenticationFailureSubmission:
        AuthenticationFailureModel?

    let callDestinationComposer: CallDestinationComposer
    let callHistoryPresenter: CallHistoryPresenter
    let changeState: (AccountWindowControllerAccountState) -> Void
    let submitAuthenticationFailure: (AuthenticationFailureModel) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if model.showsCallComposer {
                callDestinationComposer.contentView
                    .transition(.opacity)

                Divider()
            }

            callHistoryPresenter.contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: 340,
            idealWidth: 380,
            minHeight: 220,
            idealHeight: 300
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AccountStateMenu(
                    state: model.state,
                    changeState: changeState
                )
            }
        }
        .sheet(
            item: $model.authenticationFailure,
            onDismiss: submitPendingAuthenticationFailure
        ) { authenticationFailure in
            AuthenticationFailureView(
                model: authenticationFailure
            ) {
                pendingAuthenticationFailureSubmission =
                    authenticationFailure
                model.authenticationFailure = nil
            }
        }
        .alert(
            model.registrarConnectionError?.title ?? "",
            item: $model.registrarConnectionError
        ) { _ in
            Button(
                NSLocalizedString("OK", comment: "OK button."),
                role: .cancel
            ) {}
        } message: { error in
            Text(error.informativeText)
        }
        .onCommand(Selector(("focusCallHistorySearch:"))) {
            callHistoryPresenter.focusSearch()
        }
        .onCommand(Selector(("makeCall:"))) {
            callHistoryPresenter.makeCall()
        }
        .onCommand(Selector(("copy:"))) {
            callHistoryPresenter.copySelectedAddress()
        }
        .onCommand(Selector(("delete:"))) {
            callHistoryPresenter.delete()
        }
        .onCommand(Selector(("deleteAll:"))) {
            callHistoryPresenter.deleteAll()
        }
    }

    private func submitPendingAuthenticationFailure() {
        guard let authenticationFailure =
            pendingAuthenticationFailureSubmission
        else {
            return
        }

        pendingAuthenticationFailureSubmission = nil
        submitAuthenticationFailure(authenticationFailure)
    }
}

private struct AccountStateMenu: View {
    let state: AccountWindowDisplayState
    let changeState: (AccountWindowControllerAccountState) -> Void

    var body: some View {
        Menu {
            Button {
                changeState(.available)
            } label: {
                Label(
                    NSLocalizedString(
                        "Available",
                        comment: "Account registration Available menu item."
                    ),
                    systemImage: "checkmark.circle.fill"
                )
            }

            Button {
                changeState(.unavailable)
            } label: {
                Label(
                    NSLocalizedString(
                        "Unavailable",
                        comment: "Account registration Unavailable menu item."
                    ),
                    systemImage: "minus.circle.fill"
                )
            }

            Divider()

            Button {
                changeState(.offline)
            } label: {
                Label(
                    NSLocalizedString(
                        "Offline",
                        comment: "Account registration Offline menu item."
                    ),
                    systemImage: "circle.slash"
                )
            }
        } label: {
            HStack(spacing: 6) {
                AccountStateIndicator(state: state)

                Text(state.title)
                    .lineLimit(1)
            }
        }
        .help(
            NSLocalizedString(
                "Account State",
                comment: "Account state toolbar item."
            )
        )
        .accessibilityLabel(
            NSLocalizedString(
                "Account State",
                comment: "Account state toolbar item."
            )
        )
        .accessibilityValue(state.title)
    }
}

private struct AccountStateIndicator: View {
    let state: AccountWindowDisplayState

    @ViewBuilder
    var body: some View {
        switch state {
        case .connecting:
            ProgressView()
                .controlSize(.mini)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        case .unavailable:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        case .offline:
            Image(systemName: "circle.slash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
