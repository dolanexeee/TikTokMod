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
// #10 Download quality — capture + picker + skip-quality
// No stock picker exists (both passes). The variants are the playAddr keys
// from INJECTION-ANALYSIS.md (playAddr, playAddr265, playAddrH264,
// playAddrLowbr, playAddrBytevc1, playAddr3DFallback, downloadUrl).
// Capture points:
//   • AWEMediaDownloadAwemeStage downloadVideoWithURLList: — every stock
//     download passes its URL list here; the hook records the list (the
//     picker fallback) and, when a quality choice is stored, hands the stock
//     stage ONLY the matching URL ("skip quality").
//   • The current aweme model (via V1's +activePlayer) — KVC reads of the
//     playAddr variants; the picker offers those URLs directly.
// Matching a stored variant key to a URL is HEURISTIC and UNVERIFIED:
// exact model-URL match first, then a URL-substring match for the variant
// marker (265 / h264 / lowbr / bytevc1). If neither matches, the stock list
// is passed through untouched and the reason is logged. Nothing here claims
// a variant maps to a distinct quality until a runtime capture proves it.
// #44's download_no_watermark_addr is deliberately NOT read here (DEFER).
// ---------------------------------------------------------------------------

static IMP g3_orig_DownloadStage_downloadVideo = NULL;
static IMP g3_orig_DownloadComponent_didFinish = NULL;
static BOOL g3_installed_DownloadStage = NO;
static BOOL g3_installed_DownloadComponent = NO;

static NSArray<NSString *> *TM3VariantKeys(void) {
    return @[@"playAddr", @"playAddr265", @"playAddrH264", @"playAddrLowbr",
             @"playAddrBytevc1", @"playAddr3DFallback", @"downloadUrl", @"downloadAddr"];
}

/// Best-effort URL string from a model value: NSString (http…), NSArray of
/// strings, or a model/dict with a urlList/url_list/url key. nil otherwise.
static NSString * _Nullable TM3URLStringFromValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)value;
        if ([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"]) return s;
        return nil;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        for (id el in (NSArray *)value) {
            NSString *s = TM3URLStringFromValue(el);
            if (s) return s;
        }
        return nil;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"url_list", @"urlList", @"url", @"playUrl", @"play_url"]) {
            NSString *s = TM3URLStringFromValue([(NSDictionary *)value objectForKey:key]);
            if (s) return s;
        }
        return nil;
    }
    if (value) {
        for (NSString *key in @[@"urlList", @"url_list", @"url", @"playUrl", @"play_url"]) {
            NSString *s = TM3URLStringFromValue(TM3Value(value, key));
            if (s) return s;
        }
    }
    return nil;
}

/// The current video's aweme model, reached from V1's active player via KVC.
/// The player→aweme key is not in the evidence files, so several likely keys
/// are tried; a miss is nil (fail-soft), never a guess.
static id _Nullable TM3CurrentAwemeModel(void) {
    id player = [TikTokModV1 activePlayer];
    if (!player) return nil;
    for (NSString *key in @[@"aweme", @"awemeModel", @"currentAweme", @"model", @"currentModel"]) {
        id model = TM3Value(player, key);
        if (model) return model;
    }
    // The player itself may expose the video container directly.
    if (TM3Value(player, @"video")) return player;
    return nil;
}

/// Variant key → URL string for the current video (model read only).
static NSDictionary<NSString *, NSString *> *TM3QualityURLsFromAweme(id aweme) {
    if (!aweme) return @{};
    id video = TM3Value(aweme, @"video") ?: aweme;
    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    for (NSString *key in TM3VariantKeys()) {
        NSString *url = TM3URLStringFromValue(TM3Value(video, key));
        if (!url) url = TM3URLStringFromValue(TM3Value(aweme, key));
        if (url) out[key] = url;
    }
    return [out copy];
}

/// URL substring markers for the variant keys (heuristic — see the header).
/// playAddr3DFallback has no safe substring ("3d" matches too broadly).
static NSString * _Nullable TM3MarkerForVariant(NSString *variant) {
    if ([variant isEqualToString:@"playAddr265"]) return @"265";
    if ([variant isEqualToString:@"playAddrH264"]) return @"h264";
    if ([variant isEqualToString:@"playAddrLowbr"]) return @"lowbr";
    if ([variant isEqualToString:@"playAddrBytevc1"]) return @"bytevc1";
    return nil;
}

static NSString * _Nullable TM3StringOfURLValue(id value) {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value absoluteString];
    return nil;
}

/// A download-stage instance: shared factory if one resolves, else alloc/init.
static id _Nullable TM3DownloadStageInstance(void) {
    Class cls = NSClassFromString(@"AWEMediaDownloadAwemeStage");
    if (!cls) {
        NSLog(@"[TikTokMod] #10 AWEMediaDownloadAwemeStage not found (fail-soft)");
        return nil;
    }
    for (NSString *factory in @[@"sharedInstance", @"shareInstance", @"sharedManager",
                                @"sharedStage", @"defaultStage"]) {
        SEL f = NSSelectorFromString(factory);
        if ([cls respondsToSelector:f]) {
            id stage = ((id (*)(id, SEL))objc_msgSend)(cls, f);
            if (stage) return stage;
        }
    }
    return [[cls alloc] init];
}

/// Hand one URL string to the stock download stage, matching the element type
/// stock itself used (NSString vs NSURL, from the last captured list).
static BOOL TM3HandURLToStage(NSString *urlString) {
    id stage = TM3DownloadStageInstance();
    if (!stage) return NO;
    SEL dl = NSSelectorFromString(@"downloadVideoWithURLList:");
    if (![stage respondsToSelector:dl]) {
        NSLog(@"[TikTokMod] #10 stage does not respond to downloadVideoWithURLList: (fail-soft)");
        return NO;
    }
    id element = urlString;
    id firstCaptured = [g3_lastCapturedURLs firstObject];
    if ([firstCaptured isKindOfClass:[NSURL class]]) {
        element = [NSURL URLWithString:urlString] ?: urlString;
    }
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(stage, dl, @[element]);
        NSLog(@"[TikTokMod] #10 handed URL to AWEMediaDownloadAwemeStage downloadVideoWithURLList: "
              @"(UNVERIFIED-RUNTIME — stock save path, verify on device)");
        return YES;
    } @catch (__unused NSException *e) {
        NSLog(@"[TikTokMod] #10 handing URL to the stage threw (fail-soft)");
        return NO;
    }
}

static void TM3Hook_DownloadStage_downloadVideo(id self, SEL _cmd, id urlList) {
    if ([urlList isKindOfClass:[NSArray class]] && [(NSArray *)urlList count] > 0) {
        g3_lastCapturedURLs = [(NSArray *)urlList copy];
        NSLog(@"[TikTokMod] #10 captured stock download URL list (%lu URL(s))",
              (unsigned long)[(NSArray *)urlList count]);
    }
    if (TM3On(@"downloadQualitySelection")) {
        NSString *choice = [TM3Settings() downloadQualityChoice];
        if (choice && ![choice isEqualToString:@"auto"] && [urlList isKindOfClass:[NSArray class]]) {
            // 1) Exact model-URL match for the stored variant.
            NSDictionary *variants = TM3QualityURLsFromAweme(TM3CurrentAwemeModel());
            NSString *wanted = variants[choice];
            id match = nil;
            if (wanted) {
                for (id el in (NSArray *)urlList) {
                    if ([wanted isEqualToString:TM3StringOfURLValue(el)]) { match = el; break; }
                }
            }
            // 2) Heuristic substring match on the variant marker.
            if (!match) {
                NSString *marker = TM3MarkerForVariant(choice);
                if (marker) {
                    for (id el in (NSArray *)urlList) {
                        NSString *s = TM3StringOfURLValue(el);
                        if (s && [s containsString:marker]) { match = el; break; }
                    }
                }
            }
            if (match) {
                NSLog(@"[TikTokMod] #10 skip-quality: stored choice %@ matched a URL — "
                      @"downloading only that variant (UNVERIFIED-RUNTIME)", choice);
                ((void (*)(id, SEL, id))g3_orig_DownloadStage_downloadVideo)(self, _cmd, @[match]);
                return;
            }
            NSLog(@"[TikTokMod] #10 skip-quality: stored choice %@ matched no URL in the stock list "
                  @"(heuristic match failed) — passing the stock list through untouched", choice);
        }
    }
    ((void (*)(id, SEL, id))g3_orig_DownloadStage_downloadVideo)(self, _cmd, urlList);
}

static void TM3Hook_DownloadComponent_didFinish(id self, SEL _cmd, id service, id player, id url) {
    if (TM3On(@"downloadQualitySelection") || TM3On(@"audioOnlyDownload")) {
        NSString *urlString = TM3StringOfURLValue(url) ?: @"<unknown>";
        if (urlString.length > 120) urlString = [[urlString substringToIndex:120] stringByAppendingString:@"…"];
        NSLog(@"[TikTokMod] download finished callback: URL=%@ (stock save path)", urlString);
    }
    ((void (*)(id, SEL, id, id, id))g3_orig_DownloadComponent_didFinish)(self, _cmd, service, player, url);
}

static void TM3InstallDownloadCapture(void) {
    if (!g3_installed_DownloadStage) {
        g3_installed_DownloadStage = TM3InstallSite(@"AWEMediaDownloadAwemeStage",
            NSSelectorFromString(@"downloadVideoWithURLList:"),
            (IMP)TM3Hook_DownloadStage_downloadVideo, &g3_orig_DownloadStage_downloadVideo, NO, 'v');
    }
    if (!g3_installed_DownloadComponent) {
        g3_installed_DownloadComponent = TM3InstallSite(@"TTKMediaVideoDownloadComponent",
            NSSelectorFromString(@"playerDelegateService:player:didFinishVideoDataDownloadForURL:"),
            (IMP)TM3Hook_DownloadComponent_didFinish, &g3_orig_DownloadComponent_didFinish, NO, 'v');
    }
}

// ---------------------------------------------------------------------------
// #18 Downloads: web sources in the source picker
// Evidence is WEAK (R2: webSource ×4; R1: AWEMediaDownloadResultInnerItem
// downloadSourceURL / setDownloadSourceURL:). No stock picker exists, so the
// picker is dylib-built: paste a URL, or reuse the last source URL stock
// itself set (recorded by the setter hook below). A pasted direct URL needs
// no capture and works even if the pinning bypass is unproven (design §3
// #18 fallback) — the bytes are fetched with a plain NSURLSession data task
// (system trust) and written to Documents/TikTokMod/Downloads/. Nothing is
// written into TikTok's own directories.
// ---------------------------------------------------------------------------

static IMP g3_orig_DownloadResult_setSourceURL = NULL;
static BOOL g3_installed_DownloadResult = NO;

static void TM3Hook_DownloadResult_setSourceURL(id self, SEL _cmd, id url) {
    NSString *s = TM3StringOfURLValue(url);
    if (s) {
        g3_lastWebSourceURL = [s copy];
        NSLog(@"[TikTokMod] #18 stock download source URL recorded (webSource evidence is weak — "
              @"this is the URL stock itself set, offered as a picker entry)");
    }
    ((void (*)(id, SEL, id))g3_orig_DownloadResult_setSourceURL)(self, _cmd, url);
}

static void TM3InstallWebSources(void) {
    if (!g3_installed_DownloadResult) {
        g3_installed_DownloadResult = TM3InstallSite(@"AWEMediaDownloadResultInnerItem",
            NSSelectorFromString(@"setDownloadSourceURL:"),
            (IMP)TM3Hook_DownloadResult_setSourceURL, &g3_orig_DownloadResult_setSourceURL, NO, 'v');
    }
}

/// Fetch URL bytes with a plain NSURLSession data task and write them to
/// `directory/fileName`. Calls `completion` on the main thread with the
/// saved path or an error string. Shared by #18 and #25.
static void TM3FetchURLToFile(NSString *urlString, NSString *directory, NSString *fileName,
                              void (^completion)(NSString * _Nullable savedPath, NSString * _Nullable error)) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil, @"Not a valid URL.");
        return;
    }
    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
                                                attributes:nil error:&dirError];
    if (dirError) {
        if (completion) completion(nil, [NSString stringWithFormat:@"Could not create %@: %@", directory, dirError.localizedDescription]);
        return;
    }
    NSString *path = [directory stringByAppendingPathComponent:fileName];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !data) {
                if (completion) completion(nil, error ? error.localizedDescription : @"No data received.");
                return;
            }
            if ([data writeToFile:path atomically:YES]) {
                long status = [response isKindOfClass:[NSHTTPURLResponse class]]
                    ? (long)[(NSHTTPURLResponse *)response statusCode] : -1;
                NSLog(@"[TikTokMod] downloaded %lu bytes from %@ to %@ (HTTP %ld)",
                      (unsigned long)data.length, urlString, path, status);
                if (completion) completion(path, nil);
            } else {
                if (completion) completion(nil, @"Could not write the file.");
            }
        });
    }];
    [task resume];
}

static NSString *TM3DownloadsDirectory(void) {
    NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.firstObject ?: NSTemporaryDirectory();
    return [base stringByAppendingPathComponent:@"TikTokMod/Downloads"];
}

static NSString *TM3FileNameForURLString(NSString *urlString, NSString *defaultExtension) {
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *name = [url lastPathComponent];
    if (name.length == 0 || [name isEqualToString:@"/"]) {
        name = [NSString stringWithFormat:@"tiktok-%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    }
    // Strip any query string that leaked into the name and ensure an extension.
    name = [[name componentsSeparatedByString:@"?"] firstObject];
    if ([name pathExtension].length == 0 && defaultExtension.length > 0) {
        name = [name stringByAppendingPathExtension:defaultExtension];
    }
    return name;
}

// ---------------------------------------------------------------------------
// Feature bodies — filled in per feature commit (D: #24, E: #25, F: #27).
// Until then each is a safe no-op that says so.
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
    TM3InstallDownloadCapture();
    TM3InstallWebSources();
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
    return TM3QualityURLsFromAweme(TM3CurrentAwemeModel());
}

+ (NSArray *)lastCapturedDownloadURLs {
    return g3_lastCapturedURLs ?: @[];
}

+ (void)downloadCurrentVideoFromViewController:(UIViewController *)vc {
    if (!TM3On(@"downloadQualitySelection")) {
        TM3AlertFrom(vc, @"Download quality (#10)",
            @"Turn the toggle on first. The download is UNVERIFIED-RUNTIME — it needs a runtime traffic capture proving the pinning bypass.");
        return;
    }
    NSDictionary<NSString *, NSString *> *variants = [self currentVideoQualityURLs];
    NSString *choice = [TM3Settings() downloadQualityChoice];
    // "Skip quality": a stored variant downloads silently, no picker.
    if (choice && ![choice isEqualToString:@"auto"]) {
        NSString *url = variants[choice];
        if (url && TM3HandURLToStage(url)) return;
        // Stored variant not found on this video — fall through to the picker.
        NSLog(@"[TikTokMod] #10 stored choice %@ has no URL on this video — showing the picker instead", choice);
    }
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (NSString *key in TM3VariantKeys()) {
        NSString *url = variants[key];
        if (url) { [labels addObject:key]; [urls addObject:url]; }
    }
    for (id captured in g3_lastCapturedURLs ?: @[]) {
        NSString *s = TM3StringOfURLValue(captured);
        if (s && ![urls containsObject:s]) {
            [labels addObject:[NSString stringWithFormat:@"Captured URL %lu", (unsigned long)labels.count + 1]];
            [urls addObject:s];
        }
    }
    if (labels.count == 0) {
        TM3AlertFrom(vc, @"Download quality (#10)",
            @"No video URL could be found for the current video (no aweme model reachable and no stock download captured yet). Open the video, use TikTok's Share → Save once so a URL is captured, then try again. UNVERIFIED-RUNTIME.");
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Download quality (#10)"
        message:@"Pick a playAddr variant. Your pick is remembered as the skip-quality choice (tap “Ask every time” to clear it). No stock picker exists — this list is built from the current video's model + captured stock URLs. UNVERIFIED-RUNTIME."
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger i = 0; i < labels.count; i++) {
        NSString *label = labels[i];
        NSString *url = urls[i];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            // Remember the variant key when the pick came from the model;
            // captured-URL picks are one-off (no variant key to remember).
            NSString *variantKey = nil;
            for (NSString *key in TM3VariantKeys()) {
                if ([variants[key] isEqualToString:url]) { variantKey = key; break; }
            }
            if (variantKey) [TM3Settings() setDownloadQualityChoice:variantKey];
            if (!TM3HandURLToStage(url)) {
                TM3AlertFrom(vc, @"Download quality (#10)",
                    @"Could not reach the stock download stage on this version (fail-soft). The stock Share → Save flow is untouched.");
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Ask every time (clear remembered quality)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
        [TM3Settings() setDownloadQualityChoice:@"auto"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:sheet animated:YES completion:nil];
}

+ (void)downloadFromWebSourceFromViewController:(UIViewController *)vc {
    if (!TM3On(@"downloadWebSources")) {
        TM3AlertFrom(vc, @"Web sources (#18)",
            @"Turn the toggle on first. The webSource evidence is weak (4 hits) — this picker is dylib-built, and a pasted direct URL works even if the pinning bypass is unproven.");
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Downloads: web sources (#18)"
        message:@"Paste a direct video URL, or reuse the last source URL TikTok itself set. Files save to Documents/TikTokMod/Downloads/ (Files app). UNVERIFIED-RUNTIME."
        preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Paste a URL…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIAlertController *prompt = [UIAlertController alertControllerWithTitle:@"Download from URL (#18)"
            message:@"Paste a direct http(s) video URL." preferredStyle:UIAlertControllerStyleAlert];
        [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = @"https://…";
            field.keyboardType = UIKeyboardTypeURL;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        [prompt addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *done) {
            NSString *urlString = [[prompt.textFields.firstObject.text ?: @""]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
                TM3AlertFrom(vc, @"Web sources (#18)", @"That is not an http(s) URL.");
                return;
            }
            NSString *fileName = TM3FileNameForURLString(urlString, @"mp4");
            TM3FetchURLToFile(urlString, TM3DownloadsDirectory(), fileName, ^(NSString *savedPath, NSString *error) {
                if (savedPath) {
                    TM3AlertFrom(vc, @"Web sources (#18)", [NSString stringWithFormat:@"Saved to %@.", savedPath]);
                } else {
                    TM3AlertFrom(vc, @"Web sources (#18)", [NSString stringWithFormat:@"Download failed: %@", error]);
                }
            });
        }]];
        [prompt addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:prompt animated:YES completion:nil];
    }]];
    if (g3_lastWebSourceURL.length > 0) {
        NSString *last = g3_lastWebSourceURL;
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use last stock source URL" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            NSString *fileName = TM3FileNameForURLString(last, @"mp4");
            TM3FetchURLToFile(last, TM3DownloadsDirectory(), fileName, ^(NSString *savedPath, NSString *error) {
                if (savedPath) {
                    TM3AlertFrom(vc, @"Web sources (#18)", [NSString stringWithFormat:@"Saved to %@.", savedPath]);
                } else {
                    TM3AlertFrom(vc, @"Web sources (#18)", [NSString stringWithFormat:@"Download failed: %@", error]);
                }
            });
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:sheet animated:YES completion:nil];
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
