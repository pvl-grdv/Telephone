//
//  PerformanceMetricsMonitor.swift
//  Telephone
//

import Foundation
import MetricKit

@available(macOS 27.0, *)
@MainActor
final class PerformanceMetricsMonitor {
    private let manager: MetricManager
    private let directory: URL
    private var metricsTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?

    init(directory: URL) {
        self.directory = directory
        manager = MetricManager(
            enabledStateReportingDomains: [
                StateReportingDomain(
                    rawValue: PerformanceStateReporting.settingsDomain
                ),
                StateReportingDomain(
                    rawValue: PerformanceStateReporting.callDomain
                ),
            ]
        )
    }

    func start() {
        guard metricsTask == nil, diagnosticsTask == nil else {
            return
        }

        metricsTask = Task { [weak self] in
            guard let self else { return }
            for await report in manager.metricReports {
                let directory = directory
                Task.detached(priority: .utility) {
                    Self.persistMetricReport(
                        report,
                        directory: directory
                    )
                }
            }
        }

        diagnosticsTask = Task { [weak self] in
            guard let self else { return }
            for await report in manager.diagnosticReports {
                let directory = directory
                Task.detached(priority: .utility) {
                    Self.persistDiagnosticReport(
                        report,
                        directory: directory
                    )
                }
            }
        }
    }

    deinit {
        metricsTask?.cancel()
        diagnosticsTask?.cancel()
    }

    private nonisolated static func persistMetricReport(
        _ report: MetricReport,
        directory: URL
    ) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.userInfo[MetricReport.encodingFormatKey] =
                MetricReport.EncodingFormat.byStateReportingDomain
            let data = try encoder.encode(report)
            try persist(
                data,
                prefix: "metrics",
                directory: directory
            )
        } catch {
            logPersistenceFailure(
                kind: "metric",
                error: error
            )
        }
    }

    private nonisolated static func persistDiagnosticReport(
        _ report: DiagnosticReport,
        directory: URL
    ) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try persist(
                data,
                prefix: "diagnostic",
                directory: directory
            )
        } catch {
            logPersistenceFailure(
                kind: "diagnostic",
                error: error
            )
        }
    }

    private nonisolated static func persist(
        _ data: Data,
        prefix: String,
        directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let timestamp = Int(Date().timeIntervalSince1970)
        let url = directory.appendingPathComponent(
            "\(prefix)-\(timestamp)-\(UUID().uuidString).json"
        )
        try data.write(to: url, options: .atomic)
    }

    private nonisolated static func logPersistenceFailure(
        kind: String,
        error: Error
    ) {
        let nsError = error as NSError
        Log.performance.error(
            """
            Could not persist \(kind, privacy: .public) MetricKit report \
            domain=\(nsError.domain, privacy: .public) \
            code=\(nsError.code, privacy: .public) \
            description=\(nsError.localizedDescription, privacy: .private)
            """
        )
    }
}
