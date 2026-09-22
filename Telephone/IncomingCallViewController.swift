//
//  IncomingCallViewController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class IncomingCallModel {
    var displayedName = ""
    var status = ""
    var actionsEnabled = true
    var answerFocusRequest = 0
}

@MainActor
@objcMembers
final class IncomingCallViewController: NSViewController, NSMenuItemValidation {
    weak var callController: CallController?

    private let model = IncomingCallModel()
    private var displayedNameObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    @objc(initWithCallController:)
    init(callController: CallController) {
        self.callController = callController
        super.init(nibName: nil, bundle: nil)
        startObserving()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSHostingView(
            rootView: IncomingCallView(
                model: model,
                answer: { [weak self] in self?.acceptCall(nil) },
                decline: { [weak self] in self?.hangUpCall(nil) }
            )
        )
    }

    func removeObservations() {
        displayedNameObservation?.invalidate()
        statusObservation?.invalidate()
        displayedNameObservation = nil
        statusObservation = nil
    }

    func setActionsEnabled(_ enabled: Bool) {
        model.actionsEnabled = enabled
    }

    func focusAnswer() {
        model.answerFocusRequest &+= 1
    }

    @IBAction func acceptCall(_ sender: Any?) {
        callController?.acceptCall()
    }

    @IBAction func hangUpCall(_ sender: Any?) {
        callController?.hangUpCall()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(hangUpCall(_:)) {
            menuItem.title = NSLocalizedString(
                "Decline",
                comment: "Decline. Call menu item."
            )
        }
        return model.actionsEnabled
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

private struct IncomingCallView: View {
    @Bindable var model: IncomingCallModel
    @FocusState private var focusedAction: Action?

    let answer: () -> Void
    let decline: () -> Void

    private enum Action: Hashable {
        case answer
        case decline
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayedName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 12) {
                Button(action: decline) {
                    Label(
                        NSLocalizedString("Decline", comment: "Call decline button."),
                        systemImage: "phone.down.fill"
                    )
                }
                .keyboardShortcut(.cancelAction)
                .focused($focusedAction, equals: .decline)
                .disabled(!model.actionsEnabled)

                Button(action: answer) {
                    Label(
                        NSLocalizedString("Answer", comment: "Call answer button."),
                        systemImage: "phone.fill"
                    )
                }
                .keyboardShortcut(.defaultAction)
                .focused($focusedAction, equals: .answer)
                .disabled(!model.actionsEnabled)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(width: 300, height: 84)
        .onAppear {
            focusedAction = .answer
        }
        .onChange(of: model.answerFocusRequest) {
            focusedAction = .answer
        }
    }
}
