//
//  CallPresentationRegressionTests.swift
//  TelephonePresentationTests
//

import Testing

@MainActor
struct CallPresentationRegressionTests {
    @Test
    func dtmfOnlyRoutesFromFocusedCallSurface() {
        #expect(
            DTMFKeyRouting.shouldHandle(
                "5",
                isCallSurfaceFocused: true
            )
        )
        #expect(
            !DTMFKeyRouting.shouldHandle(
                "5",
                isCallSurfaceFocused: false
            )
        )
        #expect(
            DTMFKeyRouting.shouldHandle(
                "#",
                isCallSurfaceFocused: true
            )
        )
        #expect(
            !DTMFKeyRouting.shouldHandle(
                "x",
                isCallSurfaceFocused: true
            )
        )
        #expect(
            !DTMFKeyRouting.shouldHandle(
                "",
                isCallSurfaceFocused: true
            )
        )
    }

    @Test
    func regularCallStateTransitionsKeepDTMFFocusScopedToActiveCall() {
        let model = CallWindowModel(isTransfer: false)

        #expect(model.session.phase == .active)
        #expect(model.callSurfaceFocusRequest == 0)

        model.showIncomingState()
        #expect(model.session.phase == .incoming)
        #expect(model.session.incomingActionsEnabled)
        #expect(!model.session.showsProgress)

        model.requestCallSurfaceFocus()
        #expect(model.callSurfaceFocusRequest == 0)

        model.showActiveState()
        model.requestCallSurfaceFocus()
        #expect(model.session.phase == .active)
        #expect(model.callSurfaceFocusRequest == 1)

        model.session.showsProgress = true
        model.showEndedState()
        model.requestCallSurfaceFocus()
        #expect(model.session.phase == .ended)
        #expect(!model.session.showsProgress)
        #expect(model.callSurfaceFocusRequest == 1)
    }

    @Test
    func transferStateTransitionsResetDestinationActionAndAllowDTMFWhenActive() {
        let model = CallWindowModel(isTransfer: true)

        #expect(model.session.phase == .transferDestination)

        model.transferActionEnabled = true
        model.showTransferDestinationState()
        #expect(model.session.phase == .transferDestination)
        #expect(!model.transferActionEnabled)

        model.showActiveState()
        model.requestCallSurfaceFocus()
        #expect(model.session.phase == .transferActive)
        #expect(model.callSurfaceFocusRequest == 1)

        model.showEndedState()
        #expect(model.session.phase == .transferEnded)

        model.showIncomingState()
        #expect(model.session.phase == .transferEnded)
    }

    @Test
    func commandStateObservesTheSessionWithoutWindowControlCopies() {
        let model = CallWindowModel(isTransfer: false)
        let session = model.session

        model.showIncomingState()
        session.incomingActionsEnabled = false
        #expect(!CallCommandAvailability.answer(session.commandState))

        model.showActiveState()
        session.muteEnabled = true
        session.muted = true
        session.holdEnabled = true
        session.transferEnabled = true
        #expect(session.commandState.phase == .active)
        #expect(session.commandState.muted)
        #expect(CallCommandAvailability.mute(session.commandState))
        #expect(CallCommandAvailability.hold(session.commandState))
        #expect(CallCommandAvailability.transfer(session.commandState))

        session.showsProgress = true
        model.showEndedState()
        #expect(session.commandState.phase == .ended)
        #expect(!session.showsProgress)
    }

    @Test
    func callMenuAvailabilityTracksCallPhase() {
        let incoming = CallCommandState(
            phase: .incoming,
            muted: false,
            held: false,
            muteEnabled: false,
            holdEnabled: false,
            transferEnabled: false,
            incomingActionsEnabled: true,
            hangUpEnabled: true,
            redialEnabled: false
        )

        #expect(CallCommandAvailability.answer(incoming))
        #expect(CallCommandAvailability.hangUp(incoming))
        #expect(!CallCommandAvailability.mute(incoming))
        #expect(!CallCommandAvailability.hold(incoming))
        #expect(!CallCommandAvailability.transfer(incoming))
        #expect(!CallCommandAvailability.redial(incoming))

        let active = CallCommandState(
            phase: .active,
            muted: false,
            held: false,
            muteEnabled: true,
            holdEnabled: true,
            transferEnabled: true,
            incomingActionsEnabled: false,
            hangUpEnabled: true,
            redialEnabled: false
        )

        #expect(CallCommandAvailability.mute(active))
        #expect(CallCommandAvailability.hold(active))
        #expect(CallCommandAvailability.transfer(active))
        #expect(CallCommandAvailability.hangUp(active))
        #expect(!CallCommandAvailability.answer(active))
        #expect(!CallCommandAvailability.redial(active))

        let transferActive = CallCommandState(
            phase: .transferActive,
            muted: false,
            held: true,
            muteEnabled: false,
            holdEnabled: true,
            transferEnabled: false,
            incomingActionsEnabled: false,
            hangUpEnabled: true,
            redialEnabled: false
        )

        #expect(CallCommandAvailability.hold(transferActive))
        #expect(CallCommandAvailability.hangUp(transferActive))
        #expect(!CallCommandAvailability.transfer(transferActive))

        let ended = CallCommandState(
            phase: .ended,
            muted: false,
            held: false,
            muteEnabled: false,
            holdEnabled: false,
            transferEnabled: false,
            incomingActionsEnabled: false,
            hangUpEnabled: false,
            redialEnabled: true
        )

        #expect(CallCommandAvailability.redial(ended))
        #expect(!CallCommandAvailability.hangUp(ended))
    }

    @Test
    func callWindowCloseNotificationIsOneShotUntilReset() {
        var gate = CallWindowCloseNotificationGate()

        let firstConsume = gate.consume()
        let duplicateConsume = gate.consume()

        #expect(firstConsume)
        #expect(!duplicateConsume)
        #expect(gate.hasNotified)

        gate.reset()
        #expect(!gate.hasNotified)

        let consumeAfterReset = gate.consume()
        let duplicateAfterReset = gate.consume()

        #expect(consumeAfterReset)
        #expect(!duplicateAfterReset)
    }

    @Test
    func weakRegistryUnregistersExplicitlyAndPrunesReleasedValues() {
        let registry = WeakObjectRegistry<String, RegistryObject>()

        var first: RegistryObject? = RegistryObject()
        registry.register(first!, key: "first")

        #expect(registry.registeredCount == 1)
        #expect(registry.generation == 1)
        #expect(registry.value(for: "first") === first)

        registry.unregister(key: "first")
        #expect(registry.registeredCount == 0)
        #expect(registry.generation == 2)

        first = nil

        var second: RegistryObject? = RegistryObject()
        weak let weakSecond = second
        registry.register(second!, key: "second")
        #expect(registry.registeredCount == 1)

        second = nil
        #expect(weakSecond == nil)
        #expect(registry.value(for: "second") == nil)
        #expect(registry.registeredCount == 0)
    }
}

private final class RegistryObject {}
