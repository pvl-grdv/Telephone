//
//  NotificationObservation.swift
//  Telephone
//

import Foundation

final class NotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(
        center: NotificationCenter = .default,
        name: Notification.Name,
        object: AnyObject? = nil,
        queue: OperationQueue? = .main,
        using handler: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        token = center.addObserver(
            forName: name,
            object: object,
            queue: queue,
            using: handler
        )
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}


struct SendableReference<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
