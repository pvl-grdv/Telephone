//
//  AccountControllers.swift
//  Telephone
//
//  Main-actor collection of account controllers.
//

import Foundation

@MainActor
@objcMembers
final class AccountControllers: NSObject {
    private var controllers: [AccountController] = []

    var all: [AccountController] {
        controllers
    }

    var enabled: [AccountController] {
        controllers.filter(\.enabled)
    }

    @objc(objectAtIndexedSubscript:)
    func object(atIndexedSubscript index: Int) -> AccountController {
        controllers[index]
    }

    @objc(setObject:atIndexedSubscript:)
    func setObject(
        _ object: AccountController,
        atIndexedSubscript index: Int
    ) {
        controllers[index] = object
    }

    @objc(indexOfController:)
    func index(of controller: AccountController) -> Int {
        controllers.firstIndex { $0 === controller } ?? NSNotFound
    }

    @objc(addController:)
    func add(_ controller: AccountController) {
        controllers.append(controller)
    }

    @objc(removeControllerAtIndex:)
    func removeController(at index: Int) {
        controllers.remove(at: index)
    }

    @objc(insertController:atIndex:)
    func insert(_ controller: AccountController, at index: Int) {
        controllers.insert(controller, at: index)
    }

    @objc(callControllerByIdentifier:)
    func callController(byIdentifier identifier: String) -> CallController? {
        for accountController in enabled {
            for case let callController as CallController
                in accountController.callControllers
            {
                if callController.identifier == identifier {
                    return callController
                }
            }
        }
        return nil
    }

    @objc(haveActiveCallControllers)
    func haveActiveCallControllers() -> Bool {
        enabled.contains { accountController in
            accountController.callControllers.contains { item in
                (item as? CallController)?.callActive == true
            }
        }
    }

    @objc(unhandledIncomingCallsCount)
    func unhandledIncomingCallsCount() -> Int {
        enabled.reduce(into: 0) { count, accountController in
            for case let callController as CallController
                in accountController.callControllers
            {
                if callController.call?.isIncoming == true
                    && callController.callUnhandled
                {
                    count += 1
                }
            }
        }
    }

    @objc(showIncomingCallWindows)
    func showIncomingCallWindows() {
        for accountController in enabled {
            for case let callController as CallController
                in accountController.callControllers
            {
                guard let call = callController.call else { continue }

                if call.identifier >= 0
                    && call.state.rawValue == 2
                {
                    callController.showWindow(nil)
                }
            }
        }
    }

    @objc(updateCallsShouldDisplayAccountInfo)
    func updateCallsShouldDisplayAccountInfo() {
        let shouldDisplay = enabled.count > 1

        for controller in controllers {
            controller.callsShouldDisplayAccountInfo = shouldDisplay
        }
    }

    @objc(hangUpCallsAndRemoveAccountsFromUserAgent)
    func hangUpCallsAndRemoveAccountsFromUserAgent() {
        for accountController in enabled {
            for case let callController as CallController
                in accountController.callControllers
            {
                callController.hangUpCall()
            }

            accountController.removeAccountFromUserAgent()
        }
    }

    @objc(registerAllAccounts)
    func registerAllAccounts() {
        for controller in enabled {
            controller.registerAccount()
        }
    }

    @objc(unregisterAllAccounts)
    func unregisterAllAccounts() {
        for controller in enabled where controller.accountRegistered {
            controller.unregisterAccount()
        }
    }
}
