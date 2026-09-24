//
//  AboutTelephone.swift
//  Telephone
//

import AppKit
import SwiftUI

enum AboutTelephoneScene {
    static let id = "telephone-about"
}

struct AboutTelephoneCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(
                NSLocalizedString(
                    "About Telephone",
                    comment: "Application About menu item."
                )
            ) {
                openWindow(id: AboutTelephoneScene.id)
            }
        }
    }
}

struct AboutTelephoneView: View {
    private let forkURL = URL(
        string: "https://github.com/pvl-grdv/Telephone"
    )!
    private let upstreamURL = URL(
        string: "https://github.com/64characters/Telephone"
    )!
    private let licenseURL = URL(
        string: "https://github.com/pvl-grdv/Telephone/blob/master/LICENSE"
    )!

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Telephone")
                    .font(.title2.weight(.semibold))

                Text(versionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let buildCommitText {
                    Text(buildCommitText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            VStack(spacing: 6) {
                Text(
                    NSLocalizedString(
                        "Independently maintained fork",
                        comment: "About window fork status."
                    )
                )
                .font(.headline)

                Text(
                    NSLocalizedString(
                        "This build is an independently maintained fork of Telephone.",
                        comment: "About window fork explanation."
                    )
                )
                .multilineTextAlignment(.center)

                Text(
                    NSLocalizedString(
                        "Based on Telephone by Alexey Kuznetsov and 64 Characters.",
                        comment: "About window upstream attribution."
                    )
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Link(
                    NSLocalizedString(
                        "Fork Repository",
                        comment: "About window fork source link."
                    ),
                    destination: forkURL
                )

                Link(
                    NSLocalizedString(
                        "Original Project",
                        comment: "About window upstream project link."
                    ),
                    destination: upstreamURL
                )

                Link(
                    NSLocalizedString(
                        "GPLv3 License",
                        comment: "About window license link."
                    ),
                    destination: licenseURL
                )
            }
            .controlSize(.small)

            Divider()

            VStack(spacing: 3) {
                Text(
                    "© 2008–2016 Alexey Kuznetsov · © 2016–2022 64 Characters"
                )
                Text(
                    NSLocalizedString(
                        "Fork modifications © 2026 Pavel Gordeev",
                        comment: "About window fork copyright."
                    )
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 460)
        .windowMinimizeBehavior(.disabled)
        .windowResizeBehavior(.disabled)
    }

    private var buildCommitText: String? {
        let value = Bundle.main.object(
            forInfoDictionaryKey: "TelephoneBuildCommit"
        ) as? String ?? ""

        guard
            !value.isEmpty,
            value != "local",
            !value.hasPrefix("$(")
        else {
            return nil
        }

        let shortCommit = String(value.prefix(7))
        return String(
            format: NSLocalizedString(
                "Commit %@",
                comment: "About window source commit."
            ),
            shortCommit
        )
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? ""

        return String(
            format: NSLocalizedString(
                "Version %@ (%@)",
                comment: "About window version and build."
            ),
            version,
            build
        )
    }
}
