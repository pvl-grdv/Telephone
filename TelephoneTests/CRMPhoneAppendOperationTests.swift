import Foundation
import Testing

@MainActor
struct CRMPhoneAppendOperationTests {
    @Test func preDispatchCancellationNeverBecomesAnUnknownWrite() throws {
        let operation = CRMPhoneAppendOperation()
        let attempt = try #require(operation.begin())
        operation.invalidatePresentation()
        #expect(operation.state == .idle)
        #expect(!operation.dispatch(attempt))
        operation.fail(attempt, error: CancellationError())
        #expect(operation.state == .idle)
    }

    @Test func repeatedCancellationAndPrematureReadsCannotEraseAnInFlightWrite() throws {
        let operation = CRMPhoneAppendOperation()
        let attempt = try #require(operation.begin())
        #expect(operation.dispatch(attempt))
        operation.invalidatePresentation()
        operation.invalidatePresentation()
        operation.acceptFreshRead()
        #expect(operation.state == .failed(.phoneWriteUnconfirmed))
        #expect(operation.hasPendingRequest)
        #expect(operation.begin() == nil)
        operation.finish(attempt, added: true)
        #expect(!operation.hasPendingRequest)
        #expect(operation.state == .failed(.phoneWriteUnconfirmed))
        operation.invalidatePresentation()
        #expect(operation.state == .failed(.phoneWriteUnconfirmed))
        operation.acceptFreshRead()
        #expect(operation.state == .idle)
    }

    @Test(arguments: [CRMGatewayError.unavailable, .invalidResponse, .phoneWriteUnconfirmed])
    func ambiguousDispatchedErrorsRequireFreshRead(_ error: CRMGatewayError) throws {
        let operation = CRMPhoneAppendOperation()
        let attempt = try #require(operation.begin())
        #expect(operation.dispatch(attempt))
        operation.fail(attempt, error: error)
        #expect(operation.state == .failed(.phoneWriteUnconfirmed))
        #expect(!operation.hasPendingRequest)
    }

    @Test(arguments: [CRMGatewayError.forbidden, .unauthorized, .conflict, .rateLimited])
    func typedRefusalsRemainVisible(_ error: CRMGatewayError) throws {
        let operation = CRMPhoneAppendOperation()
        let attempt = try #require(operation.begin())
        #expect(operation.dispatch(attempt))
        operation.fail(attempt, error: error)
        #expect(operation.state == .failed(error))
    }

    @Test func cancellingAReadOnlyWindowDoesNotInvalidateAnotherWindowsWrite() throws {
        let operation = CRMPhoneAppendOperation()
        let attempt = try #require(operation.begin())
        #expect(operation.dispatch(attempt))
        operation.cancelPresentation(for: nil)
        #expect(operation.state == .saving)
        operation.finish(attempt, added: true)
        #expect(operation.state == .saved(added: true))
    }

    @Test func aReadOverlappingAnAppendCannotClearItsUnconfirmedOutcome() throws {
        let registry = CRMPhoneAppendRegistry()
        let operation = registry.operation(origin: "https://gateway.example", phone: "+70005550101", companyID: 123)
        let beforeWrite = registry.readReceipt()
        let attempt = try #require(operation.begin())
        #expect(operation.dispatch(attempt))
        let duringWrite = registry.readReceipt()
        operation.invalidatePresentation()
        operation.finish(attempt, added: true)
        #expect(!registry.acceptFreshRead(origin: "https://gateway.example", phone: "+70005550101", companyID: 123, receipt: beforeWrite))
        #expect(!registry.acceptFreshRead(origin: "https://gateway.example", phone: "+70005550101", companyID: 123, receipt: duringWrite))
        #expect(operation.begin() == nil)
        #expect(registry.acceptFreshRead(origin: "https://gateway.example", phone: "+70005550101", companyID: 123, receipt: registry.readReceipt()))
        #expect(operation.state == .idle)
    }

    @Test func registryRetainsTheSameAttemptAcrossWindowsAndIsolatesOtherTargets() throws {
        let registry = CRMPhoneAppendRegistry()
        let first = registry.operation(origin: "https://gateway.example", phone: "+70005550101", companyID: 123)
        let attempt = try #require(first.begin())
        #expect(first.dispatch(attempt))
        first.invalidatePresentation()
        let reopened = registry.operation(origin: "https://gateway.example", phone: "+70005550101", companyID: 123)
        #expect(reopened === first)
        #expect(reopened.state == .failed(.phoneWriteUnconfirmed))
        #expect(reopened.begin() == nil)
        #expect(registry.operation(origin: "https://other.example", phone: "+70005550101", companyID: 123) !== first)
        #expect(registry.operation(origin: "https://gateway.example", phone: "+70005550102", companyID: 123) !== first)
        #expect(registry.operation(origin: "https://gateway.example", phone: "+70005550101", companyID: 456) !== first)
    }
}
