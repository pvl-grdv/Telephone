//
//  CallTransferViews.swift
//  Telephone
//

import Foundation
import SwiftUI

struct TransferActiveSection: View {
    @Bindable var model: CallWindowModel

    let cancel: () -> Void
    let complete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CallIdentityView(
                    displayedName: model.displayedName,
                    identityDetail: model.identityDetail,
                    status: model.status,
                    usesDTMFDisplay: model.usesDTMFDisplay
                )

                Spacer(minLength: 8)

                if model.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Cancel", comment: "Cancel button."),
                    action: cancel
                )
                .keyboardShortcut(.cancelAction)
                .disabled(!model.transferCancelEnabled)

                Button(
                    NSLocalizedString(
                        "Transfer",
                        comment: "Transfer call button."
                    ),
                    action: complete
                )
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.transferActionEnabled)
            }
        }
    }
}

struct TransferEndedSection: View {
    @Bindable var model: CallWindowModel

    let redial: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CallIdentityView(
                    displayedName: model.displayedName,
                    identityDetail: model.identityDetail,
                    status: model.status,
                    usesDTMFDisplay: false
                )

                Spacer(minLength: 8)

                Button(action: redial) {
                    Label(
                        NSLocalizedString("Call Back", comment: "Call back button."),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(!model.redialEnabled)
            }

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Cancel", comment: "Cancel button."),
                    action: cancel
                )
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
