//
//  AKNetworkReachability.swift
//  Telephone
//
//  Network.framework-backed default path availability.
//

import Foundation
import Network

final class AKNetworkReachability: @unchecked Sendable {
    static let didChangeNotification =
        Notification.Name("AKNetworkReachabilityDidChange")

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(
        label: "com.tlphn.Telephone.network-path"
    )

    private(set) var isReachable = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                isReachable = reachable
                NotificationCenter.default.post(
                    name: Self.didChangeNotification,
                    object: self
                )
            }
        }

        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
