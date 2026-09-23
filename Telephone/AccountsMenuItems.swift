//
//  AccountsMenuItems.swift
//  Telephone
//

import Observation
import SwiftUI

@MainActor
@Observable
final class AccountsCommandModel: NSObject {
    struct Item: Identifiable {
        let id: ObjectIdentifier
        let title: String
        fileprivate let controller: AccountController
    }

    @ObservationIgnored
    private let controllers: AccountControllers

    private(set) var items: [Item] = []

    @objc(initWithControllers:)
    init(controllers: AccountControllers) {
        self.controllers = controllers
        super.init()
        update()
    }

    @objc
    func update() {
        items = controllers.enabled.map { controller in
            Item(
                id: ObjectIdentifier(controller),
                title: controller.accountDescription,
                controller: controller
            )
        }
    }

    func toggle(_ item: Item) {
        if item.controller.isWindowKey() {
            item.controller.hideWindow()
        } else {
            item.controller.showWindow()
        }
    }
}

struct AccountsCommands: Commands {
    let model: AccountsCommandModel

    var body: some Commands {
        CommandGroup(after: .windowList) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                accountButton(item, index: index)
            }

            if !model.items.isEmpty {
                Divider()
            }
        }
    }

    @ViewBuilder
    private func accountButton(
        _ item: AccountsCommandModel.Item,
        index: Int
    ) -> some View {
        if index < 9 {
            Button(item.title) {
                model.toggle(item)
            }
            .keyboardShortcut(
                KeyEquivalent(Character(String(index + 1))),
                modifiers: .command
            )
        } else {
            Button(item.title) {
                model.toggle(item)
            }
        }
    }
}
