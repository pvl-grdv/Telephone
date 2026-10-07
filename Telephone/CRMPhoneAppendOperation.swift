import Foundation
import Observation

enum CRMPhoneLinkState: Equatable {
    case idle
    case refreshing
    case saving
    case saved(added: Bool)
    case failed(CRMGatewayError)
}

typealias CRMHistoryPhoneLinkState = CRMPhoneLinkState

/// An explicitly confirmed write has a lifetime separate from its presentation.
/// Cancellation can stop waiting, but cannot prove that the gateway rejected it.
@MainActor
@Observable
final class CRMPhoneAppendOperation {
    var state: CRMPhoneLinkState = .idle
    private(set) var hasPendingRequest = false
    private(set) var revision = 0
    private var requiresFreshRead = false
    private var lastFailure: CRMGatewayError?
    private var attemptID: UUID?
    private var dispatched = false
    private var presentationInvalidated = false

    func begin() -> UUID? {
        guard attemptID == nil, !hasPendingRequest, !requiresFreshRead, state == .idle else { return nil }
        let id = UUID()
        revision &+= 1
        attemptID = id
        hasPendingRequest = true
        dispatched = false
        presentationInvalidated = false
        state = .saving
        return id
    }

    func dispatch(_ id: UUID) -> Bool {
        guard attemptID == id, !presentationInvalidated else { return false }
        dispatched = true
        hasPendingRequest = true
        requiresFreshRead = true
        return true
    }

    func finish(_ id: UUID, added: Bool) {
        guard attemptID == id else { return }
        revision &+= 1
        attemptID = nil
        hasPendingRequest = false
        requiresFreshRead = presentationInvalidated
        lastFailure = presentationInvalidated ? .phoneWriteUnconfirmed : nil
        state = presentationInvalidated ? .failed(.phoneWriteUnconfirmed) : .saved(added: added)
    }

    func fail(_ id: UUID, error: Error) {
        guard attemptID == id else { return }
        revision &+= 1
        attemptID = nil
        hasPendingRequest = false
        if presentationInvalidated, dispatched {
            state = .failed(.phoneWriteUnconfirmed)
        } else if dispatched {
            let typed = (error as? CRMGatewayError) ?? .phoneWriteUnconfirmed
            switch typed {
            case .forbidden, .unauthorized, .conflict, .rateLimited:
                state = .failed(typed)
            default:
                state = .failed(.phoneWriteUnconfirmed)
            }
        } else {
            state = error is CancellationError ? .idle : .failed((error as? CRMGatewayError) ?? .unavailable)
        }
        if case .failed(let error) = state {
            requiresFreshRead = true
            lastFailure = error
        }
    }

    func failRefresh(_ error: Error) {
        guard !hasPendingRequest else { return }
        if requiresFreshRead {
            state = .failed(lastFailure ?? .phoneWriteUnconfirmed)
        } else {
            state = error is CancellationError ? .idle : .failed((error as? CRMGatewayError) ?? .unavailable)
        }
    }

    func cancelPresentation(for id: UUID?) {
        // A read-only window does not own another window's in-flight write.
        if let attemptID, attemptID != id { return }
        invalidatePresentation()
    }

    func invalidatePresentation() {
        presentationInvalidated = true
        if dispatched, attemptID != nil {
            lastFailure = .phoneWriteUnconfirmed
            state = .failed(.phoneWriteUnconfirmed)
        } else if attemptID != nil {
            attemptID = nil
            hasPendingRequest = false
            state = .idle
        } else if requiresFreshRead {
            state = .failed(lastFailure ?? .phoneWriteUnconfirmed)
        } else if state == .refreshing {
            state = .idle
        }
        // Repeated cancellation must preserve a settled unconfirmed result.
    }

    func abandonBeforeDispatch(_ id: UUID) {
        guard attemptID == id, !dispatched else { return }
        attemptID = nil
        hasPendingRequest = false
        state = .idle
    }

    func acceptFreshRead() {
        guard !hasPendingRequest, attemptID == nil else { return }
        requiresFreshRead = false
        lastFailure = nil
        state = .idle
    }
}

/// App-owned ledger: reopening a call or history window cannot bypass an
/// unresolved write for the same gateway, organization and caller.
@MainActor
final class CRMPhoneAppendRegistry {
    fileprivate struct Identity: Hashable {
        let origin: String
        let phone: String
        let companyID: Int
    }
    struct ReadReceipt {
        fileprivate let revisions: [Identity: Int]
    }
    private var operations: [Identity: CRMPhoneAppendOperation] = [:]

    func readReceipt() -> ReadReceipt {
        ReadReceipt(revisions: operations.mapValues { $0.revision })
    }

    @discardableResult
    func acceptFreshRead(origin: String, phone: String, companyID: Int, receipt: ReadReceipt) -> Bool {
        let identity = Identity(origin: origin, phone: phone, companyID: companyID)
        let operation = operation(origin: origin, phone: phone, companyID: companyID)
        guard operation.revision == (receipt.revisions[identity] ?? 0), !operation.hasPendingRequest else { return false }
        operation.acceptFreshRead()
        return true
    }

    func operation(origin: String, phone: String, companyID: Int) -> CRMPhoneAppendOperation {
        let identity = Identity(origin: origin, phone: phone, companyID: companyID)
        if let operation = operations[identity] { return operation }
        let operation = CRMPhoneAppendOperation()
        operations[identity] = operation
        return operation
    }
}
