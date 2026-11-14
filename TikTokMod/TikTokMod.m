//
//  TikTokMod.m
//
#import "TikTokMod.h"
#import "TikTokModHub.h"
#import "TikTokModSettings.h"

__attribute__((constructor))
static void TikTokModInit(void) {
    @autoreleasepool {
        NSLog(@"TikTokMod loaded");
        NSLog(@"[TikTokMod] TikTokMod loaded (47.7.0 skeleton, no real hooks yet)");
        [TikTokMod installHooks];
    }
}

@implementation TikTokMod

+ (void)installHooks {
    // Skeleton: no real TikTok classes are hooked yet.
    // Hook sites are added here after R1/R2 deliver the class map,
    // each one via +safeSwizzleClass: so a missing target is a no-op.
    NSLog(@"[TikTokMod] installHooks: skeleton — 0 hook sites installed, 41 toggle slots registered");
    (void)[TikTokModSettings shared];
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

@end
