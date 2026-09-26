//
//  NameServers.swift
//  Telephone
//
//  Observes the system DNS server list through SystemConfiguration.
//

import Foundation
import SystemConfiguration

@objc
protocol NameServersChangeEventTarget: AnyObject {
    func nameServersDidChange(_ nameServers: NameServers)
}

@objcMembers
final class NameServers: NSObject {
    private static let dnsSettingsKey = "State:/Network/Global/DNS"

    private weak var target: NameServersChangeEventTarget?
    private var store: SCDynamicStore?
    private var source: CFRunLoopSource?

    init(
        bundle: Bundle,
        target: NameServersChangeEventTarget
    ) {
        self.target = target
        super.init()

        let name = bundle.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String ?? "Telephone"

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        store = SCDynamicStoreCreate(
            kCFAllocatorDefault,
            name as CFString,
            nameServersStoreDidChange,
            &context
        )

        guard let store else { return }

        SCDynamicStoreSetNotificationKeys(
            store,
            [Self.dnsSettingsKey] as CFArray,
            nil
        )

        source = SCDynamicStoreCreateRunLoopSource(
            kCFAllocatorDefault,
            store,
            0
        )

        if let source {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                source,
                .defaultMode
            )
        }
    }

    deinit {
        if let source {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                source,
                .defaultMode
            )
        }
    }

    var all: [String] {
        guard
            let store,
            let settings = SCDynamicStoreCopyValue(
                store,
                Self.dnsSettingsKey as CFString
            ) as? [String: Any],
            let addresses = settings["ServerAddresses"] as? [String]
        else {
            return []
        }

        return addresses
    }

    fileprivate func notifyTarget() {
        target?.nameServersDidChange(self)
    }
}

private func nameServersStoreDidChange(
    _ store: SCDynamicStore,
    _ changedKeys: CFArray,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }

    let nameServers = Unmanaged<NameServers>
        .fromOpaque(info)
        .takeUnretainedValue()

    nameServers.notifyTarget()
}
