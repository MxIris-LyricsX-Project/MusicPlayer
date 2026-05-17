#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <OpenSoftLinking/OpenSoftLinking.h>

#include "MediaRemote.h"

OPEN_SOFT_LINK_PRIVATE_FRAMEWORK_OPTIONAL(MediaRemote)

// Local helpers: declare a private API + its graceful public wrapper in one line.
// Two variants because C does not allow `return expr;` in a void function.
#define MR_SOFT_FN(name, rt, decls, names, fallback)                       \
    OPEN_SOFT_LINK_MAY_FAIL(MediaRemote, name, rt, decls, names)           \
    rt name decls {                                                        \
        if (!canLoad_MediaRemote_##name()) return (fallback);              \
        return name##_soft names;                                          \
    }

#define MR_SOFT_VOID_FN(name, decls, names)                                \
    OPEN_SOFT_LINK_MAY_FAIL(MediaRemote, name, void, decls, names)         \
    void name decls {                                                      \
        if (!canLoad_MediaRemote_##name()) return;                         \
        name##_soft names;                                                 \
    }

MR_SOFT_FN(MRMediaRemoteSendCommand, Boolean,
    (MRCommand command, id userInfo), (command, userInfo), false)
MR_SOFT_VOID_FN(MRMediaRemoteSetElapsedTime,
    (double elapsedTime), (elapsedTime))
MR_SOFT_VOID_FN(MRMediaRemoteRegisterForNowPlayingNotifications,
    (dispatch_queue_t queue), (queue))
MR_SOFT_VOID_FN(MRMediaRemoteUnregisterForNowPlayingNotifications, (void), ())
MR_SOFT_VOID_FN(MRMediaRemoteGetNowPlayingInfo,
    (dispatch_queue_t queue, MRMediaRemoteGetNowPlayingInfoCompletion completion),
    (queue, completion))
MR_SOFT_VOID_FN(MRMediaRemoteGetNowPlayingApplicationPID,
    (dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion completion),
    (queue, completion))
MR_SOFT_VOID_FN(MRMediaRemoteGetNowPlayingApplicationIsPlaying,
    (dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion completion),
    (queue, completion))
MR_SOFT_VOID_FN(MRMediaRemoteGetNowPlayingClient,
    (dispatch_queue_t queue, MRMediaRemoteGetNowPlayingClientCompletion completion),
    (queue, completion))

// NSString constants: each global is initialized to a fallback literal whose
// content is its own name. The constructor below overwrites each one with the
// framework's real exported pointer when available; on failure the fallback
// is kept so callers always see a non-nil NSString *.
#define MR_NSSTRING(name) NSString *name = @#name;
#include "MediaRemoteConstants.def"
#undef MR_NSSTRING

__attribute__((constructor))
static void resolveMediaRemoteConstants(void) {
    if (@available(macOS 15.4, *)) {} else { return; }
    void *handle = MediaRemoteLibrary();
    if (!handle) return;

    #define OSL_RESOLVE_NSSTRING(name) do {                                          \
        NSString * __unsafe_unretained *sym =                                        \
            (NSString * __unsafe_unretained *)dlsym(handle, #name);                  \
        if (sym != NULL && *sym != nil) name = *sym;                                 \
    } while (0)

    #define MR_NSSTRING(name) OSL_RESOLVE_NSSTRING(name);
    #include "MediaRemoteConstants.def"
    #undef MR_NSSTRING

    #undef OSL_RESOLVE_NSSTRING
}
