#ifndef _MRNowPlayingClientProtobuf_h
#define _MRNowPlayingClientProtobuf_h

#import <Foundation/Foundation.h>

@interface _MRNowPlayingClientProtobuf : NSObject <NSCopying>

@property (assign, nonatomic) BOOL hasProcessIdentifier;
@property (assign, nonatomic) int processIdentifier;
@property (nonatomic, readonly) BOOL hasBundleIdentifier;
@property (nonatomic, retain) NSString *bundleIdentifier;
@property (nonatomic, readonly) BOOL hasParentApplicationBundleIdentifier;
@property (nonatomic, readonly, retain) NSString *parentApplicationBundleIdentifier;
@property (assign, nonatomic) BOOL hasProcessUserIdentifier;
@property (assign, nonatomic) int processUserIdentifier;
@property (assign, nonatomic) BOOL hasNowPlayingVisibility;
@property (assign, nonatomic) int nowPlayingVisibility;
@property (nonatomic, readonly) BOOL hasTintColor;
@property (nonatomic, readonly) BOOL hasDisplayName;
@property (nonatomic, readonly, retain) NSString *displayName;

- (void)copyTo:(id)arg1;
- (void)mergeFrom:(id)arg1;
- (BOOL)hasBundleIdentifier;
- (id)nowPlayingVisibilityAsString:(int)arg1;
- (int)StringAsNowPlayingVisibility:(id)arg1;

@end

#endif /* _MRNowPlayingClientProtobuf_h */
