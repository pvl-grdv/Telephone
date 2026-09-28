//
//  AccountControllers.swift
//  Telephone
//
//  Main-actor collection of account controllers.
//

import Foundation
import PJSIPBridge

@MainActor
final class AccountControllers {
    private var controllers: [AccountController] = []

    var all: [AccountController] {
        controllers
    }

    var enabled: [AccountController] {
        controllers.filter(\.enabled)
    }

    subscript(index: Int) -> AccountController {
        get { controllers[index] }
        set { controllers[index] = newValue }
    }

    func index(of controller: AccountController) -> Int {
        controllers.firstIndex { $0 === controller } ?? NSNotFound
    }

    func add(_ controller: AccountController) {
        controllers.append(controller)
    }

    func removeController(at index: Int) {
        controllers.remove(at: index)
    }

    func remove(at index: Int) {
        controllers.remove(at: index)
    }

    func insert(_ controller: AccountController, at index: Int) {
        controllers.insert(controller, at: index)
    }

    func callController(byIdentifier identifier: String) -> CallController? {
        for accountController in enabled {
            for callController in accountController.callControllers {
                if callController.identifier == identifier {
                    return callController
                }
            }
        }
        return nil
    }

    func haveActiveCallControllers() -> Bool {
        enabled.contains { accountController in
            accountController.callControllers.contains(where: \.hasActiveCall)
        }
    }

    func unhandledIncomingCallsCount() -> Int {
        enabled.reduce(into: 0) { count, accountController in
            for callController in accountController.callControllers {
                if callController.call?.isIncoming == true
                    && callController.callUnhandled
                {
                    count += 1
                }
            }
        }
    }

    func showIncomingCallWindows() {
        for accountController in enabled {
            for callController in accountController.callControllers {
                guard let call = callController.call else { continue }

                if call.identifier != kAKSIPUserAgentInvalidIdentifier
                    && call.state == PJSIP_INV_STATE_INCOMING
                {
                    callController.showWindow(nil)
                }
            }
        }
    }

    func updateCallsShouldDisplayAccountInfo() {
        let shouldDisplay = enabled.count > 1

        for controller in controllers {
            controller.callsShouldDisplayAccountInfo = shouldDisplay
        }
    }

    func hangUpCallsAndRemoveAccountsFromUserAgent() {
        for accountController in enabled {
            for callController in accountController.callControllers {
                callController.hangUpCall()
            }

            accountController.removeAccountFromUserAgent()
        }
    }

    func flushPendingCustomerContextChanges() async {
        for controller in controllers {
            await controller.flushPendingCustomerContextChanges()
        }
    }

    func registerAllAccounts() {
        for controller in enabled {
            controller.registerAccount()
        }
    }

    func unregisterAllAccounts() {
        for controller in enabled where controller.accountRegistered {
            controller.unregisterAccount()
        }
    }
}
