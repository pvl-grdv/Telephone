import AppKit
import Foundation
import SwiftUI
import Testing
import Vision

@MainActor
@Suite(.serialized)
struct CompactCallTests {
    @Test func summaryDoesNotRepeatCallerNameOrEquivalentPhone() {
        #expect(CallCustomerSummaryIdentity.distinctCompany("  EXAMPLE   Organization \n",
            displayedName: "Example Organization", identityDetail: "+7 (000) 555-01-01") == nil)
        #expect(CallCustomerSummaryIdentity.distinctCompany("8 (000) 555-01-01",
            displayedName: "Example Organization", identityDetail: "+70005550101") == nil)
        #expect(CallCustomerSummaryIdentity.distinctCompany("Example Organization",
            displayedName: "Example Person", identityDetail: "Example Organization · mobile · +70005550101") == nil)
        #expect(CallCustomerSummaryIdentity.distinctCompany("Different Organization",
            displayedName: "Example Person", identityDetail: "+70005550101") == "Different Organization")
        #expect(CallCustomerSummaryIdentity.distinctCompany("Company 1234567",
            displayedName: "Other 1234567", identityDetail: "+70005550101") == "Company 1234567")
    }

    @Test func closingAndReopeningDetailsKeepsPendingLookupAndDraft() async throws {
        _ = NSApplication.shared
        let fixture = try await makeFixture(delayed: true)
        fixture.lookup.setCallerPhone("+70005550101", isActive: true)
        await waitForRequest(fixture.provider)
        var saves = 0
        let details = controller(fixture) { saves += 1 }
        details.present()
        await settleWindow()
        fixture.call.customerNote = "Unfinished synthetic note"
        details.close()
        await settleWindow()
        #expect(saves == 1)
        #expect(fixture.lookup.state == .loading)
        #expect(fixture.call.customerNote == "Unfinished synthetic note")
        await fixture.provider.finishPhoneLookup()
        await waitUntilLoaded(fixture.lookup)
        let result = fixture.lookup.state
        details.present()
        await settleWindow()
        #expect(fixture.lookup.state == result)
        #expect(await fixture.provider.phoneRequests == 1)
        fixture.call.showActiveState()
        #expect(details.window?.isVisible == true)
        fixture.call.showEndedState()
        #expect(details.window?.isVisible == true)
        details.close()
        #expect(saves == 2)
        fixture.lookup.deactivateContext()
        #expect(fixture.lookup.state == .idle)
    }

    @Test func separateCallsKeepSeparateWindowsDraftsAndLookupState() async throws {
        _ = NSApplication.shared
        let first = try await makeFixture()
        let second = try await makeFixture()
        first.lookup.setCallerPhone("+70005550101", isActive: true)
        second.lookup.setCallerPhone("+70005550102", isActive: true)
        await waitUntilLoaded(first.lookup)
        await waitUntilLoaded(second.lookup)
        let firstWindow = controller(first)
        let secondWindow = controller(second)
        firstWindow.present()
        secondWindow.present()
        defer { firstWindow.close(); secondWindow.close() }
        #expect(firstWindow.window !== secondWindow.window)
        first.call.customerNote = "Only the first call"
        firstWindow.close()
        #expect(secondWindow.window?.isVisible == true)
        #expect(second.call.customerNote.isEmpty)
        #expect(second.lookup.callerPhone == "+70005550102")
        first.lookup.resetContext()
        #expect(first.lookup.callerPhone == nil)
        #expect(second.lookup.isCallerAlreadyLinked)
    }

    @Test func closingDetailsInvalidatesOnlyUnconfirmedPhoneLink() async throws {
        _ = NSApplication.shared
        let fixture = try await makeFixture()
        fixture.lookup.setCallerPhone("+70005550101", isActive: true)
        await waitUntilLoaded(fixture.lookup)
        fixture.lookup.keyNumber = "1"
        fixture.lookup.search()
        await waitUntilLoaded(fixture.lookup)
        fixture.lookup.preparePhoneLink()
        let confirmation = try #require(fixture.lookup.pendingPhoneLink)
        let details = controller(fixture)
        details.present()
        await settleWindow()
        details.close()
        await settleWindow()
        #expect(fixture.lookup.pendingPhoneLink == nil)
        fixture.lookup.confirmPhoneLink(confirmation)
        #expect(await fixture.provider.appendRequests == 0)
        #expect(fixture.lookup.canLinkPhone)
        #expect(fixture.lookup.state != .idle)
    }

    @Test func compactSizeIsIndependentOfInventoryAndContainsNoEditors() async throws {
        _ = NSApplication.shared
        let fixture = try await makeFixture()
        fixture.call.showIncomingState()
        let before = NSHostingView(rootView: compact(fixture).frame(width: 480)).fittingSize
        fixture.lookup.setCallerPhone("+70005550101", isActive: true)
        await waitUntilLoaded(fixture.lookup)
        let incoming = NSHostingView(rootView: compact(fixture).frame(width: 480)).fittingSize
        #expect(abs(before.height - incoming.height) < 1)
        #expect(incoming.height < 220)
        fixture.call.showActiveState()
        let active = NSHostingView(rootView: compact(fixture).frame(width: 480)).fittingSize
        #expect(active.height < 240)
        let source = try source("Telephone/CompactCallView.swift")
        #expect(!source.contains("CRMKeyLookupView("))
        #expect(!source.contains("CustomerContextView("))
        #expect(!source.contains("TextField("))
        let detailsSource = try self.source("Telephone/CallCustomerDetailsView.swift")
        #expect(!detailsSource.contains("focusedSceneValue"))
        #expect(!detailsSource.contains("IncomingCallSection("))
        #expect(!detailsSource.contains("DTMFInputSurface("))
        let lookupSource = try self.source("Telephone/CRMKeyLookupView.swift")
        #expect(!lookupSource.contains(".onAppear"))
        #expect(!lookupSource.contains(".onDisappear"))
        let owner = try self.source("Telephone/CallPresentationCoordinator.swift")
        for signature in ["func closeWindow()", "func invalidate()", "func setCall(_ call: AKSIPCall?)", "private func windowDidDisappear()"] {
            let body = try #require(owner.components(separatedBy: signature).dropFirst().first)
                .components(separatedBy: "\n    }").first ?? ""
            #expect(body.contains("closeCustomerDetails()"), "Details must close with owner: \(signature)")
        }
    }

    @Test func capturesIncomingActiveAndResizableDetailsContent() async throws {
        guard let directory = ProcessInfo.processInfo.environment["TELEPHONE_UI_ARTIFACT_DIR"], !directory.isEmpty else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = try await makeFixture()
        fixture.lookup.setCallerPhone("+70005550101", isActive: true)
        await waitUntilLoaded(fixture.lookup)
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .dark ? "dark" : "light"
            for incoming in [true, false] {
                if incoming { fixture.call.showIncomingState(); fixture.call.status = "calling" }
                else { fixture.call.showActiveState(); fixture.call.status = "01:24" }
                let size = NSHostingView(rootView: compact(fixture).frame(width: 480)).fittingSize
                #expect(size.height > 0 && size.height < 240)
                let content = compact(fixture)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.locale, Locale(identifier: "en"))
                    .environment(\.colorScheme, scheme)
                let view = NSHostingView(rootView: content)
                view.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = view
                window.orderFront(nil)
                defer {
                    window.orderOut(nil)
                    window.contentView = nil
                    window.close()
                }
                let bitmap = try capture(view, to: output.appendingPathComponent("live-call-\(incoming ? "incoming" : "active")-\(appearance).png"))
                try expectVisibleCallText(bitmap, incoming: incoming)
            }
            let details = controller(fixture)
            let window = try #require(details.window)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            for width in [660, 1100] {
                details.present()
                window.setContentSize(NSSize(width: width, height: width == 660 ? 500 : 720))
                let view = try #require(window.contentView)
                try capture(view, to: output.appendingPathComponent("live-client-details-\(appearance)-\(width).png"))
            }
            details.close()
            let local = CallCustomerDetailsWindowController(model: fixture.call, crmKeyLookupModel: nil,
                changed: {}, reload: {}, save: {}, saveOnClose: {})
            let localWindow = try #require(local.window)
            localWindow.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            local.present()
            localWindow.setContentSize(NSSize(width: 660, height: 500))
            try capture(try #require(localWindow.contentView),
                        to: output.appendingPathComponent("live-client-local-details-\(appearance)-660.png"))
            local.close()
        }
    }

    private func compact(_ fixture: Fixture) -> some View {
        CompactCallView(model: fixture.call, crmKeyLookupModel: fixture.lookup, showsCustomerContext: true,
            answer: {}, decline: {}, hangUp: {}, toggleMute: {}, toggleHold: {}, showTransfer: {},
            redial: {}, showCustomerDetails: {}, sendDTMF: { _ in })
    }

    private func controller(_ fixture: Fixture, save: @escaping () -> Void = {}) -> CallCustomerDetailsWindowController {
        CallCustomerDetailsWindowController(model: fixture.call, crmKeyLookupModel: fixture.lookup,
            changed: {}, reload: {}, save: {}, saveOnClose: save)
    }

    private func makeFixture(delayed: Bool = false) async throws -> Fixture {
        let defaults = try #require(UserDefaults(suiteName: "Telephone.CompactCallTests.\(UUID())"))
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: CompactCallTokenStore())
        try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "synthetic-token")
        let provider = CompactCallProvider(delayed: delayed)
        let model = CallWindowModel(isTransfer: false)
        model.displayedName = "Example Organization"
        model.identityDetail = "+7 (000) 555-01-01"
        model.status = "calling"
        model.customerContextLoaded = true
        model.previousConversationCount = 4
        model.muteEnabled = true
        model.holdEnabled = true
        model.transferEnabled = true
        return Fixture(call: model, lookup: CRMKeyLookupModel(settings: settings, provider: provider), provider: provider)
    }

    private func settleWindow() async {
        // Allow SwiftUI appearance/disappearance callbacks to actually run;
        // closing immediately after showWindow would miss view-lifetime bugs.
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func waitForRequest(_ provider: CompactCallProvider) async {
        for _ in 0..<200 {
            if await provider.phoneRequests > 0 { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Synthetic phone request did not start")
    }

    private func waitUntilLoaded(_ model: CRMKeyLookupModel) async {
        for _ in 0..<200 where model.state == .loading { try? await Task.sleep(for: .milliseconds(5)) }
        if case .loaded = model.state { return }
        Issue.record("Synthetic lookup did not load: \(model.state)")
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Match the shared inventory capture: settle hosted controls, then composite
    /// their real pixels over the native window background (absent from a view
    /// cache). These are content previews, not WindowServer screenshots.
    @discardableResult
    private func capture(_ view: NSView, to destination: URL) throws -> NSBitmapImageRep {
        let settleUntil = Date(timeIntervalSinceNow: 0.3)
        while Date() < settleUntil {
            view.layoutSubtreeIfNeeded()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        var captured: NSBitmapImageRep?
        repeat {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let output = opaque(bitmap, appearance: view.effectiveAppearance), hasVisibleContent(output) {
                    captured = output
                    break
                }
            }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        let bitmap = try #require(captured, "Hosted preview must contain visible pixels: \(destination.lastPathComponent)")
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(!png.isEmpty)
        try png.write(to: destination, options: .atomic)
        return bitmap
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

    private func hasVisibleContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return false }
        let strideX = max(1, bitmap.pixelsWide / 96)
        let strideY = max(1, bitmap.pixelsHigh / 96)
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

    private func expectVisibleCallText(_ bitmap: NSBitmapImageRep, incoming: Bool) throws {
        let image = try #require(bitmap.cgImage)
        // Match existing inventory OCR: enlarge captured pixels only for the
        // fast recognizer. The delivered PNG is the unscaled native capture.
        let context = try #require(CGContext(data: nil, width: image.width * 3, height: image.height * 3,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * 3, height: image.height * 3))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.005
        try VNImageRequestHandler(cgImage: try #require(context.makeImage())).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string.lowercased() }.joined(separator: " ")
        #expect(text.contains("example"), "Caller identity must be readable: \(text)")
        if incoming {
            #expect(text.contains("answer"), "Answer label must be readable: \(text)")
            // Native control labels and actions have UI smoke coverage. Avoid
            // treating the fast OCR model's "cl"/"d" confusion as a UI failure.
        } else {
            #expect(text.contains("01:24"), "Active call status must be readable: \(text)")
        }
    }

    private struct Fixture {
        let call: CallWindowModel
        let lookup: CRMKeyLookupModel
        let provider: CompactCallProvider
    }
}

private actor CompactCallTokenStore: CRMGatewayTokenStoring {
    func token(for origin: String) -> String { "synthetic-token" }
    func save(_ token: String, for origin: String) -> Bool { true }
    func remove(for origin: String) -> Bool { true }
}

private actor CompactCallProvider: CRMKeyLookupProvider {
    private let delayed: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var phoneRequests = 0
    private(set) var appendRequests = 0

    init(delayed: Bool) { self.delayed = delayed }

    func customer(forPhoneNumber phoneNumber: String, companyID: Int?, configuration: CRMGatewayConfiguration) async throws -> CRMPhoneLookupResponse {
        phoneRequests += 1
        if delayed { await withCheckedContinuation { continuation = $0 } }
        let payload = PhoneResponse(data: customer, matches: [], meta: metadata)
        return try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: JSONEncoder().encode(payload))
    }

    func finishPhoneLookup() { continuation?.resume(); continuation = nil }

    func customer(forKeyNumber keyNumber: Int, configuration: CRMGatewayConfiguration) async throws -> CRMKeyLookupResponse {
        CRMKeyLookupResponse(data: customer, meta: metadata)
    }

    func appendPhone(_ phoneNumber: String, companyID: Int, sourceKeyID: Int, expectedPhone: String,
                     configuration: CRMGatewayConfiguration) async throws -> CRMPhoneAppendResponse {
        appendRequests += 1
        throw CRMGatewayError.unavailable
    }

    private struct PhoneResponse: Encodable {
        let data: CRMKeyLookupCustomer
        let matches: [CRMPhoneLookupMatch]
        let meta: CRMKeyLookupMetadata
    }

    private var metadata: CRMKeyLookupMetadata {
        CRMKeyLookupMetadata(requestId: "synthetic-live-call", fetchedAt: "2026-10-08T08:00:00Z", complete: true, fromCache: false)
    }

    private var customer: CRMKeyLookupCustomer {
        CRMKeyLookupCustomer(sourceKeyId: 1,
            company: CRMKeyLookupCompany(id: 7000, name: "Example Organization", formattedCode: "00-00-7000", phone: "+12025550100", phones: ["+12025550100"]),
            keys: (1...23).map { key in
                let url = URL(string: "https://example.test/keys/\(key)")!
                return CRMKeyLookupKey(id: key, name: "Engineering \(key)", url: url,
                    programs: (1...(key == 23 ? 39 : 32)).map { record in
                        CRMKeyLookupProgram(recordId: record, programId: record,
                            name: "Program \(record) · environmental analysis", version: "2026.\(1000 + record)", release: "0010", keyUrl: url)
                    })
            })
    }
}
