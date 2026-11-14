//
//  TikTokMod.m
//
#import "TikTokMod.h"
#import "TikTokModHub.h"
#import "TikTokModSettings.h"
#import "TikTokModV1.h"
#import "TikTokModV2.h"
#import "TikTokModHard.h"

// Crash trail (v2): synchronous, unbuffered append to
// Documents/TikTokMod/diag.log. The user can read it in the Files app
// (On My iPhone → TikTok → TikTokMod → diag.log) or share it from the
// hub's "Share diagnostic log" row. One line per event, timestamped.
NSString *TMLogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [[docs stringByAppendingPathComponent:@"TikTokMod"] stringByAppendingPathComponent:@"diag.log"];
}

void TMLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    @synchronized (lock) {
        NSString *path = TMLogPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [path stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss.SSS";
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:[NSDate date]], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        } else {
            @try {
                [fh seekToEndOfFile];
                [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (__unused NSException *e) {
            }
            [fh closeFile];
        }
    }
    NSLog(@"[TikTokMod][diag] %@", msg);
}

__attribute__((constructor))
static void TikTokModInit(void) {
    @autoreleasepool {
        TMLog(@"LOADED TikTokMod %@ (dylib constructor)", kTikTokModVersion);
        NSLog(@"TikTokMod loaded");
        NSLog(@"[TikTokMod] TikTokMod loaded (%@, 42 features per DYLIB-DESIGN.md §4; "
              @"HARD phase UNVERIFIED-RUNTIME — pinning bypass unproven without a traffic capture)", kTikTokModVersion);
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
    [TikTokModHard installHardHooks];
    (void)[TikTokModSettings shared];
    TMLog(@"INSTALL complete: V1+V2+HARD installers ran (per-site results above)");
    NSLog(@"[TikTokMod] installHooks: V1+V2+HARD installed (42 toggle slots registered; "
          @"compile-verified only — no iOS device on the build VM, nothing runtime-tested; "
          @"HARD downloads UNVERIFIED-RUNTIME, #24 PARTIAL, #44 DEFER)");
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
