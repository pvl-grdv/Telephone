//
//  CallHistoryCommands.swift
//  Telephone
//

import SwiftUI

extension FocusedValues {
    @Entry var callHistoryPresenter: CallHistoryPresenter?
}

struct CallHistoryCommands: Commands {
    @FocusedValue(\.callHistoryPresenter)
    private var presenter

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button(
                NSLocalizedString(
                    "Find…",
                    comment: "Focus call history search menu item."
                )
            ) {
                presenter?.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(presenter == nil)
        }
    }
}
