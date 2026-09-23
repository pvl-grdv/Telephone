//
//  ApplicationDialogController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

private extension Notification.Name {
    static let applicationQuitConfirmed =
        Notification.Name("TelephoneApplicationQuitConfirmed")
}

@MainActor
@objcMembers
final class ApplicationDialogController: NSObject {
    fileprivate static let sceneID = "telephone-application-dialog"

    private let model = ApplicationDialogModel()
    private var installed = false
    private lazy var representation =
        NSHostingSceneRepresentation<ApplicationDialogScene> {
            ApplicationDialogScene(
                model: model,
                dismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        }

    var isPresenting: Bool {
        model.dialog != nil
    }

    class func quitConfirmedNotificationName() -> String {
        Notification.Name.applicationQuitConfirmed.rawValue
    }

    func install() {
        guard !installed else { return }
        installed = true
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func showSIPUserAgentLaunchError() {
        present(
            .information(
                title: NSLocalizedString(
                    "Could not start SIP user agent.",
                    comment: "SIP user agent start error."
                ),
                message: NSLocalizedString(
                    "Please check your network connection and STUN server settings.",
                    comment: "SIP user agent start error informative text."
                )
            )
        )
    }

    func showSTUNCommunicationError() {
        present(
            .information(
                title: NSLocalizedString(
                    "Failed to communicate with STUN server.",
                    comment: "Failed to communicate with STUN server."
                ),
                message: NSLocalizedString(
                    "UDP packets are probably blocked. It is impossible to make or receive calls without that. Make sure that your local firewall and the firewall at your router allow UDP protocol.",
                    comment: "Failed to communicate with STUN server informative text."
                )
            )
        )
    }

    func showQuitConfirmation() {
        present(
            .quitConfirmation(
                title: NSLocalizedString(
                    "Are you sure you want to quit Telephone?",
                    comment: "Telephone quit confirmation."
                ),
                message: NSLocalizedString(
                    "All active calls will be disconnected.",
                    comment: "Telephone quit confirmation informative text."
                )
            )
        )
    }

    private func present(_ dialog: ApplicationDialog) {
        install()
        model.dialog = dialog
        representation.environment.openWindow(id: Self.sceneID)
    }

    private func dismiss() {
        model.dialog = nil
        representation.environment.dismissWindow(id: Self.sceneID)
    }
}

@MainActor
@Observable
private final class ApplicationDialogModel {
    var dialog: ApplicationDialog?
}

private enum ApplicationDialog: Equatable {
    case information(title: String, message: String)
    case quitConfirmation(title: String, message: String)

    var title: String {
        switch self {
        case let .information(title, _),
             let .quitConfirmation(title, _):
            title
        }
    }

    var message: String {
        switch self {
        case let .information(_, message),
             let .quitConfirmation(_, message):
            message
        }
    }
}

private struct ApplicationDialogScene: Scene {
    let model: ApplicationDialogModel
    let dismiss: () -> Void

    var body: some Scene {
        Window(
            NSLocalizedString("Telephone", comment: "Application name."),
            id: ApplicationDialogController.sceneID
        ) {
            if let dialog = model.dialog {
                ApplicationDialogView(
                    dialog: dialog,
                    dismiss: dismiss
                )
            } else {
                EmptyView()
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .commandsRemoved()
    }
}

private struct ApplicationDialogView: View {
    let dialog: ApplicationDialog
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dialog.title)
                        .font(.headline)

                    Text(dialog.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()

                switch dialog {
                case .information:
                    Button(
                        NSLocalizedString("OK", comment: "OK button.")
                    ) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)

                case .quitConfirmation:
                    Button(
                        NSLocalizedString("Cancel", comment: "Cancel button.")
                    ) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(
                        NSLocalizedString("Quit", comment: "Quit button.")
                    ) {
                        dismiss()
                        NotificationCenter.default.post(
                            name: .applicationQuitConfirmed,
                            object: nil
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 430)
        .windowDismissBehavior(.disabled)
        .windowMinimizeBehavior(.disabled)
        .windowResizeBehavior(.disabled)
    }
}
