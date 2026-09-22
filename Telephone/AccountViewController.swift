//
//  AccountViewController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI
import UseCases

@MainActor
@Observable
private final class AccountContentModel {
    var isActive = false
}

@MainActor
@objcMembers
final class AccountViewController: NSViewController {
    private let activeAccountViewController: ActiveAccountViewController
    private let callHistoryViewController: CallHistoryViewController
    private let callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory
    private let account: Account
    private let model = AccountContentModel()

    private var callHistoryViewEventTarget: CallHistoryViewEventTarget?

    @objc(initWithActiveAccountViewController:callHistoryViewController:callHistoryViewEventTargetFactory:account:)
    init(
        activeAccountViewController: ActiveAccountViewController,
        callHistoryViewController: CallHistoryViewController,
        callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory,
        account: Account
    ) {
        self.activeAccountViewController = activeAccountViewController
        self.callHistoryViewController = callHistoryViewController
        self.callHistoryViewEventTargetFactory = callHistoryViewEventTargetFactory
        self.account = account
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var allowsCallDestinationInput: Bool {
        activeAccountViewController.allowsCallDestinationInput
    }

    override func loadView() {
        view = NSHostingView(
            rootView: AccountContentView(
                model: model,
                activeAccountViewController: activeAccountViewController,
                callHistoryViewController: callHistoryViewController
            )
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        callHistoryViewEventTargetFactory.make(
            account: account,
            view: callHistoryViewController
        ) { [weak self] target in
            guard let self else { return }
            self.callHistoryViewEventTarget = target
            self.callHistoryViewController.target = target
        }
    }

    func showActiveState() {
        withAnimation(.easeInOut(duration: 0.2)) {
            model.isActive = true
        }
        activeAccountViewController.allowCallDestinationInput()
    }

    func showInactiveStateAnimated(_ animated: Bool) {
        activeAccountViewController.disallowCallDestinationInput()

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.isActive = false
            }
        } else {
            model.isActive = false
        }
    }

    func makeCallToDestination(_ destination: String) {
        activeAccountViewController.makeCallToDestination(destination)
    }
}

private struct AccountContentView: View {
    @Bindable var model: AccountContentModel

    let activeAccountViewController: ActiveAccountViewController
    let callHistoryViewController: CallHistoryViewController

    var body: some View {
        VStack(spacing: 0) {
            if model.isActive {
                activeAccountViewController.contentView
                    .transition(.opacity.combined(with: .move(edge: .top)))

                Divider()
            }

            ViewControllerHost(controller: callHistoryViewController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 330, minHeight: 158)
    }
}

private struct ViewControllerHost<Controller: NSViewController>: NSViewControllerRepresentable {
    let controller: Controller

    func makeNSViewController(context: Context) -> Controller {
        controller
    }

    func updateNSViewController(_ nsViewController: Controller, context: Context) {}
}
