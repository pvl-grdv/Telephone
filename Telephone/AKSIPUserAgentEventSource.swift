//
//  AKSIPUserAgentEventSource.swift
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

final class AKSIPUserAgentEventSource {
    private let target: UserAgentEventTarget
    private let agent: UserAgent
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        target: UserAgentEventTarget,
        agent: UserAgent,
        center: NotificationCenter = .default
    ) {
        self.target = target
        self.agent = agent
        self.center = center

        observe(.AKSIPUserAgentDidFinishStarting, object: agent) {
            $0.didFinishStarting($1)
        }
        observe(.AKSIPUserAgentDidFinishStopping, object: agent) {
            $0.didFinishStopping($1)
        }
        observe(.AKSIPUserAgentDidDetectNAT, object: agent) {
            $0.didDetectNAT($1)
        }
        observe(.AKSIPCallCalling) {
            $0.didMakeCall($1)
        }
        observe(.AKSIPCallIncoming) {
            $0.didReceiveCall($1)
        }
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    private func observe(
        _ name: Notification.Name,
        object: AnyObject? = nil,
        action: @escaping (UserAgentEventTarget, UserAgent) -> Void
    ) {
        let target = SendableReference(target)
        let agent = SendableReference(agent)
        let action = SendableReference(action)
        observers.append(
            center.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { _ in
                action.value(target.value, agent.value)
            }
        )
    }
}
