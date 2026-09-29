//
//  CallHistoryPresenter.swift
//  Telephone
//

import SwiftUI

@MainActor
final class CallHistoryPresenter: CallHistoryView {
    weak var target: CallHistoryViewEventTarget? {
        didSet {
            target?.shouldReloadData()
        }
    }

    var recordCount: Int {
        model.allRecords.count
    }

    var hasSelection: Bool {
        model.selectedRecord != nil
    }

    var hasRecords: Bool {
        !model.allRecords.isEmpty
    }

    private let model = CallHistoryViewModel()
    private let clipboard: Clipboard
    private let crmLookupModel: CRMHistoryLookupModel?
    private let accountUUID: String?

    init(
        clipboard: Clipboard = MacClipboard.shared,
        crmLookupModel: CRMHistoryLookupModel? = nil,
        accountUUID: String? = nil
    ) {
        self.clipboard = clipboard
        self.crmLookupModel = crmLookupModel
        self.accountUUID = accountUUID
    }

    var contentView: some View {
        CallHistoryScreen(
            model: model,
            call: { [weak self] identifier in
                self?.target?.didPickRecord(withIdentifier: identifier)
            },
            copy: { [weak self] address in
                self?.clipboard.copy(address)
            },
            deleteRecord: { [weak self] identifier in
                self?.target?.shouldRemoveRecord(withIdentifier: identifier)
            },
            deleteAll: { [weak self] in
                self?.target?.shouldRemoveAllRecords()
            },
            crmLookupModel: crmLookupModel,
            crmAccountUUID: accountUUID
        )
    }

    func show(_ records: [PresentationCallHistoryRecord]) {
        model.show(records)
    }

    func focusSearch() {
        model.requestSearchFocus()
    }

    func closeCRM() {
        model.pendingCRMRecord = nil
        crmLookupModel?.close()
    }
}
