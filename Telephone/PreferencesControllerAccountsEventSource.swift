//
//  PreferencesControllerAccountsEventSource.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Foundation
import UseCases

final class PreferencesControllerAccountsEventSource {
    private final class TargetBox: @unchecked Sendable {
        let target: AccountsEventTarget

        init(_ target: AccountsEventTarget) {
            self.target = target
        }
    }

    private var observation: NotificationObservation?

    init(center: NotificationCenter, target: AccountsEventTarget) {
        let box = TargetBox(target)

        observation = NotificationObservation(
            center: center,
            name: .AKPreferencesControllerDidRemoveAccount,
            queue: nil
        ) { notification in
            guard let uuid = notification.userInfo?[
                AKSIPAccountKeys.uuid
            ] as? String else {
                return
            }
            box.target.didRemoveAccount(withUUID: uuid)
        }
    }

}
