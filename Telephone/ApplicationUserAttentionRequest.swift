//
//  ApplicationUserAttentionRequest.swift
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

@MainActor
final class ApplicationUserAttentionRequest {
    private var request: Int?

    private let isActive: () -> Bool
    private let requestAttention: () -> Int
    private let cancelAttention: (Int) -> Void
    private var activeObservation: NotificationObservation?

    init(
        center: NotificationCenter,
        didBecomeActiveNotification: Notification.Name,
        application: AnyObject,
        isActive: @escaping () -> Bool,
        requestAttention: @escaping () -> Int,
        cancelAttention: @escaping (Int) -> Void
    ) {
        self.isActive = isActive
        self.requestAttention = requestAttention
        self.cancelAttention = cancelAttention

        activeObservation = NotificationObservation(
            center: center,
            name: didBecomeActiveNotification,
            object: application
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.request = nil
            }
        }
    }
}

extension ApplicationUserAttentionRequest: UserAttentionRequest {
    func start() {
        if !isActive(), request == nil {
            request = requestAttention()
        }
    }

    func stop() {
        if let request {
            cancelAttention(request)
        }
        request = nil
    }
}
