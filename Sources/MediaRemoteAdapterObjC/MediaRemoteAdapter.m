// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <unistd.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "MediaRemote.h"
#import "MediaRemoteAdapter.h"
#import "MediaRemoteAdapterKeys.h"

static CFRunLoopRef _runLoop = NULL;
static dispatch_queue_t _queue;
static dispatch_block_t _debounce_block = NULL;
static NSArray<NSString *> *_targetBundleIdentifiers = NULL;
static BOOL _debugDumpEnabled = NO;

static void printOut(NSString *message) {
    fprintf(stdout, "%s\n", [message UTF8String]);
    fflush(stdout);
}

static void printErr(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    fflush(stderr);
}

static NSString *formatError(NSError *error) {
    return
    [NSString stringWithFormat:@"%@ (%@:%ld)", [error localizedDescription],
     [error domain], (long)[error code]];
}

static NSString *serializeData(NSDictionary *data, NSString *notificationName) {
    NSError *error;
    NSDictionary *wrappedData = @{
        @"notificationName": notificationName,
        @"payload" : data != nil ? data : @{},
    };
    NSData *serialized = [NSJSONSerialization dataWithJSONObject:wrappedData
                                                         options:0
                                                           error:&error];
    if (!serialized) {
        printErr([NSString stringWithFormat:@"Failed for serialize data: %@",
                  formatError(error)]);
        return nil;
    }
    return [[NSString alloc] initWithData:serialized
                                 encoding:NSUTF8StringEncoding];
}

static NSMutableDictionary * convertNowPlayingInformation(NSDictionary *information) {
    
    if (!information) {
        return nil;
    }
    
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    
    void (^setKey)(id, id) = ^(id key, id fromKey) {
        id value = [NSNull null];
        if (information != nil) {
            id result =
            information[fromKey];
            if (result != nil) {
                value = result;
            }
        }
        [data setObject:value forKey:key];
    };
    
    void (^setValue)(id, id (^)(void)) = ^(id key, id (^evaluate)(void)) {
        id value = nil;
        if (information != nil) {
            value = evaluate();
        }
        if (value != nil) {
            [data setObject:value forKey:key];
        } else {
            [data setObject:[NSNull null] forKey:key];
        }
    };
    
    setKey(kTitle, kMRMediaRemoteNowPlayingInfoTitle);
    setKey(kArtist, kMRMediaRemoteNowPlayingInfoArtist);
    setKey(kAlbum, kMRMediaRemoteNowPlayingInfoAlbum);
    setKey(@"uniqueIdentifier", kMRMediaRemoteNowPlayingInfoUniqueIdentifier);
    setValue(kDurationMicros, ^id {
        id duration =
        information[kMRMediaRemoteNowPlayingInfoDuration];
        if (duration != nil) {
            NSTimeInterval durationMicros = [duration doubleValue] * 1000 * 1000;
            if (isinf(durationMicros) || isnan(durationMicros)) {
                return nil;
            }
            return @(floor(durationMicros));
        }
        return nil;
    });
    setValue(kElapsedTimeMicros, ^id {
        id elapsedTimeValue =
        information[kMRMediaRemoteNowPlayingInfoElapsedTime];
        if (elapsedTimeValue != nil) {
            NSTimeInterval elapsedTimeMicros =
            [elapsedTimeValue doubleValue] * 1000 * 1000;
            if (isinf(elapsedTimeMicros) || isnan(elapsedTimeMicros)) {
                return nil;
            }
            return @(floor(elapsedTimeMicros));
        }
        return nil;
    });
    setValue(kTimestampEpochMicros, ^id {
        NSDate *timestampValue =
        information[kMRMediaRemoteNowPlayingInfoTimestamp];
        if (timestampValue != nil) {
            NSTimeInterval timestampEpoch = [timestampValue timeIntervalSince1970];
            NSTimeInterval timestampEpochMicro = timestampEpoch * 1000 * 1000;
            return @(floor(timestampEpochMicro));
        }
        return nil;
    });
    setKey(kArtworkMimeType, kMRMediaRemoteNowPlayingInfoArtworkMIMEType);
    setValue(kArtworkDataBase64, ^id {
        NSData *artworkDataValue =
        (NSData *)information[kMRMediaRemoteNowPlayingInfoArtworkData];
        if (artworkDataValue != nil) {
            return [artworkDataValue base64EncodedStringWithOptions:0];
        }
        return nil;
    });

    if (_debugDumpEnabled) {
        // Surface every entry in the source dictionary so the Swift side can
        // see fields this adapter normally drops. Strings/numbers pass through;
        // dates become epoch seconds; NSData is replaced with a length marker;
        // everything else falls back to -description.
        NSMutableDictionary *fullDump = [NSMutableDictionary dictionary];
        [information enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            NSString *keyString = [key description];
            if ([value isKindOfClass:[NSString class]] ||
                [value isKindOfClass:[NSNumber class]]) {
                fullDump[keyString] = value;
            } else if ([value isKindOfClass:[NSDate class]]) {
                fullDump[keyString] = @([(NSDate *)value timeIntervalSince1970]);
            } else if ([value isKindOfClass:[NSData class]]) {
                fullDump[keyString] = [NSString stringWithFormat:@"<NSData length=%lu>",
                                       (unsigned long)[(NSData *)value length]];
            } else {
                fullDump[keyString] = [value description];
            }
        }];
        data[@"__debugFullDump"] = fullDump;
    }

    return data;
}


// Always sends the full data payload. No more diffing.
static void printData(NSDictionary *data, NSString *notificationName) {
    NSString *serialized = serializeData(data, notificationName);
    if (serialized != nil) {
        printOut(serialized);
    }
}

// Centralized function to process track info.
// It converts, filters, and prints the final JSON data.
static void processNowPlayingInfo(NSDictionary *nowPlayingInfo, BOOL isPlaying, _MRNowPlayingClientProtobuf *client) {
    if (nowPlayingInfo == nil || [nowPlayingInfo count] == 0) {
        printData(nil, kMRMediaRemoteNowPlayingInfoDidChangeNotification);
        return;
    }
    id title = nowPlayingInfo[kMRMediaRemoteNowPlayingInfoTitle];
    if (title == nil || title == [NSNull null] || ([title isKindOfClass:[NSString class]] && [(NSString *)title length] == 0)) {
        printData(nil, kMRMediaRemoteNowPlayingInfoDidChangeNotification);
        return;
    }
    
    NSString *clientBundleIdentifier = client.bundleIdentifier;
    NSString *parentApplicationBundleIdentifier = client.parentApplicationBundleIdentifier;
    
    if (parentApplicationBundleIdentifier) {
        clientBundleIdentifier = parentApplicationBundleIdentifier;
    }
    
    if (clientBundleIdentifier && _targetBundleIdentifiers.count > 0 && ![_targetBundleIdentifiers containsObject:clientBundleIdentifier]) {
        return;
    }
    
    NSMutableDictionary *data = convertNowPlayingInformation(nowPlayingInfo);
    [data setObject:@(isPlaying) forKey:(NSString *)kIsPlaying];

    // Surface the now-playing client's identity in every payload so the host
    // can: (1) display the source app, (2) detect iOS-on-Mac apps that abuse
    // NowPlayingInfo fields (packing "song — artist" into one field, lyrics
    // into another) and apply field recovery only for those.
    //
    // Note: at runtime this can be `MRClient` (a plain Obj-C class with these
    // properties) or `_MRNowPlayingClientProtobuf` (where the same properties
    // exist alongside `hasXxx` accessors). Both paths expose the named
    // properties, so a plain nil-check works for both — calling `hasXxx`
    // crashes when MRClient is the receiver (no such selector).
    if (client.bundleIdentifier) {
        [data setObject:client.bundleIdentifier forKey:@"bundleIdentifier"];
    }
    if (client.parentApplicationBundleIdentifier) {
        [data setObject:client.parentApplicationBundleIdentifier forKey:@"parentApplicationBundleIdentifier"];
    }
    if (client.processIdentifier > 0) {
        [data setObject:@(client.processIdentifier) forKey:@"processIdentifier"];
    }
    if (client.displayName) {
        [data setObject:client.displayName forKey:@"applicationName"];
    }

    printData(data, kMRMediaRemoteNowPlayingInfoDidChangeNotification);
}

static void processPlaybackState(id playbackState) {
    if (playbackState) {
        printData(@{ @"playbackState": @([playbackState integerValue])}, kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification);
    } else {
        printData(nil, kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification);
    }

}

// Fetches all necessary information (track info, playing state, PID)
// and passes it to the processing function.
static void fetchAndProcess(void (^completion)(void)) {
    MRMediaRemoteGetNowPlayingInfo(_queue, ^(CFDictionaryRef information) {
        if (information == NULL) {
            printData(nil, kMRMediaRemoteNowPlayingInfoDidChangeNotification);
            if (completion) {
                completion();
            }
            return;
        }
        NSDictionary *infoDict = [(__bridge NSDictionary *)information copy];
        MRMediaRemoteGetNowPlayingClient(_queue, ^(_MRNowPlayingClientProtobuf * _Nullable client) {
            MRMediaRemoteGetNowPlayingApplicationIsPlaying(_queue, ^(Boolean isPlaying) {
                processNowPlayingInfo(infoDict, isPlaying, client);
                if (completion) {
                    completion();
                }
            });
        });
    });
}

// C function implementations to be called from Perl
void bootstrap(void) {
    _queue = dispatch_queue_create("mediaremote-adapter", DISPATCH_QUEUE_SERIAL);
    
    // Read the target bundle identifier from the environment variable.
    // This is set by the Perl script based on the `--id` command-line argument.
    const char *bundleIdEnv = getenv("MEDIAREMOTEADAPTER_bundle_identifier");
    if (bundleIdEnv != NULL) {
        _targetBundleIdentifiers = [[NSString stringWithUTF8String:bundleIdEnv] componentsSeparatedByString:@"|"];
    }

    // Read the debug-dump toggle from the environment variable. The Perl
    // script sets it to "1" when --debug-dump is on the command line, which
    // makes convertNowPlayingInformation embed the full source dictionary
    // under the `__debugFullDump` key in the JSON payload.
    const char *debugDumpEnv = getenv("MEDIAREMOTEADAPTER_debug_dump");
    if (debugDumpEnv != NULL && strcmp(debugDumpEnv, "1") == 0) {
        _debugDumpEnabled = YES;
    }
}

void loop(void) {
    _runLoop = CFRunLoopGetCurrent();
    
    MRMediaRemoteRegisterForNowPlayingNotifications(_queue);
    
    // --- Initial Fetch ---
    // Fetch the current state immediately when the loop starts, so we don't
    // have to wait for a media change event.
    // We schedule this on our serial queue to ensure the run loop is active.
    dispatch_async(_queue, ^{
        fetchAndProcess(nil);
    });
    
    [[NSNotificationCenter defaultCenter]
     addObserverForName:(NSString *)kMRMediaRemoteNowPlayingInfoDidChangeNotification
     object:nil
     queue:nil
     usingBlock:^(NSNotification * _Nonnull notification) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), _queue, ^{
            fetchAndProcess(nil);
        });
    }];
    
    [[NSNotificationCenter defaultCenter]
     addObserverForName:kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification
     object:nil
     queue:nil
     usingBlock:^(NSNotification * _Nonnull notification) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), _queue, ^{
            processPlaybackState(notification.userInfo[@"kMRMediaRemotePlaybackStateUserInfoKey"]);
        });
    }];
    
    CFRunLoopRun();
}



void play(void) {
    MRMediaRemoteSendCommand(kMRPlay, nil);
}

void pause_command(void) {
    MRMediaRemoteSendCommand(kMRPause, nil);
}

void toggle_play_pause(void) {
    MRMediaRemoteSendCommand(kMRTogglePlayPause, nil);
}

void next_track(void) {
    MRMediaRemoteSendCommand(kMRNextTrack, nil);
}

void previous_track(void) {
    MRMediaRemoteSendCommand(kMRPreviousTrack, nil);
}

void stop_command(void) {
    MRMediaRemoteSendCommand(kMRStop, nil);
}

void update_player_state(void) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    dispatch_async(_queue, ^{
        fetchAndProcess(^{
            dispatch_semaphore_signal(semaphore);
        });
    });
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
}

void set_time_from_env(void) {
    const char *timeStr = getenv("MEDIAREMOTE_SET_TIME");
    if (timeStr == NULL) {
        return;
    }
    
    double time = atof(timeStr);
    MRMediaRemoteSetElapsedTime(time);
}
