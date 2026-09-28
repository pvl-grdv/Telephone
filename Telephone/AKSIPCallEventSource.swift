//
//  AKSIPCallEventSource.swift
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

final class AKSIPCallEventSource {
    private let center: NotificationCenter
    private let target: CallEventTarget
    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter, target: CallEventTarget) {
        self.center = center
        self.target = target

        observe(.AKSIPCallCalling) { target, call in
            target.didMake(call)
        }
        observe(.AKSIPCallIncoming) { target, call in
            target.didReceive(call)
        }
        observe(.AKSIPCallConnecting) { target, call in
            target.isConnecting(call)
        }
        observe(.AKSIPCallDidConfirm) { target, call in
            target.didConnect(call)
        }
        observe(.AKSIPCallDidDisconnect) { target, call in
            target.didDisconnect(call)
        }
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    private func observe(
        _ name: Notification.Name,
        action: @escaping (CallEventTarget, Call) -> Void
    ) {
        let target = SendableReference(target)
        let action = SendableReference(action)
        observers.append(
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { notification in
                guard let call = notification.object as? Call else {
                    return
                }
                action.value(target.value, call)
            }
        )
    }
}
