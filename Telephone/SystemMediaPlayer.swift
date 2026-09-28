//
//  SystemMediaPlayer.swift
//  Telephone
//
//  Private MediaRemote bridge for this personal macOS fork.
//

import Darwin
import Foundation
import UseCases

final class SystemMediaPlayer: MusicPlayer, @unchecked Sendable {
    private typealias SendCommand =
        @convention(c) (Int32, CFDictionary?) -> Bool

    private static let mediaRemotePath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let pauseCommand: Int32 = 1

    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var sendCommand: SendCommand?

    init() {
        mediaRemoteHandle = dlopen(
            Self.mediaRemotePath,
            RTLD_LAZY | RTLD_LOCAL
        )

        guard let mediaRemoteHandle else {
            Log.media.notice(
                "System media control unavailable: could not load MediaRemote"
            )
            return
        }

        if let symbol = dlsym(
            mediaRemoteHandle,
            "MRMediaRemoteSendCommand"
        ) {
            sendCommand = unsafeBitCast(symbol, to: SendCommand.self)
        } else {
            Log.media.notice(
                "System media control unavailable: MediaRemote transport symbol is missing"
            )
        }
    }

    deinit {
        if let mediaRemoteHandle {
            dlclose(mediaRemoteHandle)
        }
    }

    func pause() {
        DispatchQueue.main.async { [weak self] in
            guard let sendCommand = self?.sendCommand else { return }

            _ = sendCommand(Self.pauseCommand, nil)
        }
    }

    func resume() {
        // Modern macOS gates MediaRemote now-playing reads for third-party
        // processes. Without a reliable way to know whether Telephone actually
        // paused active media, sending Play here could start media that was
        // already paused before the call. Keep resume as a safe no-op.
    }
}
