//
//  DTMFInputSurface.swift
//  Telephone
//

import Foundation
import SwiftUI

enum DTMFKeyRouting {
    static let characters =
        CharacterSet(charactersIn: "0123456789*#abcdrABCDR")

    static func shouldHandle(
        _ text: String,
        isCallSurfaceFocused: Bool
    ) -> Bool {
        guard isCallSurfaceFocused, !text.isEmpty else {
            return false
        }

        return text.unicodeScalars.allSatisfy(characters.contains)
    }
}

struct DTMFInputSurface<Content: View>: View {
    @FocusState private var isFocused: Bool

    let focusRequest: Int
    let sendDTMF: (String) -> Void
    let content: Content

    init(
        focusRequest: Int,
        sendDTMF: @escaping (String) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.focusRequest = focusRequest
        self.sendDTMF = sendDTMF
        self.content = content()
    }

    var body: some View {
        content
            .focusable(interactions: .edit)
            .focused($isFocused)
            .focusEffectDisabled()
            .onChange(of: focusRequest) {
                isFocused = true
            }
            .onKeyPress(
                characters: DTMFKeyRouting.characters,
                phases: .down
            ) { press in
                guard DTMFKeyRouting.shouldHandle(
                    press.characters,
                    isCallSurfaceFocused: isFocused
                ) else {
                    return .ignored
                }

                sendDTMF(press.characters)
                return .handled
            }
    }
}
