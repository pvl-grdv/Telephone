//
//  SystemMediaPlayer.swift
//  Telephone
//
//  Private MediaRemote bridge for this personal macOS fork.
//

import Darwin
import Foundation
import UseCases

final class SystemMediaPlayer: NSObject, MusicPlayer {
    private typealias IsPlayingCompletion =
        @convention(block) (UInt8) -> Void
    private typealias GetIsPlaying =
        @convention(c) (DispatchQueue, IsPlayingCompletion) -> Void
    private typealias SendCommand =
        @convention(c) (Int, NSDictionary?) -> UInt8

    private static let mediaRemotePath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let playCommand = 0
    private static let pauseCommand = 1

    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var getIsPlaying: GetIsPlaying?
    private var sendCommand: SendCommand?

    private var pauseRequested = false
    private var didPause = false
    private var requestGeneration = 0

    override init() {
        super.init()

        mediaRemoteHandle = dlopen(
            Self.mediaRemotePath,
            RTLD_LAZY | RTLD_LOCAL
        )

        guard let mediaRemoteHandle else {
            NSLog(
                "System media control unavailable: could not load MediaRemote"
            )
            return
        }

        if let symbol = dlsym(
            mediaRemoteHandle,
            "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
        ) {
            getIsPlaying = unsafeBitCast(symbol, to: GetIsPlaying.self)
        }

        if let symbol = dlsym(
            mediaRemoteHandle,
            "MRMediaRemoteSendCommand"
        ) {
            sendCommand = unsafeBitCast(symbol, to: SendCommand.self)
        }

        if getIsPlaying == nil || sendCommand == nil {
            NSLog(
                "System media control unavailable: required MediaRemote symbols are missing"
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
            guard let self else { return }

            pauseRequested = true
            requestGeneration &+= 1
            let generation = requestGeneration

            guard
                let getIsPlaying,
                let sendCommand
            else {
                return
            }

            getIsPlaying(.main) { [weak self] isPlaying in
                guard
                    let self,
                    pauseRequested,
                    generation == requestGeneration,
                    isPlaying != 0
                else {
                    return
                }

                if sendCommand(Self.pauseCommand, nil) != 0 {
                    didPause = true
                }
            }
        }
    }

    func resume() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            pauseRequested = false
            requestGeneration &+= 1

            guard didPause else { return }
            didPause = false

            _ = sendCommand?(Self.playCommand, nil)
        }
    }
}
