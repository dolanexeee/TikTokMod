//
//  TikTokMod.h
//  TikTokMod — native ObjC dylib for decrypted TikTok 47.7.0
//  (com.zhiliaoapp.musically). Method-swizzling hooks, feature-gated,
//  fail-soft: a missing class/selector is a no-op with an NSLog, never a crash.
//
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface TikTokMod : NSObject

/// Install hooks. Skeleton: logs only — real hook sites land here
/// once the research agents (R1/R2) deliver the class map.
+ (void)installHooks;

/// Fail-soft swizzle: exchanges implementations only if BOTH the class
/// and both selectors exist. Returns YES on success, NO (with NSLog) otherwise.
+ (BOOL)safeSwizzleClass:(Class)cls
        originalSelector:(SEL)originalSelector
        swizzledSelector:(SEL)swizzledSelector;

/// Same contract as +safeSwizzleClass:, for CLASS methods (metaclass).
/// Needed for TTKABTest flags, AWEFeedAdController +preprocessAwemes:,
/// TTKStudioPublishPrecheckHandler prechecks, TTKCIShareABRepostShare +maxLength.
+ (BOOL)safeSwizzleClassMethod:(Class)cls
              originalSelector:(SEL)originalSelector
              swizzledSelector:(SEL)swizzledSelector;

/// Fail-soft class lookup: returns Nil + NSLog if the class is absent.
+ (nullable Class)safeClass:(NSString *)className;

@end

/// Crash-trail log (v2): append a timestamped line to
/// Documents/TikTokMod/diag.log, synchronously (so the line is on disk
/// before the caller proceeds — a crash right after still leaves a trail),
/// and mirror it to NSLog. Safe to call from any thread.
void TMLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Absolute path of the diag log file (for the hub's share row).
NSString *TMLogPath(void);

NS_ASSUME_NONNULL_END
