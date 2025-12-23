#ifndef PrivateMediaRemote__MRNowPlayingClientProtobuf_h
#define PrivateMediaRemote__MRNowPlayingClientProtobuf_h

@interface _MRNowPlayingClientProtobuf : NSObject <NSCopying> {
	NSString *_bundleIdentifier;
	NSString *_displayName;
	int _nowPlayingVisibility;
	NSString *_parentApplicationBundleIdentifier;
	int _processIdentifier;
	int _processUserIdentifier;
	struct {
		unsigned int nowPlayingVisibility: 1;
		unsigned int processIdentifier: 1;
		unsigned int processUserIdentifier: 1;
		unsigned int isEmptyDeprecated: 1;
	} _has;
}

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
- (BOOL)hasTintColor;

@end

#endif /* PrivateMediaRemote__MRNowPlayingClientProtobuf_h */
