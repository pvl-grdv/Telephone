//
//  SystemMediaPlayer.m
//  Telephone
//
//  Private MediaRemote bridge for this personal macOS fork.
//

#import "SystemMediaPlayer.h"

#import <dlfcn.h>

typedef void (*MRGetNowPlayingApplicationIsPlayingFunction)(
    dispatch_queue_t queue,
    void (^completion)(Boolean isPlaying)
);
typedef Boolean (*MRSendCommandFunction)(NSInteger command, NSDictionary * _Nullable userInfo);

static NSString * const kMediaRemotePath =
    @"/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote";
static const NSInteger kMediaRemotePlayCommand = 0;
static const NSInteger kMediaRemotePauseCommand = 1;

@interface SystemMediaPlayer ()

@property(nonatomic) void *mediaRemoteHandle;
@property(nonatomic) MRGetNowPlayingApplicationIsPlayingFunction getIsPlaying;
@property(nonatomic) MRSendCommandFunction sendCommand;
@property(nonatomic) BOOL pauseRequested;
@property(nonatomic) BOOL didPause;
@property(nonatomic) NSUInteger requestGeneration;

@end

@implementation SystemMediaPlayer

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _mediaRemoteHandle = dlopen(kMediaRemotePath.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
    if (_mediaRemoteHandle == NULL) {
        NSLog(@"System media control unavailable: could not load MediaRemote");
        return self;
    }

    _getIsPlaying = (MRGetNowPlayingApplicationIsPlayingFunction)
        dlsym(_mediaRemoteHandle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    _sendCommand = (MRSendCommandFunction)
        dlsym(_mediaRemoteHandle, "MRMediaRemoteSendCommand");

    if (_getIsPlaying == NULL || _sendCommand == NULL) {
        NSLog(@"System media control unavailable: required MediaRemote symbols are missing");
    }

    return self;
}

- (void)dealloc {
    if (_mediaRemoteHandle != NULL) {
        dlclose(_mediaRemoteHandle);
    }
}

- (void)pause {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pauseRequested = YES;
        NSUInteger generation = ++self.requestGeneration;

        if (self.getIsPlaying == NULL || self.sendCommand == NULL) {
            return;
        }

        self.getIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            if (!self.pauseRequested ||
                generation != self.requestGeneration ||
                !isPlaying) {
                return;
            }

            if (self.sendCommand(kMediaRemotePauseCommand, nil)) {
                self.didPause = YES;
            }
        });
    });
}

- (void)resume {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pauseRequested = NO;
        ++self.requestGeneration;

        if (!self.didPause) {
            return;
        }

        self.didPause = NO;
        if (self.sendCommand != NULL) {
            self.sendCommand(kMediaRemotePlayCommand, nil);
        }
    });
}

@end
