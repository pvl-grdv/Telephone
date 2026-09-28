//
//  WorkspaceSleepStatus.swift
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

final class WorkspaceSleepStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var sleeping = false
    private var observations: [NotificationObservation] = []

    var isSleeping: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sleeping
    }

    init(
        center: NotificationCenter,
        willSleepNotification: Notification.Name,
        didWakeNotification: Notification.Name,
        workspace: AnyObject
    ) {
        observations = [
            NotificationObservation(
                center: center,
                name: willSleepNotification,
                object: workspace,
                queue: nil
            ) { [weak self] _ in
                self?.setSleeping(true)
            },
            NotificationObservation(
                center: center,
                name: didWakeNotification,
                object: workspace,
                queue: nil
            ) { [weak self] _ in
                self?.setSleeping(false)
            },
        ]
    }

    private func setSleeping(_ value: Bool) {
        lock.lock()
        sleeping = value
        lock.unlock()
    }
}
