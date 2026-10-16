//
//  CRMWorkspaceScene.swift
//  Telephone
//
//  CRM searches are independent of SIP calls and their windows.
//

import SwiftUI

@MainActor
struct CRMWorkspaceScene: Scene {
    static let id = "telephone-crm-workspace"
    let makeModel: @MainActor () -> CRMKeyLookupModel

    var body: some Scene {
        Window(
            NSLocalizedString("CRM", comment: "CRM settings tab title."),
            id: Self.id
        ) {
            CRMWorkspaceView(model: makeModel())
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 980, height: 650)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
    }
}

struct CRMWorkspaceView: View {
    @State private var model: CRMKeyLookupModel

    init(model: CRMKeyLookupModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.settings.enabled {
                CRMKeyLookupView(model: model, showsInlineSearch: true)
            } else {
                VStack(spacing: 12) {
                    Label(
                        NSLocalizedString("Enable CRM lookup", comment: "CRM settings toggle."),
                        systemImage: "building.2"
                    )
                    SettingsLink()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 660, minHeight: 470)
        .onAppear { model.activateContext() }
        .onDisappear { model.deactivateContext() }
    }
}
