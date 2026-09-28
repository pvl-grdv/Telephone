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

final class SIPRuntimeThread: @unchecked Sendable {
    private final class Operation: @unchecked Sendable {
        let body: () -> Void

        init(_ body: @escaping () -> Void) {
            self.body = body
        }
    }

    private let condition = NSCondition()
    private let finished = DispatchSemaphore(value: 0)
    private var operations: [Operation] = []
    private var isShuttingDown = false

    private lazy var thread: Thread = {
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "Telephone SIP runtime"
        thread.qualityOfService = .userInitiated
        return thread
    }()

    init() {
        thread.start()
    }

    deinit {
        shutdown()
    }

    func perform(_ body: @escaping () -> Void) {
        condition.lock()
        guard !isShuttingDown else {
            condition.unlock()
            return
        }

        operations.append(Operation(body))
        condition.signal()
        condition.unlock()
    }

    func performAndWait(_ body: @escaping () -> Void) {
        if Thread.current === thread {
            body()
            return
        }

        let completed = DispatchSemaphore(value: 0)
        perform {
            body()
            completed.signal()
        }
        completed.wait()
    }

    func shutdown() {
        condition.lock()
        let shouldWait = !isShuttingDown
        isShuttingDown = true
        condition.broadcast()
        condition.unlock()

        guard shouldWait, Thread.current !== thread else {
            return
        }

        finished.wait()
    }

    private func run() {
        defer { finished.signal() }

        while true {
            condition.lock()

            while operations.isEmpty && !isShuttingDown {
                condition.wait()
            }

            if operations.isEmpty && isShuttingDown {
                condition.unlock()
                return
            }

            let operation = operations.removeFirst()
            condition.unlock()

            autoreleasepool {
                operation.body()
            }
        }
    }
}
