//
//  FoundationToUseCasesTimerAdapterFactory.swift
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

final class FoundationToUseCasesTimerAdapterFactory: TimerFactory {
    func makeRepeatingTimer(
        interval: Double,
        action: @escaping () -> Void
    ) -> UseCases.Timer {
        let action = TimerAction(action)
        let timer = Foundation.Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { _ in
            action.perform()
        }
        return FoundationToUseCasesTimerAdapter(timer: timer)
    }
}

private final class TimerAction: @unchecked Sendable {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func perform() {
        action()
    }
}
