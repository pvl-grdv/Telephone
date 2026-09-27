//
//  DirectoryCreatingApplicationDataLocations.swift
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

final class DirectoryCreatingApplicationDataLocations {
    private let origin: ApplicationDataLocations
    private nonisolated(unsafe) let manager: FileManager

    init(origin: ApplicationDataLocations, manager: FileManager) {
        self.origin = origin
        self.manager = manager
    }
}

extension DirectoryCreatingApplicationDataLocations: ApplicationDataLocations {
    func root() -> URL {
        return createDirectory(at: origin.root())
    }

    func logs() -> URL {
        return createDirectory(at: origin.logs())
    }

    func callHistories() -> URL {
        return createDirectory(at: origin.callHistories())
    }

    private func createDirectory(at url: URL) -> URL {
        do {
            try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            let nsError = error as NSError
            Log.storage.error(
                """
                Could not create application data directory \
                path=\(url.path, privacy: .private) \
                domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code, privacy: .public) \
                description=\(nsError.localizedDescription, privacy: .private)
                """
            )
        }
        return url
    }
}
