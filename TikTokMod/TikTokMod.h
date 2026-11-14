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

/// Fail-soft class lookup: returns Nil + NSLog if the class is absent.
+ (nullable Class)safeClass:(NSString *)className;

@end

NS_ASSUME_NONNULL_END
