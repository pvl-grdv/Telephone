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

    init(clipboard: Clipboard = SystemClipboard.shared) {
        self.clipboard = clipboard
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
            }
        )
    }

    func show(_ records: [PresentationCallHistoryRecord]) {
        model.show(records)
    }

    func focusSearch() {
        model.requestSearchFocus()
    }
}
