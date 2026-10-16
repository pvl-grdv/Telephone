//
//  CallHistoryCommands.swift
//  Telephone
//

import SwiftUI

extension FocusedValues {
    @Entry var callHistoryModel: CallHistoryViewModel?
}

struct CallHistoryCommands: Commands {
    @FocusedValue(\.callHistoryModel)
    private var model

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button(
                NSLocalizedString(
                    "Find…",
                    comment: "Focus call history search menu item."
                )
            ) {
                model?.requestSearchFocus()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model == nil)
        }
    }
}
