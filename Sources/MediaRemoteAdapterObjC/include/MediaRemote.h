/*
 * Media remote framework header.
 *
 * Copyright (c) 2013-2014 Cykey (David Murray)
 * All rights reserved.
 */

#ifndef MEDIAREMOTE_H_
#define MEDIAREMOTE_H_

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <objc/objc.h>
#include "_MRNowPlayingClientProtobuf.h"

#if __cplusplus
extern "C" {
#endif
    
#pragma mark - Notifications and Keys
#define MR_NSSTRING(name) extern NSString * _Nonnull name;
#include "MediaRemoteConstants.def"
#undef MR_NSSTRING

    NS_HEADER_AUDIT_BEGIN(nullability, sendability)
    
#pragma mark - API
    typedef enum {
        kMRPlay = 0,
        kMRPause = 1,
        kMRTogglePlayPause = 2,
        kMRStop = 3,
        kMRNextTrack = 4,
        kMRPreviousTrack = 5,
        kMRToggleShuffle = 6,
        kMRToggleRepeat = 7,
        kMRStartForwardSeek = 8,
        kMREndForwardSeek = 9,
        kMRStartBackwardSeek = 10,
        kMREndBackwardSeek = 11,
        kMRGoBackFifteenSeconds = 12,
        kMRSkipFifteenSeconds = 13,
        kMRLikeTrack = 0x6A,
        kMRBanTrack = 0x6B,
        kMRAddTrackToWishList = 0x6C,
        kMRRemoveTrackFromWishList = 0x6D
    } MRCommand;
    
    Boolean MRMediaRemoteSendCommand(MRCommand command, id _Nullable userInfo);
    void MRMediaRemoteSetElapsedTime(double elapsedTime);
    void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue);
    void MRMediaRemoteUnregisterForNowPlayingNotifications();
    
    typedef void (^MRMediaRemoteGetNowPlayingInfoCompletion)(CFDictionaryRef information);
    typedef void (^MRMediaRemoteGetNowPlayingApplicationPIDCompletion)(int PID);
    typedef void (^MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion)(Boolean isPlaying);
    typedef void (^MRMediaRemoteGetNowPlayingClientCompletion)(_MRNowPlayingClientProtobuf * _Nullable client);
    
    void MRMediaRemoteGetNowPlayingApplicationPID(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion completion);
    void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingInfoCompletion completion);
    void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion completion);
    void MRMediaRemoteGetNowPlayingClient(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingClientCompletion completion);

    NS_HEADER_AUDIT_END(nullability, sendability)


#if __cplusplus
}
#endif


#endif /* MEDIAREMOTE_H_ */
