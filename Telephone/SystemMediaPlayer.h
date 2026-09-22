//
//  SystemMediaPlayer.h
//  Telephone
//
//  Private MediaRemote bridge for this personal macOS fork.
//

@import Foundation;
@import UseCases;

NS_ASSUME_NONNULL_BEGIN

/// Pauses and resumes the current macOS Now Playing session.
///
/// MediaRemote is a private framework. The implementation loads it dynamically
/// so Telephone still launches normally if Apple changes or removes the API.
@interface SystemMediaPlayer : NSObject <MusicPlayer>
@end

NS_ASSUME_NONNULL_END
