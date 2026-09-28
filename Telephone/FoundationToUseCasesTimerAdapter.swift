//
//  FoundationToUseCasesTimerAdapter.swift
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

import Foundation
import UseCases

final class FoundationToUseCasesTimerAdapter: UseCases.Timer {
    private let timer: Foundation.Timer

    init(timer: Foundation.Timer) {
        self.timer = timer
    }

    var interval: Double {
        timer.timeInterval
    }

    func invalidate() {
        timer.invalidate()
    }
}
