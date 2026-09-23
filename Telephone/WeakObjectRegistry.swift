//
//  WeakObjectRegistry.swift
//  Telephone
//

import Observation

@MainActor
@Observable
final class WeakObjectRegistry<Key: Hashable, Value: AnyObject> {
    private final class WeakBox {
        weak var value: Value?

        init(_ value: Value) {
            self.value = value
        }
    }

    @ObservationIgnored
    private var storage: [Key: WeakBox] = [:]

    private(set) var generation = 0

    var registeredCount: Int {
        storage.count
    }

    func register(_ value: Value, key: Key) {
        storage[key] = WeakBox(value)
        generation &+= 1
    }

    func unregister(key: Key) {
        storage.removeValue(forKey: key)
        generation &+= 1
    }

    func value(for key: Key) -> Value? {
        storage[key]?.value
    }
}
