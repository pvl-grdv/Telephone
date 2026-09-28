//
//  DelayedRestartScheduler.swift
//  Telephone
//

import Foundation

@MainActor
final class DelayedRestartScheduler {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let delay: Duration
    private let sleep: Sleep
    private var task: Task<Void, Never>?

    init(
        delay: Duration = .seconds(3),
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.delay = delay
        self.sleep = sleep
    }

    isolated deinit {
        task?.cancel()
    }

    func request(
        hasActiveCalls: @escaping @MainActor () -> Bool,
        deferRestart: @escaping @MainActor () -> Void,
        restart: @escaping @MainActor () -> Void
    ) {
        guard !hasActiveCalls() else {
            deferRestart()
            return
        }

        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }

            do {
                try await sleep(delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            guard !hasActiveCalls() else {
                deferRestart()
                return
            }

            restart()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
