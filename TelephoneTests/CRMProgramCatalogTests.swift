import Foundation
import AppKit
import SwiftUI
import Testing

struct CRMProgramCatalogTests {
    private let fixture = Data(#"""
    {"data":[{"id":1,"name":"Example","availableForSupply":true,"signVersion":"2.0","signRelease":"0001","signDirectory":"example_sgn"},{"id":2,"name":"Example","availableForSupply":false,"signVersion":"1.0","signRelease":"0010","signDirectory":"old_sgn"}],"meta":{"requestId":"synthetic-catalogue","fetchedAt":"2026-01-01T12:00:00Z","complete":true,"fromCache":false}}
    """#.utf8)

    @Test func fixedReadRoutePreservesInactiveAndSameNamedRows() async throws {
        let transport = CatalogTransport(data: fixture)
        let configuration = try CRMGatewayConfiguration(origin: "https://gateway.example.invalid", token: "synthetic-token")
        let result = try await CRMGatewayClient(transport: transport).programCatalog(configuration: configuration)
        #expect(result.data.map(\.id) == [1, 2])
        #expect(result.data[1].availableForSupply == false)
        #expect(result.data[0].signRelease == "0001")
        #expect(result.data[0].stealthVersion == nil)
        #expect(result.data[1].matches("old_sgn"))
        #expect(result.data[1].matches("1.0"))
        let request = try #require(await transport.request)
        #expect(request.url?.absoluteString == "https://gateway.example.invalid/v1/programs/filter")
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == Data("{}".utf8))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
    }

    @Test func rejectsIncompleteCachedDuplicateAndMalformedCatalogue() async throws {
        for mutation in ["incomplete", "cached", "duplicate", "invalid-id", "malformed-release"] {
            var root = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
            var rows = try #require(root["data"] as? [[String: Any]])
            var meta = try #require(root["meta"] as? [String: Any])
            switch mutation {
            case "incomplete": meta["complete"] = false
            case "cached": meta["fromCache"] = true
            case "duplicate": rows[1]["id"] = 1
            case "invalid-id": rows[0]["id"] = 0
            default: rows[0]["signRelease"] = 1
            }
            root["data"] = rows; root["meta"] = meta
            let transport = CatalogTransport(data: try JSONSerialization.data(withJSONObject: root))
            let configuration = try CRMGatewayConfiguration(origin: "https://gateway.example.invalid", token: "synthetic-token")
            await #expect(throws: CRMGatewayError.invalidResponse) {
                try await CRMGatewayClient(transport: transport).programCatalog(configuration: configuration)
            }
        }
    }

    @Test @MainActor func filtersCatalogueWithoutMergingRecordsAndExportsWindowPreview() async throws {
        let suite = "CRMProgramCatalogTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: CatalogTokenStore())
        try await settings.save(enabled: true, origin: "https://gateway.example.invalid", newToken: "synthetic-token")
        let response = try JSONDecoder().decode(CRMProgramCatalogResponse.self, from: fixture)
        let model = CRMProgramCatalogModel(settings: settings, provider: CatalogProvider(response: response))
        await model.reload()
        #expect(model.visibleRecords.map(\.id) == [1])
        model.availableOnly = false
        #expect(model.visibleRecords.map(\.id) == [1, 2])
        model.search = "old_sgn"
        #expect(model.visibleRecords.map(\.id) == [2])
        model.search = ""

        if let path = ProcessInfo.processInfo.environment["TELEPHONE_UI_ARTIFACT_DIR"], !path.isEmpty {
            let output = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            _ = NSApplication.shared
            for scheme in [ColorScheme.light, .dark] {
                let size = NSSize(width: 1000, height: 640)
                let host = NSHostingView(rootView: CRMProgramCatalogView(model: model)
                    .environment(\.colorScheme, scheme).frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor)))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host; window.orderFront(nil)
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(400))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                window.appearance?.performAsCurrentDrawingAppearance {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                }
                let opaque = try #require(opaquePreview(bitmap, appearance: host.effectiveAppearance))
                let png = try #require(opaque.representation(using: .png, properties: [:]))
                let name = scheme == .dark ? "program-catalog-dark.png" : "program-catalog-light.png"
                try png.write(to: output.appendingPathComponent(name))
                window.orderOut(nil); window.contentView = nil; window.close()
            }
        }
        model.clear()
        #expect(model.records.isEmpty && model.fetchedAt == nil)
    }

    @MainActor private func opaquePreview(_ bitmap: NSBitmapImageRep, appearance: NSAppearance) -> NSBitmapImageRep? {
        guard let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide,
            pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: output) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh).fill()
        }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh),
            from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return output
    }
}

private actor CatalogTransport: CRMGatewayHTTPTransport {
    let data: Data
    private(set) var request: URLRequest?
    init(data: Data) { self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private struct CatalogTokenStore: CRMGatewayTokenStoring {
    func token(for origin: String) async -> String { "synthetic-token" }
    func save(_ token: String, for origin: String) async -> Bool { true }
    func remove(for origin: String) async -> Bool { true }
}
private struct CatalogProvider: CRMProgramCatalogProvider {
    let response: CRMProgramCatalogResponse
    func programCatalog(configuration: CRMGatewayConfiguration) async throws -> CRMProgramCatalogResponse { response }
}
