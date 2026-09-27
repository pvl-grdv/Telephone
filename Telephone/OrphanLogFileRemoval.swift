//
//  OrphanLogFileRemoval.swift
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

final class OrphanLogFileRemoval: NSObject {
    private let locations: ApplicationDataLocations
    private let manager: FileManager

    init(locations: ApplicationDataLocations, manager: FileManager) {
        self.locations = locations
        self.manager = manager
    }

    @objc func execute() {
        do {
            try manager.removeItem(at: locations.root().appendingPathComponent("Telephone.log"))
        } catch CocoaError.fileNoSuchFile {
            // Do nothing.
        } catch {
            let nsError = error as NSError
            Log.storage.error(
                """
                Could not remove orphan log file \
                domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code, privacy: .public) \
                description=\(nsError.localizedDescription, privacy: .private)
                """
            )
        }
    }
}
