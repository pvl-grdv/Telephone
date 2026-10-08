import AppKit
import Foundation
import SwiftUI
import Testing
import Vision

/// Opt-in CI artifacts of the actual shared inventory component, using only
/// synthetic gateway records. This does not start SIP or access a gateway.
@MainActor
struct CRMInventoryViewRenderingTests {
    @Test func capturesSharedInventoryInLightAndDarkAtCompactAndWideSizes() throws {
        guard let directory = ProcessInfo.processInfo.environment["TELEPHONE_UI_ARTIFACT_DIR"],
              !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared

        for width in [420, 660] {
            for scheme in [ColorScheme.light, .dark] {
                let bitmap = try #require(capture(width: width, scheme: scheme))
                #expect(bitmap.pixelsWide >= width)
                #expect(bitmap.pixelsHigh >= 640)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(!png.isEmpty)
                let appearance = scheme == .dark ? "dark" : "light"
                let file = output.appendingPathComponent("crm-inventory-\(appearance)-\(width).png")
                try png.write(to: file, options: .atomic)
                let decoded = try #require(NSBitmapImageRep(data: Data(contentsOf: file)))
                #expect(decoded.pixelsWide == bitmap.pixelsWide)
                #expect(decoded.pixelsHigh == bitmap.pixelsHigh)
            }
        }
    }

    @Test func capturesDesktopBrowserWith743Records() throws {
        guard let directory = ProcessInfo.processInfo.environment["TELEPHONE_UI_ARTIFACT_DIR"], !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for width in [660, 820, 1100] {
            for scheme in [ColorScheme.light, .dark] {
                let bitmap = try #require(capture(width: width, scheme: scheme, browser: true))
                #expect(bitmap.pixelsWide >= width)
                #expect(bitmap.pixelsHigh >= 640)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(!png.isEmpty)
                let appearance = scheme == .dark ? "dark" : "light"
                try png.write(to: output.appendingPathComponent("crm-browser-\(appearance)-\(width).png"), options: .atomic)
                try expectVisibleMetadataPixels(bitmap)
            }
        }
    }

    @Test func capturesCompleteHistoryWindowAndGatewaySettings() async throws {
        guard let directory = ProcessInfo.processInfo.environment["TELEPHONE_UI_ARTIFACT_DIR"], !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let defaults = try #require(UserDefaults(suiteName: "Telephone.CRMPreview.\(UUID())"))
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: PreviewTokenStore())
        try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "synthetic-token")
        let snapshot = try CRMHistorySnapshot.checkedKey(
            response: CRMKeyLookupResponse(data: largeCustomer(gatewayLinks: true), meta: CRMKeyLookupMetadata(
                requestId: "synthetic-window-preview", fetchedAt: "2026-10-08T08:00:00Z", complete: true, fromCache: false)),
            keyNumber: 1, phone: "+70005550101", checkedAt: Date(timeIntervalSince1970: 1791446400)
        )
        let lookup = CRMHistoryLookupModel(storage: PreviewHistoryStorage(check: try snapshot.storedCheck()),
            settings: settings, provider: CRMGatewayClient(transport: GatewayTransportFake(status: 404, data: Data())))
        lookup.load(accountUUID: "synthetic-account", callIdentifier: "synthetic-call")
        for _ in 0..<200 where lookup.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(lookup.snapshot?.customer?.keys.count == 23)
        #expect(lookup.snapshot?.customer?.keys.reduce(0) { $0 + $1.programs.count } == 743)
        let controller = CRMHistoryWindowController(model: lookup, didClose: {})
        let window = try #require(controller.window)
        defer { controller.close() }
        for scheme in [ColorScheme.light, .dark] {
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            for width in [660, 820, 1100] {
                window.setContentSize(NSSize(width: width, height: 720))
                controller.showWindow(nil)
                let contentView = try #require(window.contentView)
                let bitmap = try #require(capture(view: contentView))
                try write(bitmap, name: "crm-window-content-\(scheme == .dark ? "dark" : "light")-\(width)", to: output)
                try expectVisibleMetadataPixels(bitmap)
                // CI does not grant screen-recording permission. These are
                // content previews, not full WindowServer screenshots.
            }
        }
        let status = Data(("{\"runtime\":{\"build\":{\"version\":\"1.4.0\",\"commit\":\"" + String(repeating: "a", count: 40) + "\",\"builtAt\":\"2026-10-08T08:00:00Z\",\"integrity\":\"verified\"},\"startedAt\":\"2026-10-08T08:30:00Z\",\"processId\":123}}").utf8)
        let settingsModel = CRMGatewaySettingsModel(settings: settings,
            statusProvider: CRMGatewayClient(transport: GatewayTransportFake(data: status)))
        await settingsModel.checkConnection()
        #expect(settingsModel.gatewayRuntime?.build.version == "1.4.0")
        for scheme in [ColorScheme.light, .dark] {
            let content = CRMGatewaySettingsView(model: settingsModel)
                .environment(\.colorScheme, scheme)
            let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 800),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            settingsWindow.contentView = NSHostingView(rootView: content)
            settingsWindow.orderFront(nil)
            defer { settingsWindow.close() }
            let contentView = try #require(settingsWindow.contentView)
            let bitmap = try #require(capture(view: contentView))
            try write(bitmap, name: "crm-gateway-settings-\(scheme == .dark ? "dark" : "light")", to: output)
        }
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String, to directory: URL) throws {
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(!png.isEmpty)
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }

    private func capture(width: Int, scheme: ColorScheme, browser: Bool = false) -> NSBitmapImageRep? {
        let size = NSSize(width: CGFloat(width), height: 640)
        let content = CRMCustomerInventoryView(customer: browser ? largeCustomer() : sampleCustomer(), usesBrowserLayout: browser)
            .padding(18)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, scheme)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hostingView
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        let bitmap = capture(view: hostingView)
        return bitmap
    }

    private func capture(view hostingView: NSView) -> NSBitmapImageRep? {
        // Wait for hosted AppKit controls and SwiftUI layers, not just the
        // first nonblank frame (which can contain only the table).
        let settleUntil = Date(timeIntervalSinceNow: 0.3)
        while Date() < settleUntil {
            hostingView.layoutSubtreeIfNeeded()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            if let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                if hasVisibleContent(bitmap) { return opaque(bitmap, appearance: hostingView.effectiveAppearance) }
            }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
    }

    private func opaque(_ bitmap: NSBitmapImageRep, appearance: NSAppearance) -> NSBitmapImageRep? {
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

    private func expectVisibleMetadataPixels(_ bitmap: NSBitmapImageRep) throws {
        let image = try #require(bitmap.cgImage)
        // CI's virtual display is 1x. Enlarge the existing pixels for the fast
        // recognizer; never alter the UI or omit columns to satisfy this check.
        let context = try #require(CGContext(data: nil, width: image.width * 3, height: image.height * 3,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * 3, height: image.height * 3))
        let enlarged = try #require(context.makeImage())
        let request = VNRecognizeTextRequest()
        // The fast recognizer ships on CI images; accurate recognition may
        // require a separately installed language model.
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.005
        try VNImageRequestHandler(cgImage: enlarged).perform([request])
        let strings = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string.lowercased() }
        // Assert actual version and release values rather than tiny gray
        // headings, which the CI recognizer misreads. Neither value occurs
        // elsewhere in the UI, so clipped trailing columns fail this test.
        #expect(strings.contains { $0.contains("2026.1003") }, "Rendered first version: \(strings)")
        #expect(strings.contains { $0.contains("0010") }, "Rendered release: \(strings)")
    }

    private func hasVisibleContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return false }
        let strideX = max(1, bitmap.pixelsWide / 48)
        let strideY = max(1, bitmap.pixelsHigh / 48)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: strideY) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: strideX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if abs(color.redComponent - background.redComponent) > 0.03
                    || abs(color.greenComponent - background.greenComponent) > 0.03
                    || abs(color.blueComponent - background.blueComponent) > 0.03 {
                    return true
                }
            }
        }
        return false
    }

    private func largeCustomer(gatewayLinks: Bool = false) -> CRMKeyLookupCustomer {
        CRMKeyLookupCustomer(sourceKeyId: gatewayLinks ? 1 : nil,
            company: CRMKeyLookupCompany(id: 7000, name: "Example organization · synthetic inventory", formattedCode: "00-00-7000", phone: nil, phones: ["+70005550101"]),
            keys: (1...23).map { keyID in
                let url = URL(string: gatewayLinks ? "https://integral.ru/personal/keys/00-00-7000/\(keyID)/" : "https://example.test/keys/\(keyID)")!
                return CRMKeyLookupKey(id: keyID, name: "Engineering \(keyID)", url: url,
                    programs: (1...(keyID == 23 ? 39 : 32)).map { recordID in
                        CRMKeyLookupProgram(recordId: recordID, programId: max(1, recordID / 2), name: "Program \(recordID / 2) — environment analysis", version: "2026.\(1000 + recordID)", release: "0010", keyUrl: url)
                    })
            })
    }

    private func sampleCustomer() -> CRMKeyLookupCustomer {
        let portal = URL(string: "https://example.test/keys/4200")!
        let programs = [
            CRMKeyLookupProgram(recordId: 1, programId: 100, name: "Air analysis", version: "4.9", release: "9.10", keyUrl: portal),
            CRMKeyLookupProgram(recordId: 2, programId: 200, name: "Noise assessment", version: "2.2", release: "0009", keyUrl: portal),
            CRMKeyLookupProgram(recordId: 3, programId: 100, name: "Air analysis", version: "4.10", release: "9.10", keyUrl: portal),
            CRMKeyLookupProgram(recordId: 4, programId: 200, name: "Noise assessment", version: "2.3", release: "0010", keyUrl: portal),
            CRMKeyLookupProgram(recordId: 5, programId: 100, name: "Air analysis", version: "4.10", release: "10.1", keyUrl: portal)
        ]
        return CRMKeyLookupCustomer(
            sourceKeyId: 4200,
            company: CRMKeyLookupCompany(
                id: 7000, name: "Example organization", formattedCode: "00-00-7000", phone: nil, phones: nil
            ),
            keys: [
                CRMKeyLookupKey(id: 2017, name: "Office", url: URL(string: "https://example.test/keys/2017")!, programs: []),
                CRMKeyLookupKey(id: 4200, name: "Engineering", url: portal, programs: programs),
                CRMKeyLookupKey(id: 3, name: "Portable", url: URL(string: "https://example.test/keys/3")!, programs: [])
            ]
        )
    }
}

private struct PreviewHistoryStorage: CallHistoryCRMStorage {
    let check: StoredCallCRMCheck
    func phone(accountUUID: String, callIdentifier: String) async throws -> String? { "+70005550101" }
    func load(accountUUID: String, callIdentifier: String) async throws -> StoredCallCRMCheck? { check }
    func save(_ check: StoredCallCRMCheck, accountUUID: String, callIdentifier: String) async throws -> Bool { true }
}

private actor PreviewTokenStore: CRMGatewayTokenStoring {
    func token(for origin: String) async -> String { "synthetic-token" }
    func save(_ token: String, for origin: String) async -> Bool { true }
    func remove(for origin: String) async -> Bool { true }
}
