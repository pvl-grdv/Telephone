//
//  EndedCallViewController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class EndedCallModel {
    var displayedName = ""
    var status = ""
    var redialEnabled = true
}

@MainActor
@objcMembers
class EndedCallViewController: NSViewController {
    weak var callController: CallController?

    fileprivate let model = EndedCallModel()
    private var displayedNameObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    @objc(initWithNibName:callController:)
    init(nibName: String, callController: CallController) {
        self.callController = callController
        super.init(nibName: nil, bundle: nil)
        startObserving()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate var isTransferPresentation: Bool {
        self is EndedCallTransferViewController
    }

    override func loadView() {
        view = NSHostingView(
            rootView: EndedCallView(
                model: model,
                isTransfer: isTransferPresentation,
                redial: { [weak self] in
                    self?.redial(nil)
                },
                cancelTransfer: { [weak self] in
                    (self as? EndedCallTransferViewController)?.cancelTransfer(nil)
                }
            )
        )
    }

    func removeObservations() {
        displayedNameObservation?.invalidate()
        statusObservation?.invalidate()
        displayedNameObservation = nil
        statusObservation = nil
    }

    func setRedialEnabled(_ enabled: Bool) {
        model.redialEnabled = enabled
    }

    @IBAction func redial(_ sender: Any?) {
        callController?.redial()
    }

    @objc func enableRedialButtonTick(_ timer: Foundation.Timer) {
        model.redialEnabled = true
    }

    private func startObserving() {
        guard let callController else { return }

        displayedNameObservation = callController.observe(
            \.displayedName,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            let value = controller.displayedName ?? ""
            Task { @MainActor [weak self] in
                self?.model.displayedName = value
            }
        }

        statusObservation = callController.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            let value = controller.status ?? ""
            Task { @MainActor [weak self] in
                self?.model.status = value
            }
        }
    }
}

@MainActor
@objcMembers
final class EndedCallTransferViewController: EndedCallViewController {
    @IBAction func cancelTransfer(_ sender: Any?) {
        guard let transferController = callController as? CallTransferController else {
            return
        }
        transferController.showInitialState(sender)
    }
}

private struct EndedCallView: View {
    @Bindable var model: EndedCallModel

    let isTransfer: Bool
    let redial: () -> Void
    let cancelTransfer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayedName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(model.status)
                        .foregroundStyle(.secondary)
                        .lineLimit(isTransfer ? 1 : 2)
                }

                Spacer(minLength: 8)

                Button(action: redial) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!model.redialEnabled)
                .help(NSLocalizedString("Call Back", comment: "Call back button."))
                .accessibilityLabel(
                    NSLocalizedString("Call Back", comment: "Call back button.")
                )
            }

            if isTransfer {
                Spacer(minLength: 8)

                HStack {
                    Spacer()

                    Button(
                        NSLocalizedString("Cancel", comment: "Cancel button."),
                        action: cancelTransfer
                    )
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(
            width: isTransfer ? 320 : 300,
            height: isTransfer ? 115 : 84
        )
    }
}
