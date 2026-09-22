//
//  CallContentViewController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class CallContentModel {
    var controller: NSViewController?
    var stateSize = NSSize(width: 300, height: 62)
    var accountDescription = ""
    var showsAccountInfo = false
    var showsAccountFooter = true
}

@MainActor
@objcMembers
final class CallContentViewController: NSViewController {
    fileprivate static let accountInfoHeight: CGFloat = 22

    private let model = CallContentModel()
    private weak var accountController: AccountController?
    private var accountInfoObservation: NSKeyValueObservation?

    @objc(initWithAccountController:)
    convenience init(accountController: AccountController) {
        self.init(accountController: accountController, showsAccountFooter: true)
    }

    @objc(initWithAccountController:showsAccountFooter:)
    init(
        accountController: AccountController,
        showsAccountFooter: Bool
    ) {
        self.accountController = accountController
        model.accountDescription = accountController.accountDescription
        model.showsAccountFooter = showsAccountFooter
        model.showsAccountInfo =
            showsAccountFooter && accountController.callsShouldDisplayAccountInfo
        super.init(nibName: nil, bundle: nil)

        guard showsAccountFooter else { return }

        accountInfoObservation = accountController.observe(
            \.callsShouldDisplayAccountInfo,
            options: [.initial, .new]
        ) { [weak self] _, change in
            Task { @MainActor in
                self?.model.showsAccountInfo = change.newValue ?? false
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSHostingView(rootView: CallContentView(model: model))
    }

    func show(_ controller: NSViewController) {
        guard model.controller !== controller else { return }

        let stateView = controller.view
        let fittingSize = stateView.fittingSize
        let frameSize = stateView.frame.size
        let size = NSSize(
            width: fittingSize.width > 0 ? fittingSize.width : frameSize.width,
            height: fittingSize.height > 0 ? fittingSize.height : frameSize.height
        )
        model.stateSize = NSSize(
            width: max(size.width, 300),
            height: max(size.height, 1)
        )
        model.controller = controller
    }

    func isShowing(_ controller: NSViewController) -> Bool {
        model.controller === controller
    }

    var preferredWindowContentSize: NSSize {
        NSSize(
            width: model.stateSize.width,
            height: model.stateSize.height
                + (model.showsAccountFooter ? Self.accountInfoHeight : 0)
        )
    }
}

private struct CallContentView: View {
    @Bindable var model: CallContentModel

    var body: some View {
        VStack(spacing: 0) {
            if let controller = model.controller {
                LegacyCallStateHost(controller: controller)
                    .id(ObjectIdentifier(controller))
                    .frame(
                        width: model.stateSize.width,
                        height: model.stateSize.height
                    )
            } else {
                Color.clear
                    .frame(
                        width: model.stateSize.width,
                        height: model.stateSize.height
                    )
            }

            if model.showsAccountFooter {
                HStack {
                    if model.showsAccountInfo {
                        Text(model.accountDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(height: CallContentViewController.accountInfoHeight)
            }
        }
        .frame(width: model.stateSize.width)
    }
}

private struct LegacyCallStateHost: NSViewControllerRepresentable {
    let controller: NSViewController

    func makeNSViewController(context: Context) -> NSViewController {
        controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
