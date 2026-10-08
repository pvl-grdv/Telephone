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
    var crmKeyLookupModel: CRMKeyLookupModel? = nil

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
    let showCustomerDetails: () -> Void
    let customerContextVisibilityChanged: (Bool) -> Void
    let sendDTMF: (String) -> Void

    var body: some View {
        Group {
            if model.isTransfer {
                transferContent
                    .frame(
                        minWidth: 360,
                        idealWidth: 380,
                        maxWidth: 480
                    )
            } else {
                regularContent
                    .frame(
                        minWidth: 420,
                        idealWidth: 480,
                        maxWidth: 640
                    )
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
        CompactCallView(
            model: model,
            crmKeyLookupModel: crmKeyLookupModel,
            showsCustomerContext: showsCustomerContext,
            answer: answer,
            decline: decline,
            hangUp: hangUp,
            toggleMute: toggleMute,
            toggleHold: toggleHold,
            showTransfer: showTransfer,
            redial: redial,
            showCustomerDetails: showCustomerDetails,
            sendDTMF: sendDTMF
        )
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
