//
//  TikTokModHard.m
//  TikTokMod HARD phase (DYLIB-DESIGN.md §4): #10, #18, #24, #25, #27,
//  all gated on the §2.5 pinning bypass.
//
//  PINNING BYPASS — WHAT IT DOES AND DOES NOT COVER (read this first):
//  Covered (ObjC surfaces only, R2 §4.2):
//    (a) AFNetworking AFSecurityPolicy — pinning forced to none,
//        allowInvalidCertificates=YES, validatesDomainName=NO, and
//        evaluateServerTrust:forDomain: forced to YES.
//    (b) NSURLSession delegate auth challenges — the session factory
//        (+sessionWithConfiguration:delegate:delegateQueue:) installs
//        challenge-accept hooks on the delegate's class, so a server-trust
//        challenge is answered with credentialForTrust:.
//    (c) Alamofire ServerTrustManager — the evaluator lookup (if its ObjC
//        selector resolves) is forced to return a DisabledTrustEvaluator.
//  NOT covered:
//    • TTNet's NATIVE layer (libvcn + boringssl). If TikTok pins there,
//      SSL_CTX_set_verify hooks in boringssl are needed — NOT implemented
//      here. The design (§2.5) is explicit: ONLY A RUNTIME TRAFFIC CAPTURE
//      proves the bypass. Until that capture exists, every HARD download
//      feature is UNVERIFIED-RUNTIME. Nothing here claims downloads "work".
//    • bdw_skipAndPassAllServerTrust is a WEBVIEW switch only — it is NOT
//      used here and is NOT assumed to bypass API pinning.
//  The bypass hooks are installed at load but apply ONLY while at least one
//  download toggle (#10 / #18 / #25) is ON; otherwise they call through to
//  stock behaviour. #27 ad filtering needs no network and does not drive
//  the bypass.
//
//  RULES (binding, same as V1/V2): runtime IMP injection only (alias prefix
//  "tm3_orig_"); no categories on TikTok classes; no link-time refs to
//  TikTok classes. Missing class/selector = no-op + NSLog, never a crash.
//  Every hook reads its live toggle per call. Compile + artifact level
//  only: no iOS device exists on the build VM, nothing is runtime-verified.
//
#import "TikTokModHard.h"
#import "TikTokMod.h"
#import "TikTokModSettings.h"
#import "TikTokModV1.h"
#import <objc/message.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Small helpers (file-local mirrors of V1/V2's)
// ---------------------------------------------------------------------------

static TikTokModSettings *TM3Settings(void) { return [TikTokModSettings shared]; }

static BOOL TM3On(NSString *key) { return [TM3Settings() boolForKey:key]; }

/// The pinning bypass applies only while a download feature needs it.
static BOOL TM3BypassOn(void) {
    return TM3On(@"downloadQualitySelection") || TM3On(@"downloadWebSources") ||
           TM3On(@"audioOnlyDownload");
}

/// KVC read that can never throw: returns nil on any failure.
static id TM3Value(id obj, NSString *key) {
    if (!obj || !key) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

static BOOL TM3BoolValue(id obj, NSString *key) {
    id v = TM3Value(obj, key);
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return NO;
}

/// KVC write that can never throw: YES when the key exists and took the value.
static BOOL TM3TrySet(id obj, NSString *key, id value) {
    if (!obj || !key) return NO;
    @try {
        [obj setValue:value forKey:key];
        return YES;
    } @catch (__unused NSException *e) { return NO; }
}

static void TM3WalkViews(UIView *view, void (^block)(UIView *v)) {
    if (!view) return;
    block(view);
    for (UIView *sub in view.subviews) TM3WalkViews(sub, block);
}

static BOOL TM3ClassNameContains(UIView *v, NSString *sub) {
    return [NSStringFromClass([v class]) containsString:sub];
}

static UIWindow * _Nullable TM3KeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindow *w = ((UIWindowScene *)scene).keyWindow;
            if (w) return w;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

static UIViewController * _Nullable TM3TopViewController(void) {
    UIViewController *root = TM3KeyWindow().rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static void TM3AlertFrom(UIViewController *vc, NSString *title, NSString *message) {
    if (!vc) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
// Installer infrastructure (HARD mirror of V2's TM2InstallSite)
// kind: 'v' void, 'B' BOOL (accepts B/c), 'i' integer, '@' object,
//       '?' no return-type check (log-only hooks that ignore the return).
// ---------------------------------------------------------------------------

static BOOL TM3InstallSite(NSString *className, SEL origSel, IMP newImp, IMP *outOrig,
                           BOOL classMethod, char kind) {
    Class cls = [TikTokMod safeClass:className];
    if (!cls) return NO;
    Class target = classMethod ? object_getClass(cls) : cls;
    Method m = classMethod ? class_getClassMethod(cls, origSel)
                           : class_getInstanceMethod(cls, origSel);
    if (!m) {
        NSLog(@"[TikTokMod] HARD site %@ %@ not found, skipping (fail-soft)",
              className, NSStringFromSelector(origSel));
        return NO;
    }
    if (kind != '?') {
        const char *enc = method_getTypeEncoding(m);
        char got = enc ? enc[0] : '?';
        BOOL ok = NO;
        if (kind == 'B') ok = (got == 'B' || got == 'c');
        else if (kind == 'i') ok = (got == 'q' || got == 'i' || got == 'l' || got == 's' ||
                                    got == 'I' || got == 'L' || got == 'S' || got == 'Q');
        else ok = (got == kind);
        if (!ok) {
            NSLog(@"[TikTokMod] HARD site %@ %@: unexpected return type '%c' (wanted '%c'), skipping (fail-soft)",
                  className, NSStringFromSelector(origSel), got, kind);
            return NO;
        }
    }
    // Safe install (V2's rule): if the class does NOT implement the selector
    // itself (inherited), ADD our IMP as the class's own method and keep the
    // inherited IMP as the original — never swap a superclass method.
    *outOrig = method_getImplementation(m);
    if (class_addMethod(target, origSel, newImp, method_getTypeEncoding(m))) {
        NSString *aliasName = [@"tm3_orig_" stringByAppendingString:NSStringFromSelector(origSel)];
        SEL aliasSel = NSSelectorFromString(aliasName);
        class_addMethod(target, aliasSel, *outOrig, method_getTypeEncoding(m));
        NSLog(@"[TikTokMod] HARD hook installed (added override): %@ %@", className, NSStringFromSelector(origSel));
        return YES;
    }
    NSString *aliasName = [@"tm3_orig_" stringByAppendingString:NSStringFromSelector(origSel)];
    SEL aliasSel = NSSelectorFromString(aliasName);
    if (!class_addMethod(target, aliasSel, newImp, method_getTypeEncoding(m))) {
        NSLog(@"[TikTokMod] HARD site %@ %@: alias %@ already exists, skipping",
              className, NSStringFromSelector(origSel), aliasName);
        return NO;
    }
    Method aliasMethod = class_getInstanceMethod(target, aliasSel);
    method_exchangeImplementations(m, aliasMethod);
    NSLog(@"[TikTokMod] HARD hook installed: %@ %@", className, NSStringFromSelector(origSel));
    return YES;
}

/// Try the instance method first, then the class method (for targets whose
/// +/- is not stated in the design).
static BOOL TM3InstallSiteAuto(NSString *className, SEL origSel, IMP newImp, IMP *outOrig, char kind) {
    if (TM3InstallSite(className, origSel, newImp, outOrig, NO, kind)) return YES;
    return TM3InstallSite(className, origSel, newImp, outOrig, YES, kind);
}

// ---------------------------------------------------------------------------
// Pinning bypass — surface (a): AFNetworking AFSecurityPolicy
// (R2: setSSLPinningMode: / policyWithPinningMode: / allowInvalidCertificates
// / validatesDomainName — all settable. AFSSLPinningModeNone == 0.)
// ---------------------------------------------------------------------------

static IMP g3_orig_AFSP_setPinningMode = NULL;
static IMP g3_orig_AFSP_setAllowInvalid = NULL;
static IMP g3_orig_AFSP_setValidatesDomain = NULL;
static IMP g3_orig_AFSP_evaluateTrust = NULL;
static IMP g3_orig_AFSP_policyWithPinningMode = NULL;

static BOOL g3_afspHooked = NO;
static BOOL g3_afspPolicyHooked = NO;

static void TM3Hook_AFSP_setPinningMode(id self, SEL _cmd, long long mode) {
    if (TM3BypassOn()) {
        mode = 0; // AFSSLPinningModeNone
        NSLog(@"[TikTokMod] HARD bypass (a): AFSecurityPolicy pinning forced to none");
    }
    ((void (*)(id, SEL, long long))g3_orig_AFSP_setPinningMode)(self, _cmd, mode);
}

static void TM3Hook_AFSP_setAllowInvalid(id self, SEL _cmd, BOOL allow) {
    if (TM3BypassOn()) allow = YES;
    ((void (*)(id, SEL, BOOL))g3_orig_AFSP_setAllowInvalid)(self, _cmd, allow);
}

static void TM3Hook_AFSP_setValidatesDomain(id self, SEL _cmd, BOOL validates) {
    if (TM3BypassOn()) validates = NO;
    ((void (*)(id, SEL, BOOL))g3_orig_AFSP_setValidatesDomain)(self, _cmd, validates);
}

static BOOL TM3Hook_AFSP_evaluateTrust(id self, SEL _cmd, void *serverTrust, id domain) {
    if (TM3BypassOn()) {
        NSLog(@"[TikTokMod] HARD bypass (a): AFSecurityPolicy evaluateServerTrust forced YES for %@ "
              @"(UNVERIFIED-RUNTIME — TTNet native layer not covered)", domain);
        return YES;
    }
    return ((BOOL (*)(id, SEL, void *, id))g3_orig_AFSP_evaluateTrust)(self, _cmd, serverTrust, domain);
}

static id TM3Hook_AFSP_policyWithPinningMode(id self, SEL _cmd, long long mode) {
    if (TM3BypassOn()) mode = 0; // AFSSLPinningModeNone
    return ((id (*)(id, SEL, long long))g3_orig_AFSP_policyWithPinningMode)(self, _cmd, mode);
}

// ---------------------------------------------------------------------------
// Pinning bypass — surface (b): NSURLSession delegate auth challenges.
// The session factory (+sessionWithConfiguration:delegate:delegateQueue:,
// the path AFNetworking/Alamofire/TTNet wrappers use) installs the
// challenge-accept hooks on the delegate's class, once per class.
// A challenge for server trust is answered with credentialForTrust: while
// the bypass is ON; every other challenge (and every call while OFF) goes
// to the original implementation.
// ---------------------------------------------------------------------------

static IMP g3_orig_NSURLSession_challenge = NULL; // unused: hooks call through via the per-class alias (see above)
static IMP g3_orig_NSURLSession_taskChallenge = NULL; // unused: same reason
static NSMutableSet<NSString *> *g3_challengeHookedClasses = nil;

/// Call-through for the challenge hooks: the installer adds
/// tm3_orig_<selector> on the delegate's class holding THAT class's original
/// IMP, so the hook calls the alias instead of a shared static (several
/// different delegate classes can be hooked; a shared static would call the
/// wrong original).
static void TM3CallOrigChallenge(id self, SEL aliasSel, id session, id challenge, id completionHandler) {
    if (!self || !aliasSel) return;
    if (![self respondsToSelector:aliasSel]) return;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(self, aliasSel, session, challenge, completionHandler);
}

static void TM3CallOrigTaskChallenge(id self, SEL aliasSel, id session, id task, id challenge, id completionHandler) {
    if (!self || !aliasSel) return;
    if (![self respondsToSelector:aliasSel]) return;
    ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(self, aliasSel, session, task, challenge, completionHandler);
}

static void TM3Hook_NSURLSession_challenge(id self, SEL _cmd, id session, id challenge, id completionHandler) {
    if (TM3BypassOn() && challenge) {
        id protectionSpace = TM3Value(challenge, @"protectionSpace");
        NSString *method = TM3Value(protectionSpace, @"authenticationMethod");
        if ([method isEqualToString:@"NSURLAuthenticationMethodServerTrust"]) {
            id serverTrust = TM3Value(protectionSpace, @"serverTrust");
            if (serverTrust) {
                Class credCls = NSClassFromString(@"NSURLCredential");
                SEL credSel = NSSelectorFromString(@"credentialForTrust:");
                id credential = nil;
                if (credCls && [credCls respondsToSelector:credSel]) {
                    credential = ((id (*)(id, SEL, void *))objc_msgSend)(credCls, credSel, (__bridge void *)serverTrust);
                }
                if (credential && completionHandler) {
                    void (^handler)(long long, id) = completionHandler;
                    handler(0, credential); // NSURLSessionAuthChallengeUseCredential == 0
                    NSLog(@"[TikTokMod] HARD bypass (b): server-trust challenge accepted via credentialForTrust: "
                          @"(UNVERIFIED-RUNTIME — TTNet native layer not covered)");
                    return;
                }
            }
        }
    }
    TM3CallOrigChallenge(self,
        NSSelectorFromString(@"tm3_orig_URLSession:didReceiveChallenge:completionHandler:"),
        session, challenge, completionHandler);
}

static void TM3Hook_NSURLSession_taskChallenge(id self, SEL _cmd, id session, id task, id challenge, id completionHandler) {
    if (TM3BypassOn() && challenge) {
        id protectionSpace = TM3Value(challenge, @"protectionSpace");
        NSString *method = TM3Value(protectionSpace, @"authenticationMethod");
        if ([method isEqualToString:@"NSURLAuthenticationMethodServerTrust"]) {
            id serverTrust = TM3Value(protectionSpace, @"serverTrust");
            if (serverTrust) {
                Class credCls = NSClassFromString(@"NSURLCredential");
                SEL credSel = NSSelectorFromString(@"credentialForTrust:");
                id credential = nil;
                if (credCls && [credCls respondsToSelector:credSel]) {
                    credential = ((id (*)(id, SEL, void *))objc_msgSend)(credCls, credSel, (__bridge void *)serverTrust);
                }
                if (credential && completionHandler) {
                    void (^handler)(long long, id) = completionHandler;
                    handler(0, credential); // NSURLSessionAuthChallengeUseCredential == 0
                    NSLog(@"[TikTokMod] HARD bypass (b): task-level server-trust challenge accepted "
                          @"(UNVERIFIED-RUNTIME — TTNet native layer not covered)");
                    return;
                }
            }
        }
    }
    TM3CallOrigTaskChallenge(self,
        NSSelectorFromString(@"tm3_orig_URLSession:task:didReceiveChallenge:completionHandler:"),
        session, task, challenge, completionHandler);
}

/// Install the challenge hooks on a session delegate's class (once per class).
/// The delegate class is a TikTok class, so this is runtime IMP injection
/// (same pattern as V1/V2) — never a category, never a link-time ref.
static void TM3InstallChallengeHooksOnDelegate(id delegate) {
    if (!delegate) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ g3_challengeHookedClasses = [NSMutableSet set]; });
    NSString *className = NSStringFromClass([delegate class]);
    @synchronized (g3_challengeHookedClasses) {
        if ([g3_challengeHookedClasses containsObject:className]) return;
        [g3_challengeHookedClasses addObject:className];
    }
    BOOL ok1 = TM3InstallSite(className,
        NSSelectorFromString(@"URLSession:didReceiveChallenge:completionHandler:"),
        (IMP)TM3Hook_NSURLSession_challenge, &g3_orig_NSURLSession_challenge, NO, 'v');
    BOOL ok2 = TM3InstallSite(className,
        NSSelectorFromString(@"URLSession:task:didReceiveChallenge:completionHandler:"),
        (IMP)TM3Hook_NSURLSession_taskChallenge, &g3_orig_NSURLSession_taskChallenge, NO, 'v');
    if (ok1 || ok2) {
        NSLog(@"[TikTokMod] HARD bypass (b): challenge hooks installed on delegate class %@", className);
    } else {
        NSLog(@"[TikTokMod] HARD bypass (b): delegate class %@ implements neither challenge selector "
              @"(fail-soft — AFSecurityPolicy surface (a) is the remaining ObjC layer)", className);
    }
}

// NSURLSession factory hook (system class — same category pattern V2 uses
// for UIFont). After the exchange, tm3_… holds the ORIGINAL implementation.
@interface NSURLSession (TikTokModHard)
+ (NSURLSession *)tm3_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                      delegate:(nullable id<NSURLSessionDelegate>)delegate
                                 delegateQueue:(nullable NSOperationQueue *)queue;
@end

@implementation NSURLSession (TikTokModHard)

+ (NSURLSession *)tm3_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                      delegate:(nullable id<NSURLSessionDelegate>)delegate
                                 delegateQueue:(nullable NSOperationQueue *)queue {
    NSURLSession *session = [self tm3_sessionWithConfiguration:configuration
                                                      delegate:delegate
                                                 delegateQueue:queue];
    if (delegate) TM3InstallChallengeHooksOnDelegate(delegate);
    return session;
}

@end

// ---------------------------------------------------------------------------
// Pinning bypass — surface (c): Alamofire ServerTrustManager.
// The evaluator lookup selector is Swift-derived and UNVERIFIED: at install
// time the class's methods are enumerated and logged, and the hook is
// attempted only for the expected selector. If it does not resolve, this
// surface is skipped with a log (fail-soft). The disabled evaluator class
// name is likewise tried mangled first, then bare.
// ---------------------------------------------------------------------------

static IMP g3_orig_Alamofire_evaluatorForHost = NULL;
static BOOL g3_alamofireHooked = NO;
static BOOL g3_alamofireAbsentLogged = NO;

static id TM3Hook_Alamofire_evaluatorForHost(id self, SEL _cmd, id host) {
    if (TM3BypassOn()) {
        Class disabledCls = NSClassFromString(@"_TtC9Alamofire21DisabledTrustEvaluator");
        if (!disabledCls) disabledCls = NSClassFromString(@"DisabledTrustEvaluator");
        if (disabledCls) {
            id evaluator = [[disabledCls alloc] init];
            if (evaluator) {
                NSLog(@"[TikTokMod] HARD bypass (c): Alamofire evaluator for %@ forced to DisabledTrustEvaluator "
                      @"(UNVERIFIED-RUNTIME — TTNet native layer not covered)", host);
                return evaluator;
            }
        }
        NSLog(@"[TikTokMod] HARD bypass (c): DisabledTrustEvaluator class not found — falling through to stock evaluator");
    }
    return ((id (*)(id, SEL, id))g3_orig_Alamofire_evaluatorForHost)(self, _cmd, host);
}

static void TM3InstallAlamofireBypass(void) {
    static BOOL enumerated = NO;
    Class mgrCls = NSClassFromString(@"_TtC9Alamofire18ServerTrustManager");
    if (!mgrCls) {
        if (!g3_alamofireAbsentLogged) {
            g3_alamofireAbsentLogged = YES;
            NSLog(@"[TikTokMod] HARD bypass (c): _TtC9Alamofire18ServerTrustManager not found "
                  @"(fail-soft — Alamofire may not be linked in this build)");
        }
        return;
    }
    // Enumerate once: the evaluator-lookup selector is Swift-derived and
    // unverified — log what exists so a runtime run can confirm the name.
    if (!enumerated) {
        enumerated = YES;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(mgrCls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            if ([name containsString:@"valuator"] || [name containsString:@"Trust"]) {
                NSLog(@"[TikTokMod] HARD bypass (c): ServerTrustManager method found: %@", name);
            }
        }
        free(methods);
    }
    if (g3_alamofireHooked) return;
    g3_alamofireHooked = TM3InstallSite(@"_TtC9Alamofire18ServerTrustManager",
        NSSelectorFromString(@"serverTrustEvaluatorForHost:"),
        (IMP)TM3Hook_Alamofire_evaluatorForHost, &g3_orig_Alamofire_evaluatorForHost, NO, '@');
    if (!g3_alamofireHooked) {
        NSLog(@"[TikTokMod] HARD bypass (c): serverTrustEvaluatorForHost: did not resolve — "
              @"surface (c) skipped (fail-soft; check the enumeration log above for the real selector)");
    }
}

// ---------------------------------------------------------------------------
// Bypass installers (a) + (b) — retry-safe, idempotent
// ---------------------------------------------------------------------------

static BOOL g3_bypassInstalled = NO;

static void TM3InstallPinningBypass(void) {
    // (a) AFSecurityPolicy
    Class afsp = [TikTokMod safeClass:@"AFSecurityPolicy"];
    if (afsp && !g3_afspHooked) {
        BOOL ok = YES;
        ok &= TM3InstallSite(@"AFSecurityPolicy", @selector(setSSLPinningMode:),
            (IMP)TM3Hook_AFSP_setPinningMode, &g3_orig_AFSP_setPinningMode, NO, 'v');
        ok &= TM3InstallSite(@"AFSecurityPolicy", @selector(setAllowInvalidCertificates:),
            (IMP)TM3Hook_AFSP_setAllowInvalid, &g3_orig_AFSP_setAllowInvalid, NO, 'v');
        ok &= TM3InstallSite(@"AFSecurityPolicy", @selector(setValidatesDomainName:),
            (IMP)TM3Hook_AFSP_setValidatesDomain, &g3_orig_AFSP_setValidatesDomain, NO, 'v');
        ok &= TM3InstallSite(@"AFSecurityPolicy", NSSelectorFromString(@"evaluateServerTrust:forDomain:"),
            (IMP)TM3Hook_AFSP_evaluateTrust, &g3_orig_AFSP_evaluateTrust, NO, 'B');
        g3_afspHooked = ok;
        if (!ok) {
            NSLog(@"[TikTokMod] HARD bypass (a): AFSecurityPolicy partially hooked — "
                  @"see the per-site logs above (fail-soft)");
        }
    }
    if (afsp && !g3_afspPolicyHooked) {
        g3_afspPolicyHooked = TM3InstallSite(@"AFSecurityPolicy", @selector(policyWithPinningMode:),
            (IMP)TM3Hook_AFSP_policyWithPinningMode, &g3_orig_AFSP_policyWithPinningMode, YES, '@');
    }
    // (b) NSURLSession factory — system class, V2's UIFont pattern.
    if (!g3_bypassInstalled) {
        g3_bypassInstalled = YES;
        [TikTokMod safeSwizzleClassMethod:[NSURLSession class]
                         originalSelector:@selector(sessionWithConfiguration:delegate:delegateQueue:)
                         swizzledSelector:@selector(tm3_sessionWithConfiguration:delegate:delegateQueue:)];
    }
    // (c) Alamofire ServerTrustManager
    TM3InstallAlamofireBypass();
    NSLog(@"[TikTokMod] HARD bypass installed (ObjC surfaces only). "
          @"TTNet native libvcn/boringssl layer NOT covered — only a runtime "
          @"traffic capture proves the bypass. All HARD downloads UNVERIFIED-RUNTIME.");
}

// ---------------------------------------------------------------------------
// Feature bodies — filled in per feature commit (B: #10, C: #18, D: #24,
// E: #25, F: #27). Until then each is a safe no-op that says so.
// ---------------------------------------------------------------------------

static NSArray *g3_lastCapturedURLs = nil;
static NSString *g3_lastWebSourceURL = nil;

@implementation TikTokModHard

+ (void)installHardHooks {
    TM3InstallPinningBypass();
    [self retryDeferredInstalls];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tm_settingsChanged:)
                                                 name:TikTokModSettingsDidChangeNotification
                                               object:nil];
    NSLog(@"[TikTokMod] HARD installHooks: pinning bypass + 5 features "
          @"(#10 #18 #24 #25 #27; #44 DEFER — not implemented)");
}

+ (void)tm_settingsChanged:(NSNotification *)note {
    NSString *key = note.userInfo[@"key"];
    if (!key) return;
    if ([key isEqualToString:@"regionSwitching"] || [key isEqualToString:@"regionCode"]) {
        [self applyStoredRegion];
    }
}

+ (void)retryDeferredInstalls {
    // Re-attempt the bypass surfaces (classes load lazily) and the per-feature
    // sites (added in commits B–F). Idempotent: installed sites are skipped.
    TM3InstallPinningBypass();
}

+ (NSString *)pinningBypassStatus {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"AFSecurityPolicy: %@",
                      g3_afspHooked ? @"hooked" : @"absent/unhooked"]];
    [parts addObject:[NSString stringWithFormat:@"NSURLSession delegate: %@",
                      g3_bypassInstalled ? @"factory hooked" : @"not hooked"]];
    [parts addObject:[NSString stringWithFormat:@"Alamofire: %@",
                      g3_alamofireHooked ? @"hooked" : @"absent/unhooked"]];
    [parts addObject:@"TTNet native (libvcn/boringssl): NOT covered"];
    [parts addObject:TM3BypassOn() ? @"Bypass ACTIVE (a download toggle is ON)"
                                   : @"Bypass idle (no download toggle ON)"];
    return [parts componentsJoinedByString:@" • "];
}

+ (BOOL)shouldDropAdItem:(__unused id)item {
    // Filled in commit F (#27).
    return NO;
}

+ (void)hideAdViewsInView:(__unused UIView *)cellView {
    // Filled in commit F (#27).
}

+ (NSDictionary<NSString *, NSString *> *)currentVideoQualityURLs {
    // Filled in commit B (#10).
    return @{};
}

+ (NSArray *)lastCapturedDownloadURLs {
    return g3_lastCapturedURLs ?: @[];
}

+ (void)downloadCurrentVideoFromViewController:(UIViewController *)vc {
    // Filled in commit B (#10).
    TM3AlertFrom(vc, @"Download quality (#10)",
        @"Not implemented yet in this build — the HARD quality picker lands in the next commit.");
}

+ (void)downloadFromWebSourceFromViewController:(UIViewController *)vc {
    // Filled in commit C (#18).
    (void)g3_lastWebSourceURL;
    TM3AlertFrom(vc, @"Web sources (#18)",
        @"Not implemented yet in this build — the web-source picker lands in the next commit.");
}

+ (void)pickRegionFromViewController:(UIViewController *)vc {
    // Filled in commit D (#24).
    TM3AlertFrom(vc, @"Region switching (#24)",
        @"Not implemented yet in this build — the region picker lands in the next commit.");
}

+ (void)applyStoredRegion {
    // Filled in commit D (#24).
}

+ (void)downloadCurrentAudioFromViewController:(UIViewController *)vc {
    // Filled in commit E (#25).
    TM3AlertFrom(vc, @"Audio-only download (#25)",
        @"Not implemented yet in this build — the audio downloader lands in the next commit.");
}

@end
