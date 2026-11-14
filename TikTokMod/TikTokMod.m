//
//  TikTokMod.m
//
#import "TikTokMod.h"
#import "TikTokModHub.h"
#import "TikTokModSettings.h"
#import "TikTokModV1.h"
#import "TikTokModV2.h"

__attribute__((constructor))
static void TikTokModInit(void) {
    @autoreleasepool {
        NSLog(@"TikTokMod loaded");
        NSLog(@"[TikTokMod] TikTokMod loaded (47.7.0 V2, 37 features per DYLIB-DESIGN.md §4)");
        [TikTokMod installHooks];
    }
}

@implementation TikTokMod

+ (void)installHooks {
    // V1 (DYLIB-DESIGN.md §4): hub-entry hook first, then every resolvable
    // site. Each site is fail-soft via +safeSwizzleClass: / :Method: and is
    // retried from AWEFeedRootViewController viewDidLoad if its class was
    // not yet loaded. Behaviour is gated per call by the live toggle.
    [TikTokModV1 installV1Hooks];
    [TikTokModV2 installV2Hooks];
    (void)[TikTokModSettings shared];
    NSLog(@"[TikTokMod] installHooks: V1+V2 installed (42 toggle slots registered; "
          @"compile-verified only — no iOS device on the build VM, nothing runtime-tested)");
}

+ (nullable Class)safeClass:(NSString *)className {
    Class cls = NSClassFromString(className);
    if (!cls) {
        NSLog(@"[TikTokMod] safeClass: class %@ not found, skipping (fail-soft)", className);
    }
    return cls;
}

+ (BOOL)safeSwizzleClass:(Class)cls
        originalSelector:(SEL)originalSelector
        swizzledSelector:(SEL)swizzledSelector {
    if (!cls) {
        NSLog(@"[TikTokMod] safeSwizzle: nil class, skipping");
        return NO;
    }
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method swizzled = class_getInstanceMethod(cls, swizzledSelector);
    if (!original || !swizzled) {
        NSLog(@"[TikTokMod] safeSwizzle: %@ %@ / %@ missing (orig=%p swz=%p), skipping",
              cls, NSStringFromSelector(originalSelector),
              NSStringFromSelector(swizzledSelector),
              original, swizzled);
        return NO;
    }
    method_exchangeImplementations(original, swizzled);
    NSLog(@"[TikTokMod] safeSwizzle: %@ %@ <-> %@", cls,
          NSStringFromSelector(originalSelector),
          NSStringFromSelector(swizzledSelector));
    return YES;
}

+ (BOOL)safeSwizzleClassMethod:(Class)cls
              originalSelector:(SEL)originalSelector
              swizzledSelector:(SEL)swizzledSelector {
    if (!cls) {
        NSLog(@"[TikTokMod] safeSwizzleClassMethod: nil class, skipping");
        return NO;
    }
    Method original = class_getClassMethod(cls, originalSelector);
    Method swizzled = class_getClassMethod(cls, swizzledSelector);
    if (!original || !swizzled) {
        NSLog(@"[TikTokMod] safeSwizzleClassMethod: %@ +%@ / +%@ missing (orig=%p swz=%p), skipping",
              cls, NSStringFromSelector(originalSelector),
              NSStringFromSelector(swizzledSelector),
              original, swizzled);
        return NO;
    }
    method_exchangeImplementations(original, swizzled);
    NSLog(@"[TikTokMod] safeSwizzleClassMethod: %@ +%@ <-> +%@", cls,
          NSStringFromSelector(originalSelector),
          NSStringFromSelector(swizzledSelector));
    return YES;
}

@end
