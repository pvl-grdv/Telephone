//
//  ProgressiveSettingsMigrationTests.swift
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

import Testing
import UseCases
import UseCasesTestDoubles

@MainActor
final class ProgressiveSettingsMigrationTests {
    private let settings = SettingsFake()
    private var actions = ""

    @Test(arguments: [0, 1, 2, 3])
    func runsOnlyMigrationsNeededForSavedVersion(_ version: Int) {
        let settings = SettingsFake()
        settings.set(version, forKey: UserDefaultsKeys.settingsVersion)
        let accountUUID = SettingsMigrationSpy()
        let ipVersion = SettingsMigrationSpy()
        let tcpTransport = SettingsMigrationSpy()

        ProgressiveSettingsMigration(
            settings: settings,
            accountUUID: accountUUID,
            ipVersion: ipVersion,
            tcpTransport: tcpTransport
        ).execute()

        #expect(accountUUID.didCallExecute == (version == 0))
        #expect(ipVersion.didCallExecute == (version <= 1))
        #expect(tcpTransport.didCallExecute == (version <= 1))
        #expect(settings.integer(forKey: UserDefaultsKeys.settingsVersion) == max(2, version))
    }

    @Test func updatesVersionOnlyAfterEachMigrationStep() {
        ProgressiveSettingsMigration(
            settings: self,
            accountUUID: RecordedMigration { self.actions.append("Mau") },
            ipVersion: RecordedMigration { self.actions.append("Miv") },
            tcpTransport: RecordedMigration { self.actions.append("Mtt") }
        ).execute()

        #expect(actions == "MauSv1MivMttSv2")
    }
}

extension ProgressiveSettingsMigrationTests: KeyValueSettings {
    subscript(key: String) -> String? {
        get { settings[key] }
        set(newValue) { settings[key] = newValue }
    }
    func string(forKey key: String) -> String? { settings.string(forKey: key) }
    func set(_ value: Bool, forKey key: String) { settings.set(value, forKey: key) }
    func bool(forKey key: String) -> Bool { settings.bool(forKey: key) }
    func set(_ value: Int, forKey key: String) {
        actions.append("Sv\(value)")
        settings.set(value, forKey: key)
    }
    func integer(forKey key: String) -> Int { settings.integer(forKey: key) }
    func set(_ array: [Any], forKey key: String) { settings.set(array, forKey: key) }
    func array(forKey key: String) -> [Any]? { settings.array(forKey: key) }
    func exists(forKey key: String) -> Bool { settings.exists(forKey: key) }
    func register(defaults: [String : Any]) { settings.register(defaults: defaults) }
}


@MainActor
private final class RecordedMigration: SettingsMigration {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func execute() {
        action()
    }
}
