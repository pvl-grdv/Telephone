import AppKit
import Foundation
import SwiftUI
import Testing

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

    private func capture(width: Int, scheme: ColorScheme) -> NSBitmapImageRep? {
        let size = NSSize(width: CGFloat(width), height: 640)
        let content = CRMCustomerInventoryView(customer: sampleCustomer())
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

        // SwiftUI schedules its first layout on the main run loop. Pump only
        // until a nonblank bitmap is available, with a bounded one-second limit.
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            if let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                if hasVisibleContent(bitmap) { return bitmap }
            }
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
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
