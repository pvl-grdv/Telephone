//
//  Call.swift
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

/// A stable identity shared by history and call-specific notes, scoped by account UUID.
public protocol CallHistoryIdentified: Sendable {
    var historyIdentifier: String { get }
}

@objc public protocol Call: Sendable {
    var account: Account { get }
    var remote: URI { get }
    var date: Date  { get }
    var duration: Int  { get }
    var isIncoming: Bool  { get }
    var isMissed: Bool  { get }
}
