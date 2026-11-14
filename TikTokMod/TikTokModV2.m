//
//  TikTokModV2.m
//  TikTokMod V2 — DYLIB-DESIGN.md §4 (13 features).
//  RULES (binding): every class/selector below comes from RESEARCH-LOG.md /
//  INJECTION-ANALYSIS.md / class-map.txt. Nothing invented. Missing target =
//  no-op + NSLog, never a crash. Every hook reads its live toggle per call
//  and falls through to stock behaviour when OFF. Runtime IMP injection only
//  (alias prefix "tm2_orig_") — no categories on TikTok classes, no link-time
//  refs to TikTok classes (the V1 link failure). Compile + artifact level
//  only: no iOS device exists on the build VM, nothing is runtime-verified.
//
//  Judgement calls (deviations / guards — see BUILD-LOG.md V2 section):
//  • #17 pinChatCount is the CURRENT pinned count, not the limit, so it is
//    forced to 0 (not "large" as the design's shorthand says) while the
//    +inboxPinChatLimit cap is forced to 999. Forcing the count large would
//    BLOCK pinning instead of allowing it.
//  • The +hashtagCountPublishCheck / +characterLimitPublishCheck prechecks are
//    hooked ONLY if they return void (a no-op then exactly means "skip").
//    If either returns BOOL its YES/NO polarity is unverified (YES could mean
//    "limit exceeded" = block), so the hook is skipped and logged — the
//    input-limit raise still lets the user type more.
//  • #16's verified tracker selector has no sticker slot; the chosen sticker
//    ID is stored and passed as petType only when it parses as an integer.
//  • #31's timed ("always") advance is driven by V1's public +activePlayer
//    plus a 1 s ticker; the primary advance is a dylib-owned scroll of the
//    feed's collection view (the auto-scroll component has no reachable
//    shared instance to call).
//
#import "TikTokModV2.h"
#import "TikTokMod.h"
#import "TikTokModSettings.h"
#import "TikTokModV1.h"
#import <objc/message.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Small helpers (file-local mirrors of V1's — V1's are static to V1.m)
// ---------------------------------------------------------------------------

static TikTokModSettings *TM2Settings(void) { return [TikTokModSettings shared]; }

static BOOL TM2On(NSString *key) { return [TM2Settings() boolForKey:key]; }

/// KVC read that can never throw: returns nil on any failure.
static id TM2Value(id obj, NSString *key) {
    if (!obj || !key) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

/// KVC read through a key path (e.g. @"statistics.diggCount"), nil on failure.
static id TM2ValuePath(id obj, NSString *path) {
    if (!obj || !path) return nil;
    @try { return [obj valueForKeyPath:path]; } @catch (__unused NSException *e) { return nil; }
}

static BOOL TM2BoolValue(id obj, NSString *key) {
    id v = TM2Value(obj, key);
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return NO;
}

/// KVC write that can never throw: YES when the key exists and took the value.
static BOOL TM2TrySet(id obj, NSString *key, id value) {
    if (!obj || !key) return NO;
    @try {
        [obj setValue:value forKey:key];
        return YES;
    } @catch (__unused NSException *e) { return NO; }
}

static double TM2Double(id obj, SEL sel, double fallback) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) return fallback;
    double (*fn)(id, SEL) = (double (*)(id, SEL))objc_msgSend;
    @try { return fn(obj, sel); } @catch (__unused NSException *e) { return fallback; }
}

static void TM2WalkViews(UIView *view, void (^block)(UIView *v)) {
    if (!view) return;
    block(view);
    for (UIView *sub in view.subviews) TM2WalkViews(sub, block);
}

static BOOL TM2ClassNameContains(UIView *v, NSString *sub) {
    return [NSStringFromClass([v class]) containsString:sub];
}

static UIColor * _Nullable TM2ColorFromHex(NSString * _Nullable hex) {
    if (!hex) return nil;
    NSString *clean = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length != 6) return nil;
    unsigned rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

static UIWindow * _Nullable TM2KeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindow *w = ((UIWindowScene *)scene).keyWindow;
            if (w) return w;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

static UIViewController * _Nullable TM2TopViewController(void) {
    UIViewController *root = TM2KeyWindow().rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static UIView * _Nullable TM2FeedContainerView(void) {
    UIViewController *root = TM2KeyWindow().rootViewController;
    while (root) {
        if ([NSStringFromClass([root class]) containsString:@"FeedContainer"] ||
            [NSStringFromClass([root class]) containsString:@"FeedRoot"]) {
            return root.view;
        }
        root = root.presentedViewController;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// Installer infrastructure (V2 mirror of V1's TMInstallSite)
// kind: 'v' void, 'B' BOOL (accepts B/c), 'i' integer (accepts q/i/l/s/I/L/S),
//       '@' object, '?' no return-type check.
// ---------------------------------------------------------------------------

static BOOL TM2InstallSite(NSString *className, SEL origSel, IMP newImp, IMP *outOrig,
                           BOOL classMethod, char kind) {
    Class cls = [TikTokMod safeClass:className];
    if (!cls) return NO;
    Class target = classMethod ? object_getClass(cls) : cls;
    Method m = classMethod ? class_getClassMethod(cls, origSel)
                           : class_getInstanceMethod(cls, origSel);
    if (!m) {
        NSLog(@"[TikTokMod] V2 site %@ %@ not found, skipping (fail-soft)",
              className, NSStringFromSelector(origSel));
        TMLog(@"V2 SKIP (not found): %@ %@", className, NSStringFromSelector(origSel));
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
            NSLog(@"[TikTokMod] V2 site %@ %@: unexpected return type '%c' (wanted '%c'), skipping (fail-soft)",
                  className, NSStringFromSelector(origSel), got, kind);
            TMLog(@"V2 SKIP (return '%c' wanted '%c'): %@ %@", got, kind, className, NSStringFromSelector(origSel));
            return NO;
        }
    }
    // Safe install (avoids V1's latent hazard): if the class does NOT
    // implement the selector itself (it is inherited, e.g. a view
    // controller's viewDidLayoutSubviews), exchanging implementations would
    // swap the SUPERCLASS's method and hook every subclass. Instead, ADD
    // our IMP as the class's own method and keep the inherited IMP as the
    // original. Only exchange when the class already has its own method.
    *outOrig = method_getImplementation(m);
    if (class_addMethod(target, origSel, newImp, method_getTypeEncoding(m))) {
        NSString *aliasName = [@"tm2_orig_" stringByAppendingString:NSStringFromSelector(origSel)];
        SEL aliasSel = NSSelectorFromString(aliasName);
        class_addMethod(target, aliasSel, *outOrig, method_getTypeEncoding(m));
        NSLog(@"[TikTokMod] V2 hook installed (added override): %@ %@", className, NSStringFromSelector(origSel));
        TMLog(@"V2 OK (added override): %@ %@", className, NSStringFromSelector(origSel));
        return YES;
    }
    NSString *aliasName = [@"tm2_orig_" stringByAppendingString:NSStringFromSelector(origSel)];
    SEL aliasSel = NSSelectorFromString(aliasName);
    if (!class_addMethod(target, aliasSel, newImp, method_getTypeEncoding(m))) {
        NSLog(@"[TikTokMod] V2 site %@ %@: alias %@ already exists, skipping",
              className, NSStringFromSelector(origSel), aliasName);
        return NO;
    }
    Method aliasMethod = class_getInstanceMethod(target, aliasSel);
    method_exchangeImplementations(m, aliasMethod);
    NSLog(@"[TikTokMod] V2 hook installed: %@ %@", className, NSStringFromSelector(origSel));
    TMLog(@"V2 OK: %@ %@", className, NSStringFromSelector(origSel));
    return YES;
}

/// Try the instance method first, then the class method (for targets whose
/// +/- is not stated in the design, e.g. hasAIMeme, the offline config utils).
static BOOL TM2InstallSiteAuto(NSString *className, SEL origSel, IMP newImp, IMP *outOrig, char kind) {
    if (TM2InstallSite(className, origSel, newImp, outOrig, NO, kind)) return YES;
    return TM2InstallSite(className, origSel, newImp, outOrig, YES, kind);
}

/// "Skip the check" hook for the TTKStudioPublishPrecheckHandler class
/// methods — installed ONLY when the method returns void (a no-op then
/// exactly means "skip"). A BOOL return has unverified polarity, so the
/// hook is skipped and the reason logged (see the file header).
static BOOL TM2InstallVoidOnlyPrecheck(NSString *className, SEL sel, IMP noOpImp, IMP *outOrig) {
    Class cls = [TikTokMod safeClass:className];
    if (!cls) return NO;
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        NSLog(@"[TikTokMod] V2 precheck %@ +%@ not found, skipping (fail-soft)",
              className, NSStringFromSelector(sel));
        return NO;
    }
    const char *enc = method_getTypeEncoding(m);
    char got = enc ? enc[0] : '?';
    if (got != 'v') {
        NSLog(@"[TikTokMod] V2 precheck %@ +%@ returns '%c', not void — polarity unverified, "
              @"NOT hooking (fail-soft; the input-limit raise still lets the user type more)",
              className, NSStringFromSelector(sel), got);
        return NO;
    }
    return TM2InstallSite(className, sel, noOpImp, outOrig, YES, 'v');
}

// ---------------------------------------------------------------------------
// Original IMPs (one static per site; set by the installer)
// ---------------------------------------------------------------------------

// #5
static IMP g2_orig_CommentPicker_showAlbumVC = NULL;
static IMP g2_orig_CommentInput_sendComment = NULL;
// #6
static IMP g2_orig_CaptionVM_checkHashtagLimit = NULL;
static IMP g2_orig_PublishText_showHashtagToast = NULL;
static IMP g2_orig_TextInput_setMaxHashtag = NULL;
static IMP g2_orig_TextInput_maxHashtag = NULL;
static IMP g2_orig_HashtagPrecheck = NULL;
static IMP g2_orig_ABTest_hashtagMaxLimit = NULL;
// #7
static IMP g2_orig_Recorder_shouldShowTeleprompter = NULL;
static IMP g2_orig_Recorder_isAITeleprompterEnabled = NULL;
static IMP g2_orig_Recorder_viewDidLoad = NULL;
static IMP g2_orig_EffectEditor_greenScreen = NULL;
static IMP g2_orig_AICaption_hasAIMeme = NULL;
static IMP g2_orig_EditorAICaption_hasMeme = NULL;
static IMP g2_orig_RecorderAICaption_hasMeme = NULL;
static IMP g2_orig_GreenScreenGate = NULL;
static IMP g2_orig_Draft_setFrontFlashColor = NULL;
static IMP g2_orig_Torch_trackFlashColor = NULL;
// #13
static IMP g2_orig_RepostTagMount = NULL;
static IMP g2_orig_CommentCell_configRepostTag = NULL;
static IMP g2_orig_CommentCell_repostVisible = NULL;
static IMP g2_orig_RepostGuide_record = NULL;
// #16 (no IMP hooks — timer-driven, see below)
// #17
static IMP g2_orig_Inbox_pinCount = NULL;
static IMP g2_orig_ABTest_inboxPinLimit = NULL;
static IMP g2_orig_ABTest_shareETGroupCount = NULL;
static IMP g2_orig_ABTest_shareETGroupMembers = NULL;
static IMP g2_orig_ABTest_stackedItems = NULL;
static IMP g2_orig_ABTest_stackedItemsK = NULL;
// #19
static IMP g2_orig_OfflineCfg_upgrade = NULL;
static IMP g2_orig_OfflineCfg_autoAdjust = NULL;
static IMP g2_orig_OfflineMgr_fetch = NULL;
static IMP g2_orig_OfflineMgr_updateCount = NULL;
// #22
static IMP g2_orig_ABTest_filterKeywords = NULL;
// #23
static IMP g2_orig_StickerNet_save = NULL;
static IMP g2_orig_Annotation_saveSticker = NULL;
static IMP g2_orig_ABTest_stickerDownload = NULL;
// #26
static IMP g2_orig_RepostShare_maxLength = NULL;
static IMP g2_orig_RepostShare_repostMaxLength = NULL;
static IMP g2_orig_CharPrecheck = NULL;
static IMP g2_orig_ABTest_repostUidLimit = NULL;
// #31
static IMP g2_orig_AutoPlayNext_enabled = NULL;
static IMP g2_orig_AutoPlayNext_setEnabled = NULL;
static IMP g2_orig_Player_didReachEnd = NULL;
static IMP g2_orig_ABTest_autoPlayDrama = NULL;
static IMP g2_orig_ABTest_dramaAutoPlay = NULL;
static IMP g2_orig_ABTest_dramaFYPAutoPlay = NULL;
static IMP g2_orig_ABTest_ipadFYPAutoScroll = NULL;
// #32 (UIFont swizzle lives in a UIKit category below; Myna hooks here)
static IMP g2_orig_Myna_fontWithName = NULL;
static IMP g2_orig_Myna_registerFont = NULL;
// #33
static IMP g2_orig_FeedContainer_layoutSubviews = NULL;

// ---------------------------------------------------------------------------
// #5 Comments with up to 9 images — UNVERIFIED (client lift only)
// ---------------------------------------------------------------------------

static void TM2Hook_CommentPicker_showAlbumVC(id self, SEL _cmd) {
    ((void (*)(id, SEL))g2_orig_CommentPicker_showAlbumVC)(self, _cmd);
    if (!TM2On(@"comments9Images")) return;
    // The picker's selection cap has no verified settable selector (the
    // configureMultiPick… selector's full arity is unverified — see the
    // install-time enumeration log). Try the common KVC limit keys on the
    // presented album VC shortly after it appears; a miss is a silent no-op.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIViewController *top = TM2TopViewController();
        if (!top) return;
        NSArray<NSString *> *keys = @[@"maxSelectedCount", @"maximumNumberOfSelection",
            @"maxSelectionCount", @"selectionLimit", @"maxCount",
            @"maximumSelectionCount", @"maxImageCount"];
        NSArray *targets = @[top, TM2Value(top, @"viewModel") ?: [NSNull null]];
        for (id target in targets) {
            if ([target isKindOfClass:[NSNull class]]) continue;
            for (NSString *key in keys) {
                if (TM2TrySet(target, key, @9)) {
                    NSLog(@"[TikTokMod] #5 raised picker cap via %@ = 9 on %@ "
                          @"(UNVERIFIED — server may still refuse 9-image comments)",
                          key, NSStringFromClass([target class]));
                    return;
                }
            }
        }
        NSLog(@"[TikTokMod] #5 picker cap: no KVC limit key took 9 (fail-soft; stock cap stands)");
    });
}

static void TM2Hook_CommentInput_sendComment(id self, SEL _cmd, id content, id source, id taskBlock) {
    if (TM2On(@"comments9Images")) {
        NSLog(@"[TikTokMod] #5 comment send while 9-image toggle is ON "
              @"(UNVERIFIED — server may refuse; client lift only)");
    }
    ((void (*)(id, SEL, id, id, id))g2_orig_CommentInput_sendComment)(self, _cmd, content, source, taskBlock);
}

// ---------------------------------------------------------------------------
// #6 Removed hashtag limit when posting — UNVERIFIED (client lift only)
// ---------------------------------------------------------------------------

static BOOL TM2Hook_CaptionVM_checkHashtagLimit(id self, SEL _cmd) {
    if (TM2On(@"hashtagLimitRemoval")) return NO; // no limit hit
    return ((BOOL (*)(id, SEL))g2_orig_CaptionVM_checkHashtagLimit)(self, _cmd);
}

static void TM2Hook_PublishText_showHashtagToast(id self, SEL _cmd) {
    if (TM2On(@"hashtagLimitRemoval")) return; // swallow the limit toast
    ((void (*)(id, SEL))g2_orig_PublishText_showHashtagToast)(self, _cmd);
}

static void TM2Hook_TextInput_setMaxHashtag(id self, SEL _cmd, long long limit) {
    if (TM2On(@"hashtagLimitRemoval")) limit = 10000;
    ((void (*)(id, SEL, long long))g2_orig_TextInput_setMaxHashtag)(self, _cmd, limit);
}

static long long TM2Hook_TextInput_maxHashtag(id self, SEL _cmd) {
    if (TM2On(@"hashtagLimitRemoval")) return 10000;
    return ((long long (*)(id, SEL))g2_orig_TextInput_maxHashtag)(self, _cmd);
}

static long long TM2Hook_ABTest_hashtagMaxLimit(id self, SEL _cmd) {
    if (TM2On(@"hashtagLimitRemoval")) return 10000;
    return ((long long (*)(id, SEL))g2_orig_ABTest_hashtagMaxLimit)(self, _cmd);
}

// Shared no-op for the void-only precheck hooks (#6, #26).
static void TM2Hook_PrecheckNoOp(id self, SEL _cmd, id a, id b) {
    // Skipped precheck while the toggle is ON; the installer only installs
    // this when the method returns void (see TM2InstallVoidOnlyPrecheck).
    (void)self; (void)_cmd; (void)a; (void)b;
}

// ---------------------------------------------------------------------------
// #13 Comment reposts — UNVERIFIED (client lift only)
// ---------------------------------------------------------------------------

static void TM2Hook_RepostTagMount(id self, SEL _cmd) {
    ((void (*)(id, SEL))g2_orig_RepostTagMount)(self, _cmd);
    if (!TM2On(@"commentReposts")) return;
    if (![self isKindOfClass:[UIView class]]) return;
    TM2WalkViews((UIView *)self, ^(UIView *v) {
        if (TM2ClassNameContains(v, @"Repost")) {
            v.hidden = NO;
            v.alpha = 1.0;
        }
    });
}

static void TM2Hook_CommentCell_configRepostTag(id self, SEL _cmd) {
    ((void (*)(id, SEL))g2_orig_CommentCell_configRepostTag)(self, _cmd);
    if (!TM2On(@"commentReposts")) return;
    id tagView = TM2Value(self, @"repostTagView");
    if ([tagView isKindOfClass:[UIView class]]) {
        ((UIView *)tagView).hidden = NO;
        ((UIView *)tagView).alpha = 1.0;
        NSLog(@"[TikTokMod] #13 repost tag unhidden (UNVERIFIED — server may refuse)");
    }
}

static BOOL TM2Hook_CommentCell_repostVisible(id self, SEL _cmd) {
    if (TM2On(@"commentReposts")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_CommentCell_repostVisible)(self, _cmd);
}

static void TM2Hook_RepostGuide_record(id self, SEL _cmd) {
    if (TM2On(@"commentReposts")) {
        NSLog(@"[TikTokMod] #13 recordCommentReposted called (UNVERIFIED — server may refuse)");
    }
    ((void (*)(id, SEL))g2_orig_RepostGuide_record)(self, _cmd);
}

// ---------------------------------------------------------------------------
// #26 Removed character limit on reposts — UNVERIFIED (client lift only)
// ---------------------------------------------------------------------------

static long long TM2Hook_RepostShare_maxLength(id self, SEL _cmd) {
    if (TM2On(@"repostCharacterLimitRemoval")) return 10000;
    return ((long long (*)(id, SEL))g2_orig_RepostShare_maxLength)(self, _cmd);
}

static long long TM2Hook_RepostShare_repostMaxLength(id self, SEL _cmd) {
    if (TM2On(@"repostCharacterLimitRemoval")) return 10000;
    return ((long long (*)(id, SEL))g2_orig_RepostShare_repostMaxLength)(self, _cmd);
}

static long long TM2Hook_ABTest_repostUidLimit(id self, SEL _cmd) {
    if (TM2On(@"repostCharacterLimitRemoval")) return 10000;
    return ((long long (*)(id, SEL))g2_orig_ABTest_repostUidLimit)(self, _cmd);
}

// ---------------------------------------------------------------------------
// #7 Camera extras: teleprompter, green screen, colored selfie flash, AI meme
// Flash sub-part is PARTIAL — frontFlashColor is a real field, not a proven
// user-facing toggle; shipped as an experimental sub-toggle (see header).
// ---------------------------------------------------------------------------

static BOOL TM2Hook_Recorder_shouldShowTeleprompter(id self, SEL _cmd) {
    if (TM2On(@"cameraExtras")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_Recorder_shouldShowTeleprompter)(self, _cmd);
}

static BOOL TM2Hook_Recorder_isAITeleprompterEnabled(id self, SEL _cmd) {
    if (TM2On(@"cameraExtras")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_Recorder_isAITeleprompterEnabled)(self, _cmd);
}

static void TM2Hook_Recorder_viewDidLoad(id self, SEL _cmd) {
    ((void (*)(id, SEL))g2_orig_Recorder_viewDidLoad)(self, _cmd);
    if (!TM2On(@"cameraExtras")) return;
    // Direct entry point (design §3 #7 fallback): invoke setupTeleprompter
    // instead of relying only on the AB-gated flag.
    SEL setup = NSSelectorFromString(@"setupTeleprompter");
    if ([self respondsToSelector:setup]) {
        ((void (*)(id, SEL))objc_msgSend)(self, setup);
        NSLog(@"[TikTokMod] #7 teleprompter setup invoked on recorder open");
    }
}

static BOOL TM2Hook_EffectEditor_greenScreen(id self, SEL _cmd) {
    if (TM2On(@"cameraExtras")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_EffectEditor_greenScreen)(self, _cmd);
}

static BOOL TM2Hook_AICaption_hasAIMeme(id self, SEL _cmd) {
    if (TM2On(@"cameraExtras")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_AICaption_hasAIMeme)(self, _cmd);
}

static BOOL TM2Hook_EditorAICaption_hasMeme(id self, SEL _cmd) {
    if (TM2On(@"cameraExtras")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_EditorAICaption_hasMeme)(self, _cmd);
}

static BOOL TM2Hook_RecorderAICaption_hasMeme(id self, SEL _cmd) {
    if (TM2On(@"cameraExtras")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_RecorderAICaption_hasMeme)(self, _cmd);
}

static BOOL TM2Hook_GreenScreenGate(id self, SEL _cmd) {
    if (TM2On(@"cameraExtras")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_GreenScreenGate)(self, _cmd);
}

/// Colored selfie flash (EXPERIMENTAL): replace the flash color argument
/// with the user's chosen hex color when the sub-toggle is ON. The argument
/// type is not fully verified, so only UIColor / NSString args are replaced;
/// anything else passes through untouched.
static id TM2FlashColorArg(id originalArg) {
    if (![TM2Settings() coloredSelfieFlashEnabled]) return originalArg;
    UIColor *chosen = TM2ColorFromHex([TM2Settings() frontFlashColorHex]);
    if ([originalArg isKindOfClass:[UIColor class]] && chosen) return chosen;
    if ([originalArg isKindOfClass:[NSString class]]) return [TM2Settings() frontFlashColorHex];
    return originalArg;
}

static void TM2Hook_Draft_setFrontFlashColor(id self, SEL _cmd, id color) {
    if (TM2On(@"cameraExtras")) {
        id arg = TM2FlashColorArg(color);
        ((void (*)(id, SEL, id))g2_orig_Draft_setFrontFlashColor)(self, _cmd, arg);
        if (arg != color) {
            NSLog(@"[TikTokMod] #7 experimental flash color set to %@ (PARTIAL — verify on device)",
                  [TM2Settings() frontFlashColorHex]);
        }
        return;
    }
    ((void (*)(id, SEL, id))g2_orig_Draft_setFrontFlashColor)(self, _cmd, color);
}

static void TM2Hook_Torch_trackFlashColor(id self, SEL _cmd, id color) {
    if (TM2On(@"cameraExtras")) {
        ((void (*)(id, SEL, id))g2_orig_Torch_trackFlashColor)(self, _cmd, TM2FlashColorArg(color));
        return;
    }
    ((void (*)(id, SEL, id))g2_orig_Torch_trackFlashColor)(self, _cmd, color);
}

// ---------------------------------------------------------------------------
// #16 Automatic streaks — dylib scheduler driving the stock send path
// (a timer + the existing trackSendStreakInvite… call, NOT an unlock).
// Recipients come only from the user's own hub list; the timer stops
// cleanly when the toggle is OFF.
// ---------------------------------------------------------------------------

static NSTimer *g2_streakTimer = nil;
static BOOL g2_streakFallbackAlertShown = NO;

static void TM2SendStreakToRecipient(NSString *conversationID) {
    if (!conversationID.length) return;
    Class trackerCls = NSClassFromString(@"AWEStreakTracker");
    if (!trackerCls) {
        NSLog(@"[TikTokMod] #16 AWEStreakTracker not found (fail-soft)");
        return;
    }
    SEL trackSel = NSSelectorFromString(@"trackSendStreakInviteWithConversationID:conversationType:source:petType:");
    id tracker = nil;
    for (NSString *factory in @[@"sharedInstance", @"shareInstance", @"sharedTracker"]) {
        SEL f = NSSelectorFromString(factory);
        if ([trackerCls respondsToSelector:f]) {
            tracker = ((id (*)(id, SEL))objc_msgSend)(trackerCls, f);
            if (tracker) break;
        }
    }
    if (!tracker) tracker = [[trackerCls alloc] init];
    if (!tracker || ![tracker respondsToSelector:trackSel]) {
        NSLog(@"[TikTokMod] #16 streak tracker unavailable or missing the send selector (fail-soft)");
        if (!g2_streakFallbackAlertShown) {
            g2_streakFallbackAlertShown = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *top = TM2TopViewController();
                if (!top) return;
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Automatic streaks (#16)"
                    message:@"The stock streak send path could not be reached — send the invite manually from the streak UI. The timer keeps the schedule and will retry."
                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [top presentViewController:a animated:YES completion:nil];
            });
        }
        return;
    }
    // petType has no documented sticker slot in the verified selector; the
    // stored sticker ID is passed as petType only when it parses as an
    // integer, otherwise 0 (see the file header — honest limit).
    long long petType = [[TM2Settings() streakStickerID] longLongValue];
    ((void (*)(id, SEL, id, long long, id, long long))objc_msgSend)(
        tracker, trackSel, conversationID, 0, @"TikTokMod", petType);
    NSLog(@"[TikTokMod] #16 streak invite sent to %@ (petType=%lld)", conversationID, petType);
}

@implementation TikTokModV2 (Streaks)

+ (void)sendStreaksNow {
    NSArray<NSString *> *recipients = [TM2Settings() streakRecipients];
    if (recipients.count == 0) {
        NSLog(@"[TikTokMod] #16 sendStreaksNow: no recipients configured (hub row) — nothing sent");
        return;
    }
    for (NSString *cid in recipients) TM2SendStreakToRecipient(cid);
}

+ (void)tm_streakTimerFired:(__unused NSTimer *)timer {
    if (!TM2On(@"automaticStreaks")) return;
    [self sendStreaksNow];
}

+ (void)refreshStreakTimer {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshStreakTimer]; });
        return;
    }
    [g2_streakTimer invalidate];
    g2_streakTimer = nil;
    if (!TM2On(@"automaticStreaks")) return;
    if ([TM2Settings() streakRecipients].count == 0) {
        NSLog(@"[TikTokMod] #16 timer not started: no recipients configured yet");
        return;
    }
    NSTimeInterval interval = MAX(1, [TM2Settings() streakIntervalMinutes]) * 60.0;
    g2_streakTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                       target:self
                                                     selector:@selector(tm_streakTimerFired:)
                                                     userInfo:nil repeats:YES];
    NSLog(@"[TikTokMod] #16 streak timer started (every %.0f min, %lu recipient(s))",
          interval / 60.0, (unsigned long)[TM2Settings() streakRecipients].count);
}

@end

// ---------------------------------------------------------------------------
// #23 Sticker downloads — route the tapped sticker through the stock save APIs
// ---------------------------------------------------------------------------

static void TM2Hook_StickerNet_save(id self, SEL _cmd, id sticker, id completion) {
    if (TM2On(@"stickerDownloads")) {
        NSLog(@"[TikTokMod] #23 saveStickerWith:completion: invoked (stock save path; "
              @"verify on device that the saved file is the tapped sticker)");
    }
    ((void (*)(id, SEL, id, id))g2_orig_StickerNet_save)(self, _cmd, sticker, completion);
}

static void TM2Hook_Annotation_saveSticker(id self, SEL _cmd, id destination, id success, id errorBlock) {
    id dest = destination;
    if (TM2On(@"stickerDownloads")) {
        BOOL empty = !dest || ([dest isKindOfClass:[NSString class]] && [(NSString *)dest length] == 0);
        if (empty) {
            // No destination supplied — give the stock saver a real one.
            NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *base = dirs.firstObject ?: NSTemporaryDirectory();
            NSString *dir = [base stringByAppendingPathComponent:@"TikTokMod/Stickers"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            dest = [dir stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"sticker-%lld.png", (long long)[[NSDate date] timeIntervalSince1970]]];
            NSLog(@"[TikTokMod] #23 sticker destination supplied: %@", dest);
        }
    }
    ((void (*)(id, SEL, id, id, id))g2_orig_Annotation_saveSticker)(self, _cmd, dest, success, errorBlock);
}

static BOOL TM2Hook_ABTest_stickerDownload(id self, SEL _cmd) {
    if (TM2On(@"stickerDownloads")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_ABTest_stickerDownload)(self, _cmd);
}

// ---------------------------------------------------------------------------
// #17 Removed limits on sending videos + pinning chats — UNVERIFIED
// ---------------------------------------------------------------------------

static long long TM2Hook_Inbox_pinCount(id self, SEL _cmd) {
    // pinChatCount is the CURRENT pinned count (the limit lives in
    // +inboxPinChatLimit / maxPinnedCount). Forcing the count large would
    // BLOCK pinning; forcing it to 0 lets the "pinned >= limit" check pass,
    // while the cap itself is raised to 999 below. See the file header.
    if (TM2On(@"sendPinLimitRemoval")) return 0;
    return ((long long (*)(id, SEL))g2_orig_Inbox_pinCount)(self, _cmd);
}

static long long TM2Hook_ABTest_inboxPinLimit(id self, SEL _cmd) {
    if (TM2On(@"sendPinLimitRemoval")) return 999;
    return ((long long (*)(id, SEL))g2_orig_ABTest_inboxPinLimit)(self, _cmd);
}

static long long TM2Hook_ABTest_shareETGroupCount(id self, SEL _cmd) {
    if (TM2On(@"sendPinLimitRemoval")) return 999;
    return ((long long (*)(id, SEL))g2_orig_ABTest_shareETGroupCount)(self, _cmd);
}

static long long TM2Hook_ABTest_shareETGroupMembers(id self, SEL _cmd) {
    if (TM2On(@"sendPinLimitRemoval")) return 999;
    return ((long long (*)(id, SEL))g2_orig_ABTest_shareETGroupMembers)(self, _cmd);
}

static long long TM2Hook_ABTest_stackedItems(id self, SEL _cmd) {
    if (TM2On(@"sendPinLimitRemoval")) return 999;
    return ((long long (*)(id, SEL))g2_orig_ABTest_stackedItems)(self, _cmd);
}

static long long TM2Hook_ABTest_stackedItemsK(id self, SEL _cmd) {
    if (TM2On(@"sendPinLimitRemoval")) return 999;
    return ((long long (*)(id, SEL))g2_orig_ABTest_stackedItemsK)(self, _cmd);
}

// ---------------------------------------------------------------------------
// #19 Offline video limit — tune the count path (no iOS twin of "2,000")
// ---------------------------------------------------------------------------

static BOOL TM2Hook_OfflineCfg_upgrade(id self, SEL _cmd) {
    if (TM2On(@"offlineVideoLimit")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_OfflineCfg_upgrade)(self, _cmd);
}

static BOOL TM2Hook_OfflineCfg_autoAdjust(id self, SEL _cmd) {
    if (TM2On(@"offlineVideoLimit")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_OfflineCfg_autoAdjust)(self, _cmd);
}

static void TM2Hook_OfflineMgr_fetch(id self, SEL _cmd, long long count, BOOL isByUser, id reason, id fetchBlock) {
    if (TM2On(@"offlineVideoLimit")) {
        count = MAX(1, [TM2Settings() offlineVideoCount]);
        NSLog(@"[TikTokMod] #19 offline fetch count raised to %lld", count);
    }
    ((void (*)(id, SEL, long long, BOOL, id, id))g2_orig_OfflineMgr_fetch)(self, _cmd, count, isByUser, reason, fetchBlock);
}

static void TM2Hook_OfflineMgr_updateCount(id self, SEL _cmd, long long count) {
    if (TM2On(@"offlineVideoLimit")) count = MAX(1, [TM2Settings() offlineVideoCount]);
    ((void (*)(id, SEL, long long))g2_orig_OfflineMgr_updateCount)(self, _cmd, count);
}

// ---------------------------------------------------------------------------
// #22 Content filters — words, tags, likes, views
// Words/tags match the caption + hashtags; likes/views use the aweme's
// digg/play counts. A count that cannot be read is treated as "unknown"
// and never drops the item (fail-soft — a bad predicate must not eat the feed).
// ---------------------------------------------------------------------------

static long long TM2AwemeCount(id item, NSString *key) {
    id v = TM2Value(item, key);
    if ([v isKindOfClass:[NSNumber class]]) return [v longLongValue];
    v = TM2ValuePath(item, [@"statistics." stringByAppendingString:key]);
    if ([v isKindOfClass:[NSNumber class]]) return [v longLongValue];
    return -1; // unknown — do not drop on it
}

static NSString *TM2AwemeText(id item) {
    NSMutableString *text = [NSMutableString string];
    for (NSString *key in @[@"desc", @"caption", @"text"]) {
        id v = TM2Value(item, key);
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            [text appendString:(NSString *)v];
            [text appendString:@" "];
            break;
        }
    }
    for (NSString *key in @[@"hashtags", @"hashTags"]) {
        id tags = TM2Value(item, key);
        if (![tags isKindOfClass:[NSArray class]]) continue;
        for (id tag in (NSArray *)tags) {
            NSString *name = nil;
            if ([tag isKindOfClass:[NSString class]]) name = tag;
            else name = TM2Value(tag, @"hashtagName") ?: TM2Value(tag, @"name");
            if ([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0) {
                [text appendString:@"#"];
                [text appendString:(NSString *)name];
                [text appendString:@" "];
            }
        }
        break;
    }
    return [text copy];
}

@implementation TikTokModV2 (Filters)

+ (BOOL)shouldDropFeedItem:(id)item {
    if (!item || !TM2On(@"contentFilters")) return NO;
    NSString *haystack = [TM2AwemeText(item) lowercaseString];
    for (NSString *word in [TM2Settings() filterWords]) {
        NSString *w = [[word stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if (w.length > 0 && [haystack containsString:w]) return YES;
    }
    for (NSString *tag in [TM2Settings() filterTags]) {
        NSString *t = [[tag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if ([t hasPrefix:@"#"]) t = [t substringFromIndex:1];
        if (t.length > 0 && ([haystack containsString:[@"#" stringByAppendingString:t]] ||
                             [haystack containsString:t])) return YES;
    }
    NSInteger minLikes = [TM2Settings() filterMinLikes];
    if (minLikes > 0) {
        long long likes = TM2AwemeCount(item, @"diggCount");
        if (likes >= 0 && likes < minLikes) return YES;
    }
    NSInteger minViews = [TM2Settings() filterMinViews];
    if (minViews > 0) {
        long long views = TM2AwemeCount(item, @"playCount");
        if (views >= 0 && views < minViews) return YES;
    }
    return NO;
}

+ (void)openStockKeywordFilterFromViewController:(UIViewController *)vc {
    Class mgrCls = NSClassFromString(@"PNSFeedFilterKeywordsManager");
    if (!mgrCls) {
        NSLog(@"[TikTokMod] #22 PNSFeedFilterKeywordsManager not found (fail-soft)");
        return;
    }
    id mgr = nil;
    if ([mgrCls respondsToSelector:@selector(sharedInstance)]) {
        mgr = [mgrCls performSelector:@selector(sharedInstance)];
    }
    if (!mgr) mgr = [[mgrCls alloc] init];
    SEL open = NSSelectorFromString(@"openFilterKeywordWithEnterFrom:popup:");
    if (mgr && [mgr respondsToSelector:open]) {
        // popup: is nil-safe for both an object and a BOOL reading.
        ((void (*)(id, SEL, id, id))objc_msgSend)(mgr, open, @"TikTokMod", nil);
        NSLog(@"[TikTokMod] #22 stock keyword-filter editor opened");
    } else {
        NSLog(@"[TikTokMod] #22 stock keyword-filter editor not reachable (fail-soft)");
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Content filters (#22)"
            message:@"TikTok's own keyword editor could not be opened on this version — the dylib word/tag/likes/views filter still applies to the feed."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    }
}

@end

static BOOL TM2Hook_ABTest_filterKeywords(id self, SEL _cmd) {
    if (TM2On(@"contentFilters")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_ABTest_filterKeywords)(self, _cmd);
}

// ---------------------------------------------------------------------------
// #31 Auto-scroll / auto-play "autotease" (+options/order)
// Primary advance: dylib-owned scroll of the feed's collection/table view
// (the TTKFeedAutoScrollModeComponent has no reachable shared instance to
// call, and the pipService path needs a component instance too). The
// auto-play-next service gate is forced YES as the service-level fallback.
// End-of-video trigger = playerItemDidReachEnd: + hub delay. "Always"
// (timed) mode = 1 s ticker over V1's public +activePlayer.
// ---------------------------------------------------------------------------

static BOOL TM2ScrollFeedToNext(void) {
    UIView *container = TM2FeedContainerView();
    if (!container) {
        NSLog(@"[TikTokMod] #31 no feed container on screen (fail-soft)");
        return NO;
    }
    __block UICollectionView *cv = nil;
    __block UITableView *tv = nil;
    TM2WalkViews(container, ^(UIView *v) {
        if (!cv && [v isKindOfClass:[UICollectionView class]]) cv = (UICollectionView *)v;
        if (!tv && [v isKindOfClass:[UITableView class]]) tv = (UITableView *)v;
    });
    if (cv) {
        NSArray<NSIndexPath *> *visible = [[cv indexPathsForVisibleItems]
            sortedArrayUsingSelector:@selector(compare:)];
        NSIndexPath *current = visible.firstObject;
        if (!current) return NO;
        NSIndexPath *next = nil;
        if (current.row + 1 < [cv numberOfItemsInSection:current.section]) {
            next = [NSIndexPath indexPathForRow:current.row + 1 inSection:current.section];
        } else if (current.section + 1 < [cv numberOfSections]) {
            next = [NSIndexPath indexPathForRow:0 inSection:current.section + 1];
        }
        if (!next) {
            NSLog(@"[TikTokMod] #31 already at the last feed item");
            return NO;
        }
        [cv scrollToItemAtIndexPath:next
                   atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
        NSLog(@"[TikTokMod] #31 auto-scrolled to section %ld row %ld",
              (long)next.section, (long)next.row);
        return YES;
    }
    if (tv) {
        NSArray<NSIndexPath *> *visible = [[tv indexPathsForVisibleRows]
            sortedArrayUsingSelector:@selector(compare:)];
        NSIndexPath *current = visible.firstObject;
        if (!current) return NO;
        NSIndexPath *next = nil;
        if (current.row + 1 < [tv numberOfRowsInSection:current.section]) {
            next = [NSIndexPath indexPathForRow:current.row + 1 inSection:current.section];
        } else if (current.section + 1 < [tv numberOfSections]) {
            next = [NSIndexPath indexPathForRow:0 inSection:current.section + 1];
        }
        if (!next) {
            NSLog(@"[TikTokMod] #31 already at the last feed item");
            return NO;
        }
        [tv scrollToRowAtIndexPath:next
                  atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        NSLog(@"[TikTokMod] #31 auto-scrolled to section %ld row %ld",
              (long)next.section, (long)next.row);
        return YES;
    }
    NSLog(@"[TikTokMod] #31 no collection/table view in the feed container "
          @"(fail-soft — current video keeps playing)");
    return NO;
}

static NSTimer *g2_autoScrollTimer = nil;
static __weak id g2_lastPlayer = nil;
static NSTimeInterval g2_playerStartTime = 0;
static NSTimeInterval g2_nextScrollRetryTime = 0;

static BOOL TM2Hook_AutoPlayNext_enabled(id self, SEL _cmd) {
    if (TM2On(@"autoScrollAutoPlayNext")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_AutoPlayNext_enabled)(self, _cmd);
}

static void TM2Hook_AutoPlayNext_setEnabled(id self, SEL _cmd, BOOL enabled) {
    if (TM2On(@"autoScrollAutoPlayNext")) enabled = YES;
    ((void (*)(id, SEL, BOOL))g2_orig_AutoPlayNext_setEnabled)(self, _cmd, enabled);
}

static void TM2Hook_Player_didReachEnd(id self, SEL _cmd, id arg) {
    ((void (*)(id, SEL, id))g2_orig_Player_didReachEnd)(self, _cmd, arg);
    if (!TM2On(@"autoScrollAutoPlayNext")) return;
    double delay = [TM2Settings() autoScrollDelaySeconds];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!TM2On(@"autoScrollAutoPlayNext")) return;
        TM2ScrollFeedToNext();
    });
}

static BOOL TM2Hook_ABTest_autoPlayDrama(id self, SEL _cmd) {
    if (TM2On(@"autoScrollAutoPlayNext")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_ABTest_autoPlayDrama)(self, _cmd);
}

static BOOL TM2Hook_ABTest_dramaAutoPlay(id self, SEL _cmd) {
    if (TM2On(@"autoScrollAutoPlayNext")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_ABTest_dramaAutoPlay)(self, _cmd);
}

static BOOL TM2Hook_ABTest_dramaFYPAutoPlay(id self, SEL _cmd) {
    if (TM2On(@"autoScrollAutoPlayNext")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_ABTest_dramaFYPAutoPlay)(self, _cmd);
}

static BOOL TM2Hook_ABTest_ipadFYPAutoScroll(id self, SEL _cmd) {
    if (TM2On(@"autoScrollAutoPlayNext")) return YES;
    return ((BOOL (*)(id, SEL))g2_orig_ABTest_ipadFYPAutoScroll)(self, _cmd);
}

// ---------------------------------------------------------------------------
// #32 Custom fonts + system font
// Primary: UIFont +fontWithName:size: swizzle (a UIKit category — linked,
// so no TikTok-class problem). "System font" = system font for every
// request. A named custom font falls back to the system font when the name
// is not installed. MynaUIFontManager fontWithName: is also hooked so the
// stock registry path gets the same swap at its own size.
// ---------------------------------------------------------------------------

@interface UIFont (TikTokModV2)
+ (UIFont *)tm2_fontWithName:(NSString *)fontName size:(CGFloat)fontSize;
@end

@implementation UIFont (TikTokModV2)

+ (UIFont *)tm2_fontWithName:(NSString *)fontName size:(CGFloat)fontSize {
    // After the exchange this selector holds the ORIGINAL implementation,
    // so calling it here is the call-through (V1's tm_viewDidLoad pattern).
    if (!TM2On(@"customFonts")) {
        return [self tm2_fontWithName:fontName size:fontSize];
    }
    NSString *chosen = [TM2Settings() customFontName];
    if (!chosen || [chosen isEqualToString:@"System"]) {
        return [UIFont systemFontOfSize:fontSize];
    }
    UIFont *custom = [self tm2_fontWithName:chosen size:fontSize];
    return custom ?: [UIFont systemFontOfSize:fontSize];
}

@end

static id TM2Hook_Myna_fontWithName(id self, SEL _cmd, id name) {
    UIFont *orig = ((id (*)(id, SEL, id))g2_orig_Myna_fontWithName)(self, _cmd, name);
    if (!TM2On(@"customFonts") || ![orig isKindOfClass:[UIFont class]]) return orig;
    NSString *chosen = [TM2Settings() customFontName];
    CGFloat size = [(UIFont *)orig pointSize];
    if (!chosen || [chosen isEqualToString:@"System"]) return [UIFont systemFontOfSize:size];
    UIFont *custom = [UIFont fontWithName:chosen size:size];
    return custom ?: orig;
}

static void TM2Hook_Myna_registerFont(id self, SEL _cmd, id font, id name) {
    if (TM2On(@"customFonts")) {
        NSLog(@"[TikTokMod] #32 registerFont:forName: called (name=%@)", name);
    }
    ((void (*)(id, SEL, id, id))g2_orig_Myna_registerFont)(self, _cmd, font, name);
}

// ---------------------------------------------------------------------------
// #33 Custom colors / theming — PER-SURFACE ONLY (feed chrome first).
// The global theme engine is DEFER (no single choke point exists).
// Applied in the feed container's viewDidLayoutSubviews: bottom bar / tab
// bar get the background color, right-rail interaction elements and the
// container get the accent tint. Unhandled surfaces keep stock colors.
// ---------------------------------------------------------------------------

static void TM2ApplyThemeColors(UIView *container) {
    if (!container) return;
    UIColor *accent = TM2ColorFromHex([TM2Settings() themeAccentColorHex]);
    UIColor *bg = TM2ColorFromHex([TM2Settings() themeBackgroundColorHex]);
    if (!accent && !bg) return;
    if (accent) container.tintColor = accent;
    TM2WalkViews(container, ^(UIView *v) {
        if (bg && (TM2ClassNameContains(v, @"BottomBar") || TM2ClassNameContains(v, @"TabBar"))) {
            v.backgroundColor = bg;
        }
        if (accent && TM2ClassNameContains(v, @"PlayInteraction")) {
            v.tintColor = accent;
        }
    });
}

static void TM2Hook_FeedContainer_layoutSubviews(id self, SEL _cmd) {
    ((void (*)(id, SEL))g2_orig_FeedContainer_layoutSubviews)(self, _cmd);
    if (TM2On(@"customColorsTheming") && [self isKindOfClass:[UIView class]]) {
        TM2ApplyThemeColors((UIView *)self);
    }
}

// ---------------------------------------------------------------------------
// Installer
// ---------------------------------------------------------------------------

static BOOL g2_installed_CommentPicker_showAlbumVC = NO;
static BOOL g2_installed_CommentInput_sendComment = NO;
static BOOL g2_installed_CaptionVM_checkHashtagLimit = NO;
static BOOL g2_installed_PublishText_showHashtagToast = NO;
static BOOL g2_installed_TextInput_setMaxHashtag = NO;
static BOOL g2_installed_TextInput_maxHashtag = NO;
static BOOL g2_installed_HashtagPrecheck = NO;
static BOOL g2_installed_ABTest_hashtagMaxLimit = NO;
static BOOL g2_installed_Recorder_shouldShowTeleprompter = NO;
static BOOL g2_installed_Recorder_isAITeleprompterEnabled = NO;
static BOOL g2_installed_Recorder_viewDidLoad = NO;
static BOOL g2_installed_EffectEditor_greenScreen = NO;
static BOOL g2_installed_AICaption_hasAIMeme = NO;
static BOOL g2_installed_EditorAICaption_hasMeme = NO;
static BOOL g2_installed_RecorderAICaption_hasMeme = NO;
static BOOL g2_installed_GreenScreenGate = NO;
static BOOL g2_installed_Draft_setFrontFlashColor = NO;
static BOOL g2_installed_Torch_trackFlashColor = NO;
static BOOL g2_installed_RepostTagMount = NO;
static BOOL g2_installed_CommentCell_configRepostTag = NO;
static BOOL g2_installed_CommentCell_repostVisible = NO;
static BOOL g2_installed_RepostGuide_record = NO;
static BOOL g2_installed_Inbox_pinCount = NO;
static BOOL g2_installed_ABTest_inboxPinLimit = NO;
static BOOL g2_installed_ABTest_shareETGroupCount = NO;
static BOOL g2_installed_ABTest_shareETGroupMembers = NO;
static BOOL g2_installed_ABTest_stackedItems = NO;
static BOOL g2_installed_ABTest_stackedItemsK = NO;
static BOOL g2_installed_OfflineCfg_upgrade = NO;
static BOOL g2_installed_OfflineCfg_autoAdjust = NO;
static BOOL g2_installed_OfflineMgr_fetch = NO;
static BOOL g2_installed_OfflineMgr_updateCount = NO;
static BOOL g2_installed_ABTest_filterKeywords = NO;
static BOOL g2_installed_StickerNet_save = NO;
static BOOL g2_installed_Annotation_saveSticker = NO;
static BOOL g2_installed_ABTest_stickerDownload = NO;
static BOOL g2_installed_RepostShare_maxLength = NO;
static BOOL g2_installed_RepostShare_repostMaxLength = NO;
static BOOL g2_installed_CharPrecheck = NO;
static BOOL g2_installed_ABTest_repostUidLimit = NO;
static BOOL g2_installed_AutoPlayNext_enabled = NO;
static BOOL g2_installed_AutoPlayNext_setEnabled = NO;
static BOOL g2_installed_Player_didReachEnd = NO;
static BOOL g2_installed_ABTest_autoPlayDrama = NO;
static BOOL g2_installed_ABTest_dramaAutoPlay = NO;
static BOOL g2_installed_ABTest_dramaFYPAutoPlay = NO;
static BOOL g2_installed_ABTest_ipadFYPAutoScroll = NO;
static BOOL g2_installed_Myna_fontWithName = NO;
static BOOL g2_installed_Myna_registerFont = NO;
static BOOL g2_installed_FeedContainer_layoutSubviews = NO;
static BOOL g2_didLogPickerMethods = NO;

@implementation TikTokModV2

+ (void)installV2Hooks {
    [self retryDeferredInstalls];
    // #32 generic fallback (UIKit is always loaded — no deferred install).
    [TikTokMod safeSwizzleClassMethod:[UIFont class]
                     originalSelector:@selector(fontWithName:size:)
                     swizzledSelector:@selector(tm2_fontWithName:size:)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tm_settingsChanged:)
                                                 name:TikTokModSettingsDidChangeNotification
                                               object:nil];
    // #31 "always" (timed) mode ticker — 1 s, cheap, toggle-gated per tick.
    dispatch_async(dispatch_get_main_queue(), ^{
        static BOOL started = NO;
        if (started) return;
        started = YES;
        g2_autoScrollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                               target:self
                                                             selector:@selector(tm_autoScrollTick:)
                                                             userInfo:nil repeats:YES];
    });
    [self refreshStreakTimer];
    NSLog(@"[TikTokMod] V2 installHooks: 13 features, per-site results in the logs above");
}

+ (void)tm_settingsChanged:(NSNotification *)note {
    NSString *key = note.userInfo[@"key"];
    if (!key) return;
    if ([key isEqualToString:@"automaticStreaks"] ||
        [key isEqualToString:@"streakRecipients"] ||
        [key isEqualToString:@"streakIntervalMinutes"] ||
        [key isEqualToString:@"streakStickerID"]) {
        [self refreshStreakTimer];
    }
}

+ (void)tm_autoScrollTick:(__unused NSTimer *)timer {
    if (!TM2On(@"autoScrollAutoPlayNext")) return;
    if ([TM2Settings() autoScrollOnlyAfterFullWatch]) return; // end-of-video hook owns this mode
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now < g2_nextScrollRetryTime) return;
    id player = [TikTokModV1 activePlayer];
    if (!player) return;
    if (player != g2_lastPlayer) {
        g2_lastPlayer = player;
        g2_playerStartTime = now;
        return;
    }
    double delay = [TM2Settings() autoScrollDelaySeconds];
    if (now - g2_playerStartTime >= delay) {
        if (TM2ScrollFeedToNext()) {
            g2_playerStartTime = now; // new video: restart the window
        } else {
            g2_nextScrollRetryTime = now + 10; // back off after a failed scroll
        }
    }
}

+ (void)retryDeferredInstalls {
    // #5 — comments with up to 9 images (UNVERIFIED)
    if (!g2_installed_CommentPicker_showAlbumVC) {
        g2_installed_CommentPicker_showAlbumVC = TM2InstallSite(@"TTKCommentPhotoPicker",
            @selector(showAlbumVC), (IMP)TM2Hook_CommentPicker_showAlbumVC,
            &g2_orig_CommentPicker_showAlbumVC, NO, 'v');
    }
    if (!g2_installed_CommentInput_sendComment) {
        g2_installed_CommentInput_sendComment = TM2InstallSite(@"TikTokCommentInputViewController",
            NSSelectorFromString(@"sendComment:inputSource:taskBlock:"),
            (IMP)TM2Hook_CommentInput_sendComment,
            &g2_orig_CommentInput_sendComment, NO, 'v');
    }
    if (!g2_didLogPickerMethods) {
        g2_didLogPickerMethods = YES;
        Class pickerCls = NSClassFromString(@"TTKCommentPhotoPicker");
        if (pickerCls) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(pickerCls, &count);
            for (unsigned int i = 0; i < count; i++) {
                NSString *name = NSStringFromSelector(method_getName(methods[i]));
                if ([name containsString:@"configureMultiPick"]) {
                    NSLog(@"[TikTokMod] #5 picker method found: %@ (NOT hooked — full selector arity unverified; cap raised via KVC instead)", name);
                }
            }
            free(methods);
        }
    }
    // #6 — removed hashtag limit (UNVERIFIED)
    if (!g2_installed_CaptionVM_checkHashtagLimit) {
        g2_installed_CaptionVM_checkHashtagLimit = TM2InstallSite(@"TTKPublishPageItemCaptionAreaViewModel",
            @selector(checkHashtagLimit), (IMP)TM2Hook_CaptionVM_checkHashtagLimit,
            &g2_orig_CaptionVM_checkHashtagLimit, NO, 'B');
    }
    if (!g2_installed_PublishText_showHashtagToast) {
        g2_installed_PublishText_showHashtagToast = TM2InstallSite(@"ACCPublishFunctionalTextManager",
            @selector(showHashtagCountLimitToast), (IMP)TM2Hook_PublishText_showHashtagToast,
            &g2_orig_PublishText_showHashtagToast, NO, 'v');
    }
    if (!g2_installed_TextInput_setMaxHashtag) {
        g2_installed_TextInput_setMaxHashtag = TM2InstallSite(@"AWETextInputController",
            @selector(setMaxHashtagCharacterLimit:), (IMP)TM2Hook_TextInput_setMaxHashtag,
            &g2_orig_TextInput_setMaxHashtag, NO, 'v');
    }
    if (!g2_installed_TextInput_maxHashtag) {
        g2_installed_TextInput_maxHashtag = TM2InstallSite(@"AWETextInputController",
            @selector(maxHashtagCharacterLimit), (IMP)TM2Hook_TextInput_maxHashtag,
            &g2_orig_TextInput_maxHashtag, NO, 'i');
    }
    if (!g2_installed_HashtagPrecheck) {
        g2_installed_HashtagPrecheck = TM2InstallVoidOnlyPrecheck(@"TTKStudioPublishPrecheckHandler",
            NSSelectorFromString(@"hashtagCountPublishCheck:extraInfo:"),
            (IMP)TM2Hook_PrecheckNoOp, &g2_orig_HashtagPrecheck);
    }
    if (!g2_installed_ABTest_hashtagMaxLimit) {
        g2_installed_ABTest_hashtagMaxLimit = TM2InstallSite(@"TTKABTest",
            @selector(studioPublishHashtagMaxLimit), (IMP)TM2Hook_ABTest_hashtagMaxLimit,
            &g2_orig_ABTest_hashtagMaxLimit, YES, 'i');
    }
    // #7 — camera extras (flash sub-part PARTIAL / experimental)
    if (!g2_installed_Recorder_shouldShowTeleprompter) {
        g2_installed_Recorder_shouldShowTeleprompter = TM2InstallSite(@"AWERecorderViewController",
            @selector(shouldShowAITeleprompter), (IMP)TM2Hook_Recorder_shouldShowTeleprompter,
            &g2_orig_Recorder_shouldShowTeleprompter, NO, 'B');
    }
    if (!g2_installed_Recorder_isAITeleprompterEnabled) {
        g2_installed_Recorder_isAITeleprompterEnabled = TM2InstallSite(@"AWERecorderViewController",
            @selector(isAITeleprompterEnabledInABTest), (IMP)TM2Hook_Recorder_isAITeleprompterEnabled,
            &g2_orig_Recorder_isAITeleprompterEnabled, NO, 'B');
    }
    if (!g2_installed_Recorder_viewDidLoad) {
        g2_installed_Recorder_viewDidLoad = TM2InstallSite(@"AWERecorderViewController",
            @selector(viewDidLoad), (IMP)TM2Hook_Recorder_viewDidLoad,
            &g2_orig_Recorder_viewDidLoad, NO, 'v');
    }
    if (!g2_installed_EffectEditor_greenScreen) {
        g2_installed_EffectEditor_greenScreen = TM2InstallSite(@"CKEEffectEditor",
            @selector(isContainsGreenScreenFeature), (IMP)TM2Hook_EffectEditor_greenScreen,
            &g2_orig_EffectEditor_greenScreen, NO, 'B');
    }
    if (!g2_installed_AICaption_hasAIMeme) {
        g2_installed_AICaption_hasAIMeme = TM2InstallSiteAuto(@"ACCAICaptionUtils",
            @selector(hasAIMeme), (IMP)TM2Hook_AICaption_hasAIMeme,
            &g2_orig_AICaption_hasAIMeme, 'B');
    }
    if (!g2_installed_EditorAICaption_hasMeme) {
        g2_installed_EditorAICaption_hasMeme = TM2InstallSite(@"ACCEditorAICaptionComponent",
            @selector(hasAiMemeBarItem), (IMP)TM2Hook_EditorAICaption_hasMeme,
            &g2_orig_EditorAICaption_hasMeme, NO, 'B');
    }
    if (!g2_installed_RecorderAICaption_hasMeme) {
        g2_installed_RecorderAICaption_hasMeme = TM2InstallSite(@"ACCRecorderAICaptionComponent",
            @selector(hasAiMemeBarItem), (IMP)TM2Hook_RecorderAICaption_hasMeme,
            &g2_orig_RecorderAICaption_hasMeme, NO, 'B');
    }
    if (!g2_installed_GreenScreenGate) {
        g2_installed_GreenScreenGate = TM2InstallSite(@"TTKABTest",
            @selector(studioGreenScreenAlbumOptV2), (IMP)TM2Hook_GreenScreenGate,
            &g2_orig_GreenScreenGate, YES, 'B');
    }
    if (!g2_installed_Draft_setFrontFlashColor) {
        g2_installed_Draft_setFrontFlashColor = TM2InstallSite(@"AWEVideoDraftModel",
            @selector(setFrontFlashColor:), (IMP)TM2Hook_Draft_setFrontFlashColor,
            &g2_orig_Draft_setFrontFlashColor, NO, 'v');
    }
    if (!g2_installed_Torch_trackFlashColor) {
        g2_installed_Torch_trackFlashColor = TM2InstallSite(@"ACCRecordTorchServiceImplNew",
            @selector(trackChooseFlashColor:), (IMP)TM2Hook_Torch_trackFlashColor,
            &g2_orig_Torch_trackFlashColor, NO, 'v');
    }
    // #13 — comment reposts (UNVERIFIED)
    if (!g2_installed_RepostTagMount) {
        g2_installed_RepostTagMount = TM2InstallSite(@"TTKCommentRepostTagRefreshComponent",
            @selector(componentMount), (IMP)TM2Hook_RepostTagMount,
            &g2_orig_RepostTagMount, NO, 'v');
    }
    if (!g2_installed_CommentCell_configRepostTag) {
        g2_installed_CommentCell_configRepostTag = TM2InstallSite(@"_TtC17TikTokCommentImpl23TTKCommentTableViewCell",
            @selector(configRepostTag), (IMP)TM2Hook_CommentCell_configRepostTag,
            &g2_orig_CommentCell_configRepostTag, NO, 'v');
    }
    if (!g2_installed_CommentCell_repostVisible) {
        g2_installed_CommentCell_repostVisible = TM2InstallSite(@"_TtC17TikTokCommentImpl23TTKCommentTableViewCell",
            @selector(isRepostTagVisibleForAnimation), (IMP)TM2Hook_CommentCell_repostVisible,
            &g2_orig_CommentCell_repostVisible, NO, 'B');
    }
    if (!g2_installed_RepostGuide_record) {
        g2_installed_RepostGuide_record = TM2InstallSiteAuto(@"TTKCommentRepostGuideManager",
            @selector(recordCommentReposted), (IMP)TM2Hook_RepostGuide_record,
            &g2_orig_RepostGuide_record, 'v');
    }
    // #17 — send/pin limits removed (UNVERIFIED)
    if (!g2_installed_Inbox_pinCount) {
        g2_installed_Inbox_pinCount = TM2InstallSiteAuto(@"AWEIMInboxDataManager",
            @selector(pinChatCount), (IMP)TM2Hook_Inbox_pinCount,
            &g2_orig_Inbox_pinCount, 'i');
    }
    if (!g2_installed_ABTest_inboxPinLimit) {
        g2_installed_ABTest_inboxPinLimit = TM2InstallSite(@"TTKABTest",
            @selector(inboxPinChatLimit), (IMP)TM2Hook_ABTest_inboxPinLimit,
            &g2_orig_ABTest_inboxPinLimit, YES, 'i');
    }
    if (!g2_installed_ABTest_shareETGroupCount) {
        g2_installed_ABTest_shareETGroupCount = TM2InstallSite(@"TTKABTest",
            @selector(imShareVideoToChatETGroupCountLimit), (IMP)TM2Hook_ABTest_shareETGroupCount,
            &g2_orig_ABTest_shareETGroupCount, YES, 'i');
    }
    if (!g2_installed_ABTest_shareETGroupMembers) {
        g2_installed_ABTest_shareETGroupMembers = TM2InstallSite(@"TTKABTest",
            @selector(imShareVideoToChatETGroupMemberCountLimit), (IMP)TM2Hook_ABTest_shareETGroupMembers,
            &g2_orig_ABTest_shareETGroupMembers, YES, 'i');
    }
    if (!g2_installed_ABTest_stackedItems) {
        g2_installed_ABTest_stackedItems = TM2InstallSite(@"TTKABTest",
            @selector(imStackedVideoCardsItemsLimit), (IMP)TM2Hook_ABTest_stackedItems,
            &g2_orig_ABTest_stackedItems, YES, 'i');
    }
    if (!g2_installed_ABTest_stackedItemsK) {
        g2_installed_ABTest_stackedItemsK = TM2InstallSite(@"TTKABTest",
            @selector(kAWEIMABTestIMStackedVideoCardsItemsLimit), (IMP)TM2Hook_ABTest_stackedItemsK,
            &g2_orig_ABTest_stackedItemsK, YES, 'i');
    }
    // #19 — offline video limit (count path)
    if (!g2_installed_OfflineCfg_upgrade) {
        g2_installed_OfflineCfg_upgrade = TM2InstallSiteAuto(@"AWEOfflineVideoConfigUtils",
            @selector(isOfflineModeCountLimitUpgradeEnabled), (IMP)TM2Hook_OfflineCfg_upgrade,
            &g2_orig_OfflineCfg_upgrade, 'B');
    }
    if (!g2_installed_OfflineCfg_autoAdjust) {
        g2_installed_OfflineCfg_autoAdjust = TM2InstallSiteAuto(@"AWEOfflineVideoConfigUtils",
            @selector(isOfflineModeAutoAdjustDownloadCountEnabled), (IMP)TM2Hook_OfflineCfg_autoAdjust,
            &g2_orig_OfflineCfg_autoAdjust, 'B');
    }
    if (!g2_installed_OfflineMgr_fetch) {
        g2_installed_OfflineMgr_fetch = TM2InstallSite(@"AWEOfflineModeDownloadManager",
            NSSelectorFromString(@"fetchOfflineVideoAwemeModelsWithCount:isByUser:startReasonIfNeed:beginingFetchblock:"),
            (IMP)TM2Hook_OfflineMgr_fetch, &g2_orig_OfflineMgr_fetch, NO, 'v');
    }
    if (!g2_installed_OfflineMgr_updateCount) {
        g2_installed_OfflineMgr_updateCount = TM2InstallSite(@"AWEOfflineModeDownloadManager",
            @selector(updateOfflineDataWithCount:), (IMP)TM2Hook_OfflineMgr_updateCount,
            &g2_orig_OfflineMgr_updateCount, NO, 'v');
    }
    // #22 — content filters (gate; the predicate runs in V1's filteredDataSource hook)
    if (!g2_installed_ABTest_filterKeywords) {
        g2_installed_ABTest_filterKeywords = TM2InstallSite(@"TTKABTest",
            @selector(filterVideosWithKeywords), (IMP)TM2Hook_ABTest_filterKeywords,
            &g2_orig_ABTest_filterKeywords, YES, 'B');
    }
    // #23 — sticker downloads
    if (!g2_installed_StickerNet_save) {
        g2_installed_StickerNet_save = TM2InstallSiteAuto(@"_TtC15TikTokIMSticker23IMStickerNetworkService",
            NSSelectorFromString(@"saveStickerWith:completion:"),
            (IMP)TM2Hook_StickerNet_save, &g2_orig_StickerNet_save, 'v');
    }
    if (!g2_installed_Annotation_saveSticker) {
        g2_installed_Annotation_saveSticker = TM2InstallSiteAuto(@"EEUIAnnotationParser",
            NSSelectorFromString(@"saveStickerWithDestination:success:andError:"),
            (IMP)TM2Hook_Annotation_saveSticker, &g2_orig_Annotation_saveSticker, 'v');
    }
    if (!g2_installed_ABTest_stickerDownload) {
        g2_installed_ABTest_stickerDownload = TM2InstallSite(@"TTKABTest",
            @selector(studioStickerDownloadDispatchMain), (IMP)TM2Hook_ABTest_stickerDownload,
            &g2_orig_ABTest_stickerDownload, YES, 'B');
    }
    // #26 — removed character limit on reposts (UNVERIFIED)
    if (!g2_installed_RepostShare_maxLength) {
        g2_installed_RepostShare_maxLength = TM2InstallSite(@"TTKCIShareABRepostShare",
            @selector(maxLength), (IMP)TM2Hook_RepostShare_maxLength,
            &g2_orig_RepostShare_maxLength, YES, 'i');
    }
    if (!g2_installed_RepostShare_repostMaxLength) {
        g2_installed_RepostShare_repostMaxLength = TM2InstallSite(@"TTKCIShareABRepostShare",
            @selector(repostShareMaxLength), (IMP)TM2Hook_RepostShare_repostMaxLength,
            &g2_orig_RepostShare_repostMaxLength, YES, 'i');
    }
    if (!g2_installed_CharPrecheck) {
        g2_installed_CharPrecheck = TM2InstallVoidOnlyPrecheck(@"TTKStudioPublishPrecheckHandler",
            NSSelectorFromString(@"characterLimitPublishCheck:extraInfo:"),
            (IMP)TM2Hook_PrecheckNoOp, &g2_orig_CharPrecheck);
    }
    if (!g2_installed_ABTest_repostUidLimit) {
        g2_installed_ABTest_repostUidLimit = TM2InstallSite(@"TTKABTest",
            @selector(repostUidStrLengthLimit), (IMP)TM2Hook_ABTest_repostUidLimit,
            &g2_orig_ABTest_repostUidLimit, YES, 'i');
    }
    // #31 — auto-scroll / auto-play "autotease"
    if (!g2_installed_AutoPlayNext_enabled) {
        g2_installed_AutoPlayNext_enabled = TM2InstallSite(@"TTKFeedLandscapeAutoPlayNextService",
            @selector(isAutoPlayNextEnabled), (IMP)TM2Hook_AutoPlayNext_enabled,
            &g2_orig_AutoPlayNext_enabled, NO, 'B');
    }
    if (!g2_installed_AutoPlayNext_setEnabled) {
        g2_installed_AutoPlayNext_setEnabled = TM2InstallSite(@"TTKFeedLandscapeAutoPlayNextService",
            @selector(setIsAutoPlayNextEnabled:), (IMP)TM2Hook_AutoPlayNext_setEnabled,
            &g2_orig_AutoPlayNext_setEnabled, NO, 'v');
    }
    if (!g2_installed_Player_didReachEnd) {
        g2_installed_Player_didReachEnd = TM2InstallSite(@"AWEVideoPlayerController",
            @selector(playerItemDidReachEnd:), (IMP)TM2Hook_Player_didReachEnd,
            &g2_orig_Player_didReachEnd, NO, 'v');
    }
    if (!g2_installed_ABTest_autoPlayDrama) {
        g2_installed_ABTest_autoPlayDrama = TM2InstallSite(@"TTKABTest",
            @selector(enableAutoPlayNextForDramaVideo), (IMP)TM2Hook_ABTest_autoPlayDrama,
            &g2_orig_ABTest_autoPlayDrama, YES, 'B');
    }
    if (!g2_installed_ABTest_dramaAutoPlay) {
        g2_installed_ABTest_dramaAutoPlay = TM2InstallSite(@"TTKABTest",
            @selector(enableDramaAutoPlayNext), (IMP)TM2Hook_ABTest_dramaAutoPlay,
            &g2_orig_ABTest_dramaAutoPlay, YES, 'B');
    }
    if (!g2_installed_ABTest_dramaFYPAutoPlay) {
        g2_installed_ABTest_dramaFYPAutoPlay = TM2InstallSite(@"TTKABTest",
            @selector(enableDramaFYPAutoPlayNext), (IMP)TM2Hook_ABTest_dramaFYPAutoPlay,
            &g2_orig_ABTest_dramaFYPAutoPlay, YES, 'B');
    }
    if (!g2_installed_ABTest_ipadFYPAutoScroll) {
        g2_installed_ABTest_ipadFYPAutoScroll = TM2InstallSite(@"TTKABTest",
            @selector(ipadFYPAutoScroll), (IMP)TM2Hook_ABTest_ipadFYPAutoScroll,
            &g2_orig_ABTest_ipadFYPAutoScroll, YES, 'B');
    }
    // #32 — custom fonts (Myna registry path; the UIFont swizzle is in installV2Hooks)
    if (!g2_installed_Myna_fontWithName) {
        g2_installed_Myna_fontWithName = TM2InstallSite(@"MynaUIFontManager",
            @selector(fontWithName:), (IMP)TM2Hook_Myna_fontWithName,
            &g2_orig_Myna_fontWithName, NO, '@');
    }
    if (!g2_installed_Myna_registerFont) {
        g2_installed_Myna_registerFont = TM2InstallSite(@"MynaUIFontManager",
            @selector(registerFont:forName:), (IMP)TM2Hook_Myna_registerFont,
            &g2_orig_Myna_registerFont, NO, 'v');
    }
    // #33 — custom colors, per-surface only (feed chrome first)
    if (!g2_installed_FeedContainer_layoutSubviews) {
        g2_installed_FeedContainer_layoutSubviews = TM2InstallSite(@"AWEFeedContainerViewController",
            @selector(viewDidLayoutSubviews), (IMP)TM2Hook_FeedContainer_layoutSubviews,
            &g2_orig_FeedContainer_layoutSubviews, NO, 'v');
    }
}

@end
