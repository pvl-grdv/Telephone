//
//  CallHistoryRow.swift
//  Telephone
//

import SwiftUI

struct CallHistoryRow: View {
    let record: PresentationCallHistoryRecord
    let answer: CRMIncomingCallAnswer?

    private var answeredElsewhere: Bool {
        record.wasNotAnsweredHere && answer?.status == .answered
    }
    private var globallyUnanswered: Bool {
        record.wasNotAnsweredHere && answer?.status == .unanswered
    }
    private var showsMissed: Bool {
        (record.isMissed && !answeredElsewhere) || globallyUnanswered
    }

    private var answerDetail: String? {
        // Even a stale ATS response must not override a locally answered call.
        guard record.wasNotAnsweredHere, let answer else { return nil }
        if answer.status == .answered, let employee = answer.answeredBy {
            return String(
                format: NSLocalizedString("Answered by: %@", comment: "Answering employee from the call service."),
                employee.displayName
            )
        }
        guard answer.status == .unknown else { return nil }
        switch answer.reason {
        case "not-found":
            return NSLocalizedString("ATS: no matching call", comment: "Call answer lookup found no matching PBX record.")
        case "time-mismatch":
            return NSLocalizedString("ATS: call time does not match", comment: "Caller exists in PBX but no record matches the SIP start time.")
        case "ambiguous":
            return NSLocalizedString("ATS: multiple possible calls", comment: "More than one PBX call could match.")
        case "transferred":
            return NSLocalizedString("ATS: transferred call", comment: "Transfer prevents reliable answering employee attribution.")
        case "not-confirmed":
            return NSLocalizedString("ATS: answer not confirmed", comment: "PBX did not confirm a completed answered call.")
        case "identity-unavailable":
            return NSLocalizedString("ATS: employee not identified", comment: "PBX outcome does not identify who answered.")
        default:
            return nil
        }
    }

    private var directionSymbol: String {
        record.isIncoming
            ? "phone.arrow.down.left.fill"
            : "phone.arrow.up.right.fill"
    }

    private var statusText: String {
        if answeredElsewhere {
            return NSLocalizedString("Answered Elsewhere", comment: "Incoming call answered by another employee.")
        }
        if globallyUnanswered {
            return NSLocalizedString("No One Answered", comment: "ATS confirmed an unanswered incoming call.")
        }
        return record.isMissed
            ? NSLocalizedString(
                "Not Answered Here",
                comment: "Incoming call was not answered on this account; overall outcome may be unknown."
            )
            : record.duration
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: directionSymbol)
                .font(.caption)
                .foregroundStyle(
                    showsMissed ? Color.red : Color.secondary
                )
                .frame(width: 16, height: 16)
                .padding(.top, 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.contact.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(
                            showsMissed ? Color.red : Color.primary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(record.contact.title)

                    Text(record.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.contact.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(record.contact.address)

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(
                            showsMissed ? Color.red : Color.secondary
                        )
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .help(statusText)
                }

                if let detail = answerDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(answer?.status == .answered
                            ? NSLocalizedString("Matched by caller number and call time.", comment: "Call answer correlation provenance.")
                            : detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
