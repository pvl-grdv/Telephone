//
//  WaitingThread.swift
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

// Thread identity is immutable; all mutable state is protected by its condition.
// PJSIP requires a dedicated OS thread, so a Swift actor cannot replace it.
final class SIPRuntimeThread: @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let condition = NSCondition()
        var operations: [@Sendable () -> Void] = []
        var isShuttingDown = false
        var hasFinished = false
    }

    private let state: State
    private let thread: Thread

    init() {
        let state = State()
        self.state = state
        // The worker retains only its state, allowing owner deinit to stop it.
        thread = Thread { Self.run(state) }
        thread.name = "Telephone SIP runtime"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    deinit {
        shutdown()
    }

    @discardableResult
    func perform(_ body: @escaping @Sendable () -> Void) -> Bool {
        state.condition.lock()
        defer { state.condition.unlock() }
        guard !state.isShuttingDown else {
            return false
        }

        state.operations.append(body)
        state.condition.signal()
        return true
    }

    @discardableResult
    func performAndWait(_ body: @escaping @Sendable () -> Void) -> Bool {
        if Thread.current === thread {
            state.condition.lock()
            let acceptsWork = !state.isShuttingDown
            state.condition.unlock()
            guard acceptsWork else { return false }
            body()
            return true
        }

        let completed = DispatchSemaphore(value: 0)
        guard perform({
            defer { completed.signal() }
            body()
        }) else { return false }
        completed.wait()
        return true
    }

    func shutdown() {
        state.condition.lock()
        defer { state.condition.unlock() }
        state.isShuttingDown = true
        state.condition.broadcast()
        guard Thread.current !== thread else { return }
        // Every external caller joins the worker, including repeated shutdowns.
        while !state.hasFinished { state.condition.wait() }
    }

    private static func run(_ state: State) {
        defer {
            state.condition.lock()
            state.hasFinished = true
            state.condition.broadcast()
            state.condition.unlock()
        }

        while true {
            state.condition.lock()

            while state.operations.isEmpty && !state.isShuttingDown {
                state.condition.wait()
            }

            if state.operations.isEmpty && state.isShuttingDown {
                state.condition.unlock()
                return
            }

            let operation = state.operations.removeFirst()
            state.condition.unlock()

            autoreleasepool {
                operation()
            }
        }
    }
}
