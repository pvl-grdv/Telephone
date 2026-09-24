//
//  CallWindowView.swift
//  Telephone
//

import Foundation
import SwiftUI

struct CallWindowView: View {
    @Bindable var model: CallWindowModel

    @AppStorage(UserDefaultsKeys.showCustomerContext)
    private var showsCustomerContext = true

    let transferDestinationComposer: CallDestinationComposer?

    let answer: () -> Void
    let decline: () -> Void
    let hangUp: () -> Void
    let toggleMute: () -> Void
    let toggleHold: () -> Void
    let showTransfer: () -> Void
    let redial: () -> Void
    let callTransferDestination: () -> Void
    let closeTransfer: () -> Void
    let cancelTransfer: () -> Void
    let completeTransfer: () -> Void
    let customerContextChanged: () -> Void
    let customerContextVisibilityChanged: (Bool) -> Void
    let sendDTMF: (String) -> Void

    var body: some View {
        Group {
            if model.isTransfer {
                transferContent
                    .frame(width: 360)
            } else {
                regularContent
                    .frame(width: 420)
            }
        }
        .windowResizeAnchor(.top)
        .navigationTitle(model.windowTitle)
        .windowDismissBehavior(
            model.windowDismissEnabled ? .enabled : .disabled
        )
        .focusedSceneValue(\.callCommandState, model.commandState)
        .sheet(item: $model.transferPresentation) { transfer in
            transfer.contentView
                .interactiveDismissDisabled()
        }
        .onChange(of: showsCustomerContext) { _, isVisible in
            customerContextVisibilityChanged(isVisible)
        }
    }

    private var regularContent: some View {
        VStack(spacing: 0) {
            DTMFInputSurface(
                focusRequest: model.callSurfaceFocusRequest,
                sendDTMF: sendDTMF
            ) {
                callStateContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showsCustomerContext {
                Divider()

                CustomerContextView(
                    model: model,
                    changed: customerContextChanged
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if model.showsAccountInfo {
                Divider()

                Text(model.accountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 22)
            }
        }
    }

    @ViewBuilder
    private var callStateContent: some View {
        switch model.phase {
        case .incoming:
            IncomingCallSection(
                model: model,
                answer: answer,
                decline: decline
            )
        case .active:
            ActiveCallSection(
                model: model,
                hangUp: hangUp,
                toggleMute: toggleMute,
                toggleHold: toggleHold,
                showTransfer: showTransfer
            )
        case .ended:
            EndedCallSection(
                model: model,
                redial: redial
            )
        case .transferDestination, .transferActive, .transferEnded:
            EmptyView()
        }
    }

    @ViewBuilder
    private var transferContent: some View {
        switch model.phase {
        case .transferDestination:
            if let transferDestinationComposer {
                TransferDestinationView(
                    composer: transferDestinationComposer,
                    call: callTransferDestination,
                    close: closeTransfer
                )
            }
        case .transferActive:
            DTMFInputSurface(
                focusRequest: model.callSurfaceFocusRequest,
                sendDTMF: sendDTMF
            ) {
                TransferActiveSection(
                    model: model,
                    cancel: cancelTransfer,
                    complete: completeTransfer
                )
            }
            .padding(14)
        case .transferEnded:
            TransferEndedSection(
                model: model,
                redial: redial,
                cancel: cancelTransfer
            )
            .padding(14)
        case .incoming, .active, .ended:
            EmptyView()
        }
    }
}

extension FocusedValues {
    @Entry var callCommandState: CallCommandState?
}
