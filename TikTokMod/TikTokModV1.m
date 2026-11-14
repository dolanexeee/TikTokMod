//
//  TikTokModV1.m
//  TikTokMod V1 — DYLIB-DESIGN.md §4 (24 features).
//  RULES (binding): every class/selector below comes from RESEARCH-LOG.md /
//  INJECTION-ANALYSIS.md / class-map.txt. Nothing invented. Missing target =
//  no-op + NSLog, never a crash. Every hook reads its live toggle per call
//  and falls through to stock behaviour when OFF.
//
#import "TikTokModV1.h"
#import "TikTokMod.h"
#import "TikTokModHub.h"
#import "TikTokModSettings.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString * const kTikTokModVersion = @"v1.0";

// Overlay view tags (unique range, dylib-owned).
static const NSInteger kTMTagModButton      = 7001;
static const NSInteger kTMTagPiPButton      = 7002;
static const NSInteger kTMTagSlider         = 7003;
static const NSInteger kTMTagDateLabel      = 7004;
static const NSInteger kTMTagDrawOverlay    = 7005;
static const NSInteger kTMTagFakeStatusBar  = 7006;
static const NSInteger kTMTagBurnInDim      = 7007;
static const NSInteger kTMTagCustomBg       = 7008;
static const NSInteger kTMTagScrim          = 7009;
static const NSInteger kTMTagRestoreUI      = 7010;

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

static TikTokModSettings *TMSettings(void) { return [TikTokModSettings shared]; }

static BOOL TMOn(NSString *key) { return [TMSettings() boolForKey:key]; }

/// KVC read that can never throw: returns nil on any failure.
static id TMValue(id obj, NSString *key) {
    if (!obj || !key) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

static BOOL TMBoolValue(id obj, NSString *key) {
    id v = TMValue(obj, key);
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return NO;
}

static void TMWalkViews(UIView *view, void (^block)(UIView *v)) {
    if (!view) return;
    block(view);
    for (UIView *sub in view.subviews) TMWalkViews(sub, block);
}

static UIView * _Nullable TMFindView(UIView *root, BOOL (^pred)(UIView *v)) {
    if (!root) return nil;
    __block UIView *found = nil;
    TMWalkViews(root, ^(UIView *v) {
        if (!found && pred(v)) found = v;
    });
    return found;
}

static BOOL TMClassNameContains(UIView *v, NSString *sub) {
    return [NSStringFromClass([v class]) containsString:sub];
}

/// The most recently seen video player controller (weak). Set by the #2 hooks.
static __weak id g_activePlayer = nil;

static double TMDouble(id obj, SEL sel, double fallback) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) return fallback;
    double (*fn)(id, SEL) = (double (*)(id, SEL))objc_msgSend;
    @try { return fn(obj, sel); } @catch (__unused NSException *e) { return fallback; }
}

static double TMPlayerDuration(id player) {
    for (NSString *name in @[@"duration", @"totalDuration", @"videoDuration"]) {
        double d = TMDouble(player, NSSelectorFromString(name), -1);
        if (d > 0) return d;
    }
    return 60.0;
}

// ---------------------------------------------------------------------------
// #38 Drawing overlay ("risovalca") — fully dylib-owned, no stock target.
// ---------------------------------------------------------------------------

@interface TikTokModDrawView : UIView
@property (nonatomic, strong) NSMutableArray<UIBezierPath *> *paths;
@property (nonatomic, strong) CAShapeLayer *drawLayer;
@end

@implementation TikTokModDrawView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.paths = [NSMutableArray array];
        self.drawLayer = [CAShapeLayer layer];
        self.drawLayer.strokeColor = [UIColor systemYellowColor].CGColor;
        self.drawLayer.fillColor = [UIColor clearColor].CGColor;
        self.drawLayer.lineWidth = 4.0;
        self.drawLayer.lineCap = kCALineCapRound;
        self.drawLayer.frame = self.bounds;
        [self.layer addSublayer:self.drawLayer];
        // Toolbar: Clear / Save / Done
        NSArray<NSString *> *titles = @[@"Clear", @"Save", @"Done"];
        CGFloat x = 12;
        for (NSString *t in titles) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            [b setTitle:t forState:UIControlStateNormal];
            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
            b.layer.cornerRadius = 8;
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            b.frame = CGRectMake(x, 12, 64, 32);
            x += 72;
            if ([t isEqualToString:@"Clear"]) {
                [b addTarget:self action:@selector(tm_clear) forControlEvents:UIControlEventTouchUpInside];
            } else if ([t isEqualToString:@"Save"]) {
                [b addTarget:self action:@selector(tm_save) forControlEvents:UIControlEventTouchUpInside];
            } else {
                [b addTarget:self action:@selector(tm_done) forControlEvents:UIControlEventTouchUpInside];
            }
            [self addSubview:b];
        }
    }
    return self;
}

- (void)tm_clear {
    [self.paths removeAllObjects];
    [self tm_redraw];
}

- (void)tm_redraw {
    UIBezierPath *all = [UIBezierPath bezierPath];
    for (UIBezierPath *p in self.paths) [all appendPath:p];
    self.drawLayer.path = all.CGPath;
}

- (void)tm_save {
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 0);
    [self.drawLayer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) {
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        NSLog(@"[TikTokMod] #38 drawing saved to Photos");
    }
}

- (void)tm_done {
    [self removeFromSuperview];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch *t = touches.anyObject;
    if (!t) return;
    UIBezierPath *p = [UIBezierPath bezierPath];
    p.lineWidth = 4.0;
    [p moveToPoint:[t locationInView:self]];
    [self.paths addObject:p];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UITouch *t = touches.anyObject;
    if (!t) return;
    [[self.paths lastObject] addLineToPoint:[t locationInView:self]];
    [self tm_redraw];
}

@end

// ---------------------------------------------------------------------------
// #40 Startup screen — dylib-owned VC (check / download / FAQ / legal / stats)
// ---------------------------------------------------------------------------

@interface TikTokModStartupViewController : UIViewController
@end

@implementation TikTokModStartupViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scroll];
    __block CGFloat y = 24;
    CGFloat w = self.view.bounds.size.width - 32;
    UILabel *(^label)(NSString *, CGFloat, BOOL) = ^UILabel *(NSString *text, CGFloat size, BOOL bold) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w, 0)];
        l.text = text;
        l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
        l.numberOfLines = 0;
        [l sizeToFit];
        l.frame = CGRectMake(16, y, w, l.frame.size.height);
        y += l.frame.size.height + 8;
        [scroll addSubview:l];
        return l;
    };
    label(@"TikTokMod — Startup Check", 22, YES);
    NSUInteger enabled = 0;
    for (NSString *k in [TikTokModSettings allFeatureKeys]) if (TMOn(k)) enabled++;
    label([NSString stringWithFormat:@"Status: dylib loaded ✓  •  Version %@  •  %lu/%lu features ON",
           kTikTokModVersion, (unsigned long)enabled,
           (unsigned long)[TikTokModSettings allFeatureKeys].count], 14, NO);
    label(@"Download — mod updates", 17, YES);
    label(@"OTA (#41/#15) checks GitHub releases for a newer dylib. An update applies "
          @"after re-assembly and re-sign — a loaded dylib cannot hot-patch itself.", 14, NO);
    UIButton *check = [UIButton buttonWithType:UIButtonTypeSystem];
    [check setTitle:@"Check for mod updates" forState:UIControlStateNormal];
    check.frame = CGRectMake(16, y, 220, 36);
    [check addTarget:self action:@selector(tm_checkUpdates) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:check];
    y += 48;
    label(@"FAQ", 17, YES);
    label(@"• Toggles apply live — no restart needed (except the app icon, which iOS applies immediately).\n"
          @"• Signal / Wi-Fi in the fake status bar (#39) are user-set values, not live readings — "
          @"iOS has no public live API for them.\n"
          @"• Series (#43) is HIDE ONLY. Unlock is impossible (server-side IAP) and is never attempted.\n"
          @"• The custom background (#45) never makes the video layer translucent — it shows on "
          @"profile / chat / chrome areas, with a dark scrim behind captions.", 14, NO);
    label(@"Legal", 17, YES);
    label(@"TikTokMod is an unofficial modification, not affiliated with or endorsed by TikTok / ByteDance. "
          @"Use at your own risk, on a secondary account only. TikTok detects modified clients.", 14, NO);
    label(@"Stats", 17, YES);
    label([NSString stringWithFormat:@"Base: TikTok 47.7.0 (477034)  •  V1: 24 features  •  Hub: %@",
           [TikTokModSettings allFeatureKeys].count == 41 ? @"41 toggles" : @"registry"], 14, NO);
    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    [go setTitle:@"Continue to TikTok" forState:UIControlStateNormal];
    go.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    go.frame = CGRectMake(16, y, 220, 44);
    [go addTarget:self action:@selector(tm_continue) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:go];
    y += 60;
    scroll.contentSize = CGSizeMake(self.view.bounds.size.width, y);
}

- (void)tm_checkUpdates {
    [TikTokModV1 checkForUpdatesFromViewController:self];
}

- (void)tm_continue {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

// ---------------------------------------------------------------------------
// Overlay helpers (feed container / window level)
// ---------------------------------------------------------------------------

static UIWindow * _Nullable TMKeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindow *w = ((UIWindowScene *)scene).keyWindow;
            if (w) return w;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

static UIViewController * _Nullable TMTopViewController(void) {
    UIViewController *root = TMKeyWindow().rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

/// The feed container/root view, if one is on screen (class-name match, fail-soft).
static UIView * _Nullable TMFeedContainerView(void) {
    UIViewController *top = TMTopViewController();
    if (top && ([NSStringFromClass([top class]) containsString:@"FeedContainer"] ||
                [NSStringFromClass([top class]) containsString:@"FeedRoot"])) {
        return top.view;
    }
    // Walk presented stack for a feed VC.
    UIViewController *root = TMKeyWindow().rootViewController;
    while (root) {
        if ([NSStringFromClass([root class]) containsString:@"FeedContainer"] ||
            [NSStringFromClass([root class]) containsString:@"FeedRoot"]) {
            return root.view;
        }
        root = root.presentedViewController;
    }
    return nil;
}

static UIView * _Nullable TMOverlayHost(void) {
    UIView *feed = TMFeedContainerView();
    if (feed) return feed;
    return TMKeyWindow();
}

static void TMRemoveTagged(UIView *host, NSInteger tag) {
    if (!host) return;
    UIView *v = [host viewWithTag:tag];
    if (v) [v removeFromSuperview];
}

// ---------------------------------------------------------------------------
// #1 Interface editor — tap-to-hide (dylib gesture + alert, persisted list)
// ---------------------------------------------------------------------------

static void TMShowHidePromptForView(UIView *hitView) {
    if (!hitView) return;
    NSString *clsName = NSStringFromClass([hitView class]);
    UIViewController *top = TMTopViewController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Hide this element?"
                         message:[NSString stringWithFormat:@"Class: %@\nIt will stay hidden until you unhide it in the hub (#1).", clsName]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hide" style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *a) {
        TikTokModSettings *s = TMSettings();
        NSMutableArray *hidden = [[s hiddenElementClasses] mutableCopy] ?: [NSMutableArray array];
        if (![hidden containsObject:clsName]) [hidden addObject:clsName];
        [s setHiddenElementClasses:[hidden copy]];
        hitView.hidden = YES;
        NSLog(@"[TikTokMod] #1 hid element class %@", clsName);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
// Overlay builders (feed container level)
// ---------------------------------------------------------------------------

@interface TikTokModV1 (Overlays)
+ (void)tm_addModButtonToView:(UIView *)host;
+ (void)tm_addPiPButtonToView:(UIView *)host;
+ (void)tm_addSliderToView:(UIView *)host;
+ (void)tm_addFakeStatusBarToView:(UIView *)host;
+ (void)tm_addBurnInOverlayToView:(UIView *)host;
+ (void)tm_applyCustomBackgroundToView:(UIView *)host;
+ (void)tm_updateOverlayVisibilityForView:(UIView *)host;
+ (void)tm_installEditorGestureOnView:(UIView *)host;
@end

@implementation TikTokModV1 (Overlays)

+ (void)tm_addModButtonToView:(UIView *)host {
    if (!host || [host viewWithTag:kTMTagModButton]) return;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.tag = kTMTagModButton;
    [b setTitle:@"Mod" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    b.layer.cornerRadius = 14;
    NSString *pos = [TMSettings() modButtonCenter];
    if (pos) {
        NSArray<NSString *> *parts = [pos componentsSeparatedByString:@","];
        if (parts.count == 2) {
            b.frame = CGRectMake([parts[0] floatValue], [parts[1] floatValue], 56, 28);
        } else {
            b.frame = CGRectMake(host.bounds.size.width - 72, 56, 56, 28);
        }
    } else {
        b.frame = CGRectMake(host.bounds.size.width - 72, 56, 56, 28);
    }
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [b addTarget:self action:@selector(tm_modButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(tm_modButtonDragged:)];
    [b addGestureRecognizer:pan];
    [host addSubview:b];
    NSLog(@"[TikTokMod] hub entry: Mod button added to feed chrome (#9, candidate A)");
}

+ (void)tm_modButtonTapped {
    [TikTokModHub presentHub];
}

+ (void)tm_modButtonDragged:(UIPanGestureRecognizer *)pan {
    UIView *b = pan.view;
    if (!b) return;
    CGPoint t = [pan translationInView:b.superview];
    b.center = CGPointMake(b.center.x + t.x, b.center.y + t.y);
    [pan setTranslation:CGPointZero inView:b.superview];
    if (pan.state == UIGestureRecognizerStateEnded) {
        [TMSettings() setModButtonCenter:[NSString stringWithFormat:@"%.0f,%.0f", b.frame.origin.x, b.frame.origin.y]];
    }
}

+ (void)tm_addPiPButtonToView:(UIView *)host {
    if (!host || [host viewWithTag:kTMTagPiPButton]) return;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.tag = kTMTagPiPButton;
    [b setTitle:@"PiP" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    b.layer.cornerRadius = 14;
    b.frame = CGRectMake(host.bounds.size.width - 72, 92, 56, 28);
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    b.hidden = !TMOn(@"pictureInPicture");
    [b addTarget:self action:@selector(tm_pipButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:b];
}

// #3 — drive the stock PiP stack (BUILD-AS-UNLOCK). Never reimplements PiP.
+ (void)tm_pipButtonTapped {
    Class pipCls = NSClassFromString(@"TTKMediaPiPController");
    if (!pipCls) pipCls = NSClassFromString(@"TTPictureInPictureController");
    if (!pipCls) {
        NSLog(@"[TikTokMod] #3 PiP: no PiP controller class found, skipping (fail-soft)");
        return;
    }
    id pip = nil;
    if ([pipCls respondsToSelector:@selector(sharedInstance)]) {
        pip = [pipCls performSelector:@selector(sharedInstance)];
    }
    if (!pip) pip = [[pipCls alloc] init];
    if (!pip) {
        NSLog(@"[TikTokMod] #3 PiP: could not obtain a PiP controller");
        return;
    }
    if ([pip respondsToSelector:@selector(setupPictureInPictureController)]) {
        [pip performSelector:@selector(setupPictureInPictureController)];
    }
    double dur = TMPlayerDuration(g_activePlayer);
    if ([pip respondsToSelector:@selector(armPictureInPictureWithVideoDuration:)]) {
        ((void (*)(id, SEL, double))objc_msgSend)(pip, @selector(armPictureInPictureWithVideoDuration:), dur);
    }
    if ([pip respondsToSelector:@selector(startPictureInPicture)]) {
        [pip performSelector:@selector(startPictureInPicture)];
        NSLog(@"[TikTokMod] #3 PiP started");
    } else if ([pip respondsToSelector:@selector(preparePictureInPicture)]) {
        [pip performSelector:@selector(preparePictureInPicture)];
        NSLog(@"[TikTokMod] #3 PiP prepared (no startPictureInPicture on this controller)");
    } else {
        NSLog(@"[TikTokMod] #3 PiP: controller has no start method, skipping (fail-soft)");
    }
}

+ (void)tm_addSliderToView:(UIView *)host {
    if (!host || [host viewWithTag:kTMTagSlider]) return;
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(16, host.bounds.size.height - 96,
                                                             host.bounds.size.width - 32, 28)];
    s.tag = kTMTagSlider;
    s.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    s.minimumValue = 0;
    s.maximumValue = 1;
    s.hidden = !TMOn(@"videoSliderSeekBar");
    [s addTarget:self action:@selector(tm_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [host addSubview:s];
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tm_sliderTick:)
                                   userInfo:nil repeats:YES];
}

+ (void)tm_sliderTick:(__unused NSTimer *)timer {
    UIView *host = TMOverlayHost();
    UISlider *s = (UISlider *)[host viewWithTag:kTMTagSlider];
    if (!s || s.hidden || !g_activePlayer) return;
    if (s.isTracking) return;
    double t = TMDouble(g_activePlayer, @selector(currentPlaybackTime), -1);
    if (t < 0) return;
    s.value = (float)(t / TMPlayerDuration(g_activePlayer));
}

+ (void)tm_sliderChanged:(UISlider *)s {
    if (!g_activePlayer) return;
    SEL seek = NSSelectorFromString(@"_seekToTime:shouldPlay:");
    if (![g_activePlayer respondsToSelector:seek]) {
        NSLog(@"[TikTokMod] #30 seek: active player does not respond to _seekToTime:shouldPlay:");
        return;
    }
    double target = s.value * TMPlayerDuration(g_activePlayer);
    ((void (*)(id, SEL, double, BOOL))objc_msgSend)(g_activePlayer, seek, target, YES);
}

+ (void)tm_addFakeStatusBarToView:(UIView *)host {
    if (!host || [host viewWithTag:kTMTagFakeStatusBar]) return;
    CGFloat h = 44;
    UIWindowScene *scene = (UIWindowScene *)TMKeyWindow().windowScene;
    if (scene.statusBarManager) h = scene.statusBarManager.statusBarFrame.size.height ?: 44;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, host.bounds.size.width, h)];
    bar.tag = kTMTagFakeStatusBar;
    bar.backgroundColor = [UIColor blackColor];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    bar.hidden = !TMOn(@"fakeStatusBarPreview");
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm";
    UILabel *time = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 60, h)];
    time.text = [fmt stringFromDate:[NSDate date]];
    time.textColor = [UIColor whiteColor];
    time.font = [UIFont boldSystemFontOfSize:14];
    [bar addSubview:time];
    NSInteger bars = [TMSettings() fakeStatusBarSignalBars];
    UILabel *sig = [[UILabel alloc] initWithFrame:CGRectMake(host.bounds.size.width - 150, 0, 90, h)];
    sig.textAlignment = NSTextAlignmentRight;
    sig.textColor = [UIColor whiteColor];
    sig.font = [UIFont systemFontOfSize:13];
    NSMutableString *sigText = [NSMutableString string];
    for (NSInteger i = 0; i < 4; i++) [sigText appendString:(i < bars ? @"X" : @"-")];
    if ([TMSettings() fakeStatusBarWifiEnabled]) [sigText appendString:@" WiFi"];
    sig.text = sigText;
    [bar addSubview:sig];
    UILabel *bat = [[UILabel alloc] initWithFrame:CGRectMake(host.bounds.size.width - 56, 0, 48, h)];
    bat.textAlignment = NSTextAlignmentRight;
    bat.textColor = [UIColor whiteColor];
    bat.font = [UIFont systemFontOfSize:13];
    bat.text = device.batteryLevel >= 0
        ? [NSString stringWithFormat:@"%.0f%%", device.batteryLevel * 100]
        : @"--%";
    [bar addSubview:bat];
    [host addSubview:bar];
    NSLog(@"[TikTokMod] #39 fake status bar added (signal/wifi are user-set values, not live readings)");
}

+ (void)tm_addBurnInOverlayToView:(UIView *)host {
    if (!host || [host viewWithTag:kTMTagBurnInDim]) return;
    UIView *dim = [[UIView alloc] initWithFrame:host.bounds];
    dim.tag = kTMTagBurnInDim;
    dim.backgroundColor = [UIColor blackColor];
    dim.alpha = [TMSettings() feedOverlayOpacity];
    dim.userInteractionEnabled = NO;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.hidden = !TMOn(@"antiBurnInHideSystemBars");
    [host addSubview:dim];
    [NSTimer scheduledTimerWithTimeInterval:60 target:self
                                   selector:@selector(tm_burnInShift:) userInfo:nil repeats:YES];
}

+ (void)tm_burnInShift:(__unused NSTimer *)timer {
    UIView *host = TMOverlayHost();
    UIView *dim = [host viewWithTag:kTMTagBurnInDim];
    if (!dim || dim.hidden) return;
    static BOOL shifted = NO;
    shifted = !shifted;
    dim.frame = CGRectOffset(host.bounds, shifted ? 1 : 0, shifted ? 1 : 0);
}

+ (void)tm_applyCustomBackgroundToView:(UIView *)host {
    if (host) [TMSettings() applyCustomBackgroundToView:host];
}

+ (void)tm_updateOverlayVisibilityForView:(UIView *)host {
    if (!host) return;
    UIView *pip = [host viewWithTag:kTMTagPiPButton];
    if (pip) pip.hidden = !TMOn(@"pictureInPicture");
    UIView *slider = [host viewWithTag:kTMTagSlider];
    if (slider) slider.hidden = !TMOn(@"videoSliderSeekBar");
    UIView *fake = [host viewWithTag:kTMTagFakeStatusBar];
    if (fake) fake.hidden = !TMOn(@"fakeStatusBarPreview");
    UIView *dim = [host viewWithTag:kTMTagBurnInDim];
    if (dim) {
        dim.hidden = !TMOn(@"antiBurnInHideSystemBars");
        dim.alpha = [TMSettings() feedOverlayOpacity];
    }
    if (TMOn(@"customBackground")) [self tm_applyCustomBackgroundToView:host];
    else TMRemoveTagged(host, kTMTagCustomBg);
}

+ (void)tm_installEditorGestureOnView:(UIView *)host {
    if (!host) return;
    static char kTMEditorGestureKey;
    if (objc_getAssociatedObject(host, &kTMEditorGestureKey)) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(tm_editorTap:)];
    tap.numberOfTapsRequired = 2;
    [host addGestureRecognizer:tap];
    objc_setAssociatedObject(host, &kTMEditorGestureKey, tap,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)tm_editorTap:(UITapGestureRecognizer *)g {
    if (!TMOn(@"interfaceEditor")) return;
    if (g.state != UIGestureRecognizerStateRecognized) return;
    UIView *host = g.view;
    CGPoint p = [g locationInView:host];
    UIView *hit = [host hitTest:p withEvent:nil];
    while (hit && hit.tag >= 7001 && hit.tag <= 7010) hit = hit.superview;
    if (!hit || hit == host) {
        NSLog(@"[TikTokMod] #1 editor tap hit no stock element, ignoring");
        return;
    }
    TMShowHidePromptForView(hit);
}

@end

// ---------------------------------------------------------------------------
// Per-cell overlays (#1, #21, #28, #29, #35, #36, #43, #45 scrim)
// Called from the AWEFeedViewCell setupViewController hook.
// ---------------------------------------------------------------------------

@implementation TikTokModV1 (CellOverlays)

+ (void)applyCellOverlays:(UIView *)cellView {
    if (!cellView) return;
    // #1 — hide element classes the user picked in the editor.
    NSArray<NSString *> *hiddenClasses = [TMSettings() hiddenElementClasses];
    if (hiddenClasses.count > 0) {
        TMWalkViews(cellView, ^(UIView *v) {
            if ([hiddenClasses containsObject:NSStringFromClass([v class])]) v.hidden = YES;
        });
    }
    // #28 — hide the story tag view.
    if (TMOn(@"hideStory")) {
        TMWalkViews(cellView, ^(UIView *v) {
            if (TMClassNameContains(v, @"StoryTag") || TMClassNameContains(v, @"StoryCard")) v.hidden = YES;
        });
    }
    // #35 — hide live entry views in the cell.
    if (TMOn(@"hideLiveEntries")) {
        TMWalkViews(cellView, ^(UIView *v) {
            if (TMClassNameContains(v, @"LiveSkylight") || TMClassNameContains(v, @"LiveAvatarBubble") ||
                TMClassNameContains(v, @"SkylightLive")) v.hidden = YES;
        });
    }
    // #43 — hide the paid/Series preview tag (HIDE ONLY, never unlock).
    if (TMOn(@"hideSeriesRows")) {
        TMWalkViews(cellView, ^(UIView *v) {
            if (TMClassNameContains(v, @"PaidContentPreviewTag")) v.hidden = YES;
        });
    }
    // #36 — hide like/comment count labels (tap targets stay).
    if (TMOn(@"hideLikeViewCounts")) {
        TMWalkViews(cellView, ^(UIView *v) {
            if (!TMClassNameContains(v, @"LikeElement") && !TMClassNameContains(v, @"CommentElement")) return;
            for (UIView *sub in v.subviews) {
                if ([sub isKindOfClass:[UILabel class]]) sub.hidden = YES;
            }
        });
    }
    // #29 — hide UI with opacity control (alpha on the interaction elements).
    if (TMOn(@"hideUIOpacity")) {
        float alpha = [TMSettings() hideUIOpacityValue];
        TMWalkViews(cellView, ^(UIView *v) {
            if (TMClassNameContains(v, @"PlayInteraction") || TMClassNameContains(v, @"BottomBar")) {
                v.alpha = alpha;
            }
        });
        // Restore affordance: a small button to bring the UI back.
        if (alpha < 0.05 && ![cellView viewWithTag:kTMTagRestoreUI]) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.tag = kTMTagRestoreUI;
            [b setTitle:@"Show UI" forState:UIControlStateNormal];
            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            b.layer.cornerRadius = 12;
            b.frame = CGRectMake(cellView.bounds.size.width - 92, 120, 76, 26);
            b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
            [b addTarget:self action:@selector(tm_restoreUITapped:) forControlEvents:UIControlEventTouchUpInside];
            [cellView addSubview:b];
        }
    } else {
        TMRemoveTagged(cellView, kTMTagRestoreUI);
    }
    // #21 — post date label, from aweme.createTime (relative date, e.g. "12 Nov").
    if (TMOn(@"postDatesForYou")) {
        [self tm_addDateLabelToCell:cellView];
    } else {
        TMRemoveTagged(cellView, kTMTagDateLabel);
    }
    // #45 — dark scrim behind the caption text where the background shows through
    // (alpha 0.35-0.55). The video layer itself is NEVER made translucent.
    if (TMOn(@"customBackground")) {
        UIView *desc = TMFindView(cellView, ^BOOL(UIView *v) {
            return TMClassNameContains(v, @"DescriptionElement");
        });
        if (desc && ![desc.superview viewWithTag:kTMTagScrim]) {
            UIView *scrim = [[UIView alloc] initWithFrame:desc.frame];
            scrim.tag = kTMTagScrim;
            scrim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
            scrim.layer.cornerRadius = 6;
            scrim.autoresizingMask = desc.autoresizingMask;
            [desc.superview insertSubview:scrim belowSubview:desc];
        }
    } else {
        TMWalkViews(cellView, ^(UIView *v) {
            if (v.tag == kTMTagScrim) [v removeFromSuperview];
        });
    }
}

+ (void)tm_restoreUITapped:(UIButton *)sender {
    [TMSettings() setBool:NO forKey:@"hideUIOpacity"];
    [self refreshOverlays];
    UIView *cell = sender.superview;
    while (cell && ![NSStringFromClass([cell class]) containsString:@"FeedViewCell"]) {
        cell = cell.superview;
    }
    if (cell) [self applyCellOverlays:cell];
}

+ (void)tm_addDateLabelToCell:(UIView *)cellView {
    UILabel *label = (UILabel *)[cellView viewWithTag:kTMTagDateLabel];
    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectMake(12, cellView.bounds.size.height - 140, 120, 18)];
        label.tag = kTMTagDateLabel;
        label.font = [UIFont systemFontOfSize:12];
        label.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.85];
        label.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
        [cellView addSubview:label];
    }
    // aweme model: try the cell's likely model properties (fail-soft KVC).
    id aweme = TMValue(cellView, @"aweme");
    if (!aweme) aweme = TMValue(cellView, @"model");
    if (!aweme) aweme = TMValue(TMValue(cellView, @"viewController"), @"aweme");
    NSNumber *createTime = TMValue(aweme, @"createTime");
    if (!createTime || [createTime doubleValue] <= 0) {
        label.hidden = YES;
        return;
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[createTime doubleValue]];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"d MMM";
    label.text = [fmt stringFromDate:date];
    label.hidden = NO;
}

@end

// ---------------------------------------------------------------------------
// #4 "Read all" — drives the stock mark-all-read path with the user's selection
// ---------------------------------------------------------------------------

@implementation TikTokModV1 (ReadAll)

+ (void)tm_readAllTapped:(__unused UIButton *)sender {
    Class svc = NSClassFromString(@"AWEIMModuleService");
    if (!svc) {
        NSLog(@"[TikTokMod] #4 read-all: AWEIMModuleService not found (fail-soft)");
        return;
    }
    // Selected conversation IDs come only from the visible inbox VC (fail-soft KVC).
    UIViewController *top = TMTopViewController();
    NSArray *ids = TMValue(top, @"selectedConversationIDs");
    if (!ids) ids = TMValue(top, @"selectedConversationIds");
    if (!ids) ids = TMValue(top, @"conversationIDs");
    if ([ids isKindOfClass:[NSArray class]] && ids.count > 0 &&
        [svc respondsToSelector:@selector(markAllMessagesReadForConversationIDs:completion:)]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(
            svc, @selector(markAllMessagesReadForConversationIDs:completion:), ids, nil);
        NSLog(@"[TikTokMod] #4 read-all: marked %lu conversations read", (unsigned long)ids.count);
        return;
    }
    // Fallback: the adapter's mark-all (no IDs needed).
    id adapter = TMValue(top, @"flowAdapter");
    if (!adapter) adapter = TMValue(top, @"adapter");
    if (adapter && [adapter respondsToSelector:@selector(markAllReadWithCompletion:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(adapter, @selector(markAllReadWithCompletion:), nil);
        NSLog(@"[TikTokMod] #4 read-all: adapter markAllRead called");
        return;
    }
    NSLog(@"[TikTokMod] #4 read-all: no selected conversations / adapter found, nothing marked");
}

@end

// ---------------------------------------------------------------------------
// #20 icons / #40 startup / #41 OTA / #42 Telegram
// ---------------------------------------------------------------------------

@implementation TikTokModV1 (HubActions)

+ (NSArray<NSDictionary *> *)alternateIcons {
    // 7 styles: stock Default + the 6 named styles from the APK's
    // ttmod_launcher_* resources. iconName must match a CFBundleAlternateIcons
    // key added at assembly time (see TikTokMod/Icons/ASSEMBLY-README.md).
    return @[
        @{@"title": @"Default (stock)", @"iconName": [NSNull null]},
        @{@"title": @"Cheese", @"iconName": @"Cheese"},
        @{@"title": @"HLX", @"iconName": @"HLX"},
        @{@"title": @"MD", @"iconName": @"MD"},
        @{@"title": @"Metal", @"iconName": @"Metal"},
        @{@"title": @"Nostalgic", @"iconName": @"Nostalgic"},
        @{@"title": @"Parody", @"iconName": @"Parody"},
    ];
}

+ (void)applyAlternateIconNamed:(nullable NSString *)iconName
           fromViewController:(UIViewController *)vc {
    if (![UIApplication.sharedApplication supportsAlternateIcons]) {
        NSLog(@"[TikTokMod] #20 alternate icons not supported on this device");
        return;
    }
    [UIApplication.sharedApplication setAlternateIconName:iconName
                                        completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[TikTokMod] #20 setAlternateIconName failed: %@ "
                  @"(icon sets must exist in the bundle at assembly time)", error);
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Icon not applied"
                message:@"The icon set is missing from the app bundle (assembly-time step). Current icon kept."
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [vc presentViewController:a animated:YES completion:nil];
        } else {
            [TMSettings() setSelectedAlternateIconName:iconName];
            NSLog(@"[TikTokMod] #20 alternate icon set: %@", iconName ?: @"Default");
        }
    }];
}

+ (void)presentStartupScreen {
    static dispatch_once_t onceToken;
    // Present at most once per launch; the hub can re-show it on demand.
    dispatch_once(&onceToken, ^{
        [self presentStartupScreenNow];
    });
}

+ (void)presentStartupScreenNow {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self tm_presentStartupNow];
    });
}

+ (void)tm_presentStartupNow {
    UIViewController *top = TMTopViewController();
    if (!top) {
        // Too early (no window yet) — retry shortly; never block launch.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self tm_presentStartupNow];
        });
        return;
    }
    if ([top isKindOfClass:[TikTokModStartupViewController class]]) return;
    TikTokModStartupViewController *vc = [[TikTokModStartupViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:vc animated:YES completion:nil];
    NSLog(@"[TikTokMod] #40 startup screen presented");
}

+ (void)checkForUpdatesFromViewController:(UIViewController *)vc {
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/dolanexeee/TikTokMod/releases/latest"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = nil;
            NSString *htmlURL = nil;
            NSString *tag = nil;
            if (error || !data) {
                msg = @"Update check failed (no network / GitHub unreachable). The hub still works fully offline.";
                NSLog(@"[TikTokMod] #41 OTA check failed: %@", error);
            } else {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                tag = json[@"tag_name"];
                htmlURL = json[@"html_url"];
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
                if (http.statusCode != 200 || !tag) {
                    msg = @"Update check failed (unexpected GitHub response). The hub still works fully offline.";
                } else if ([tag isEqualToString:kTikTokModVersion]) {
                    msg = [NSString stringWithFormat:@"You are up to date (%@).", kTikTokModVersion];
                } else {
                    msg = [NSString stringWithFormat:@"Update available: %@ (you have %@).\n\n"
                           @"A new dylib applies after re-assembly and re-sign — a loaded dylib cannot hot-patch itself.",
                           tag, kTikTokModVersion];
                }
            }
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Mod updates (#41)"
                message:msg preferredStyle:UIAlertControllerStyleAlert];
            if (htmlURL) {
                [a addAction:[UIAlertAction actionWithTitle:@"Open release" style:UIAlertActionStyleDefault
                    handler:^(__unused UIAlertAction *act) {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:htmlURL]
                                                       options:@{} completionHandler:nil];
                }]];
            }
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [vc presentViewController:a animated:YES completion:nil];
        });
    }];
    [task resume];
}

+ (void)openTelegramFromViewController:(UIViewController *)vc {
    NSString *urlString = [TMSettings() telegramCommunityURL];
    if (!urlString || urlString.length == 0) {
        // No concrete t.me URL exists in the research (design §3 #42: the URL
        // is hub config, not code) — ask for it instead of inventing one.
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Telegram community"
            message:@"No Telegram link is configured yet. Paste the community t.me link:"
            preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"https://t.me/...";
            tf.keyboardType = UIKeyboardTypeURL;
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"Save & Open" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *act) {
            NSString *entered = a.textFields.firstObject.text;
            if (entered.length > 0) {
                [TMSettings() setTelegramCommunityURL:entered];
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:entered]
                                                   options:@{} completionHandler:nil];
            }
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        UIPasteboard.generalPasteboard.string = urlString;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Telegram link"
            message:@"Could not open the link — it was copied to the pasteboard instead."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    }
}

@end

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Swizzled implementations.
// The UIViewController dispatcher below is a category on UIKit (linked, fine).
// TikTok classes are hooked at runtime (see the Runtime hooks section).
// ---------------------------------------------------------------------------

static const NSInteger kTMTagDrawButton = 7011;

@interface TikTokModV1 (Private)
+ (void)tm_feedRootAppeared:(UIViewController *)vc;
+ (void)tm_feedContainerAppeared:(UIViewController *)vc;
+ (void)tm_addDrawButtonToView:(UIView *)host;
+ (void)tm_addReadAllButtonToVC:(UIViewController *)vc;
+ (void)tm_settingsChanged:(NSNotification *)note;
@end

// --- Generic dispatcher: every UIViewController viewDidLoad ---
@interface UIViewController (TikTokModV1)
- (void)tm_viewDidLoad;
@end

@implementation UIViewController (TikTokModV1)

- (void)tm_viewDidLoad {
    [self tm_viewDidLoad]; // after exchange: the original viewDidLoad
    NSString *name = NSStringFromClass([self class]);
    if ([name containsString:@"FeedRoot"]) {
        [TikTokModV1 tm_feedRootAppeared:self];
    } else if ([name containsString:@"FeedContainer"]) {
        [TikTokModV1 tm_feedContainerAppeared:self];
    } else if ([name containsString:@"Profile"]) {
        // #45 profile surface (clean — no video layer here).
        if (TMOn(@"customBackground")) [TMSettings() applyCustomBackgroundToView:self.view];
    } else if ([name containsString:@"Chat"] || [name containsString:@"IMChat"]) {
        // #45 chat surface (stock wallpaper path is separate; overlay fallback).
        if (TMOn(@"customBackground")) [TMSettings() applyCustomBackgroundToView:self.view];
    } else if ([name containsString:@"Inbox"] || [name containsString:@"ConversationList"]) {
        // #4 entry: "Read all" button (candidate: multi-select UI).
        [TikTokModV1 tm_addReadAllButtonToVC:self];
    } else if ([name containsString:@"Setting"] && [self isKindOfClass:[UITableViewController class]]) {
        // #9 candidate B: secondary hub entry from stock Settings.
        if (!self.navigationItem.rightBarButtonItem) {
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                initWithTitle:@"TikTokMod" style:UIBarButtonItemStylePlain
                       target:[TikTokModV1 class] action:@selector(tm_modButtonTapped)];
        }
    }
}

@end

// ---------------------------------------------------------------------------
// Runtime hooks (NO ObjC categories on TikTok classes).
// WHY: a category on an external class emits a link-time _OBJC_CLASS_$_<class>
// reference, and TikTok's classes live in MusicallyCore, not in this dylib —
// the link fails. Runtime injection (class_addMethod + IMP swap) references
// the class only through NSClassFromString at runtime, so a missing class is
// a logged no-op, never a link error or a crash.
// Each site stores its original IMP in a static; the replacement IMP calls
// through it when the toggle is OFF.
// ---------------------------------------------------------------------------

static IMP g_orig_Container_viewDidLoad = NULL;
static IMP g_orig_Root_viewDidLoad = NULL;
static IMP g_orig_Root_prefersStatusBarHidden = NULL;
static IMP g_orig_Cell_setupViewController = NULL;
static IMP g_orig_Player_setPlaybackRate = NULL;
static IMP g_orig_Player_setCurrentPlaybackRate = NULL;
static IMP g_orig_Player_seekToTime = NULL;
static IMP g_orig_Engine_setPlaybackSpeed = NULL;
static IMP g_orig_PiP1_supported = NULL;
static IMP g_orig_PiP2_supported = NULL;
static IMP g_orig_PiPGate = NULL;
static IMP g_orig_ReadAllEnable = NULL;
static IMP g_orig_StoryMount = NULL;
static IMP g_orig_StoryBar = NULL;
static IMP g_orig_DataSource = NULL;
static IMP g_orig_BannerLayout = NULL;
static IMP g_orig_PhotoButton = NULL;
static IMP g_orig_LiveBadge = NULL;
static IMP g_orig_StreakView = NULL;
static IMP g_orig_StreakSwitch = NULL;
static IMP g_orig_SeriesTagSetup = NULL;
static IMP g_orig_AppDidFinishLaunching = NULL;

// --- Feed root / container ---
static void TMHook_Container_viewDidLoad(id self, SEL _cmd) {
    ((void (*)(id, SEL))g_orig_Container_viewDidLoad)(self, _cmd);
    [TikTokModV1 tm_feedContainerAppeared:(UIViewController *)self];
}

static void TMHook_Root_viewDidLoad(id self, SEL _cmd) {
    ((void (*)(id, SEL))g_orig_Root_viewDidLoad)(self, _cmd);
    [TikTokModV1 retryDeferredInstalls];
}

static BOOL TMHook_Root_prefersStatusBarHidden(id self, SEL _cmd) {
    // #8 / #39: hide the real status bar while the overlay/fake bar is up.
    if (TMOn(@"antiBurnInHideSystemBars") || TMOn(@"fakeStatusBarPreview")) return YES;
    return ((BOOL (*)(id, SEL))g_orig_Root_prefersStatusBarHidden)(self, _cmd);
}

// --- Feed cell ---
static void TMHook_Cell_setupViewController(id self, SEL _cmd) {
    ((void (*)(id, SEL))g_orig_Cell_setupViewController)(self, _cmd);
    if ([(id)self isKindOfClass:[UIView class]]) {
        [TikTokModV1 applyCellOverlays:(UIView *)self];
    }
}

// --- Player: speed (#2) + active-player tracking (#30) ---
static void TMHook_Player_setPlaybackRate(id self, SEL _cmd, float rate) {
    g_activePlayer = self;
    if (TMOn(@"playbackSpeed3x")) {
        ((void (*)(id, SEL, float))g_orig_Player_setPlaybackRate)(self, _cmd, [TMSettings() playbackRateValue]);
        return;
    }
    ((void (*)(id, SEL, float))g_orig_Player_setPlaybackRate)(self, _cmd, rate);
}

static void TMHook_Player_setCurrentPlaybackRate(id self, SEL _cmd, float rate) {
    g_activePlayer = self;
    if (TMOn(@"playbackSpeed3x")) {
        ((void (*)(id, SEL, float))g_orig_Player_setCurrentPlaybackRate)(self, _cmd, [TMSettings() playbackRateValue]);
        return;
    }
    ((void (*)(id, SEL, float))g_orig_Player_setCurrentPlaybackRate)(self, _cmd, rate);
}

static void TMHook_Player_seekToTime(id self, SEL _cmd, double time, BOOL play) {
    g_activePlayer = self;
    ((void (*)(id, SEL, double, BOOL))g_orig_Player_seekToTime)(self, _cmd, time, play);
}

static void TMHook_Engine_setPlaybackSpeed(id self, SEL _cmd, float speed) {
    if (TMOn(@"playbackSpeed3x")) speed = [TMSettings() playbackRateValue];
    ((void (*)(id, SEL, float))g_orig_Engine_setPlaybackSpeed)(self, _cmd, speed);
}

// --- PiP (#3): force the stock gates open ---
static BOOL TMHook_PiP_supported(id self, SEL _cmd, IMP orig) {
    if (TMOn(@"pictureInPicture")) return YES;
    return ((BOOL (*)(id, SEL))orig)(self, _cmd);
}

static BOOL TMHook_PiP1_supported(id self, SEL _cmd) {
    return TMHook_PiP_supported(self, _cmd, g_orig_PiP1_supported);
}

static BOOL TMHook_PiP2_supported(id self, SEL _cmd) {
    return TMHook_PiP_supported(self, _cmd, g_orig_PiP2_supported);
}

static BOOL TMHook_PiPGate(id self, SEL _cmd) {
    if (TMOn(@"pictureInPicture")) return YES;
    return ((BOOL (*)(id, SEL))g_orig_PiPGate)(self, _cmd);
}

// --- Read-all (#4): force the stock enable flag (class method) ---
static BOOL TMHook_ReadAllEnable(id self, SEL _cmd) {
    if (TMOn(@"readAllChats")) return YES;
    return ((BOOL (*)(id, SEL))g_orig_ReadAllEnable)(self, _cmd);
}

// --- Story (#28) ---
static void TMHook_StoryMount(id self, SEL _cmd) {
    if (TMOn(@"hideStory")) return; // suppress the story overlay entirely
    ((void (*)(id, SEL))g_orig_StoryMount)(self, _cmd);
}

static BOOL TMHook_StoryBar(id self, SEL _cmd) {
    if (TMOn(@"hideStory")) return YES;
    return ((BOOL (*)(id, SEL))g_orig_StoryBar)(self, _cmd);
}

// --- Data source filter (#34 photo, #35 live, #43 series) ---
static id TMHook_DataSource_filteredDataSource(id self, SEL _cmd) {
    NSArray *orig = ((id (*)(id, SEL))g_orig_DataSource)(self, _cmd);
    if (!orig) return orig;
    BOOL hidePhoto = TMOn(@"hidePhotoMode");
    BOOL hideLive = TMOn(@"hideLiveEntries");
    BOOL hideSeries = TMOn(@"hideSeriesRows");
    if (!hidePhoto && !hideLive && !hideSeries) return orig;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:orig.count];
    for (id item in orig) {
        BOOL drop = NO;
        if (hidePhoto && (TMBoolValue(item, @"isNowPhoto") || TMBoolValue(item, @"isStoryPhoto"))) drop = YES;
        if (!drop && hideLive) {
            if (TMBoolValue(item, @"judgeWhetherHasLiveRoomModel") || TMValue(item, @"liveRoomModel") != nil) drop = YES;
        }
        if (!drop && hideSeries && TMBoolValue(item, @"is_series")) drop = YES;
        if (!drop) [kept addObject:item];
    }
    if (kept.count != orig.count) {
        NSLog(@"[TikTokMod] filteredDataSource: %lu -> %lu items (photo/live/series hides)",
              (unsigned long)orig.count, (unsigned long)kept.count);
    }
    return [kept copy];
}

// --- Banners (#14, banners only — layout half is DEFER) ---
static void TMHook_BannerLayout(id self, SEL _cmd) {
    ((void (*)(id, SEL))g_orig_BannerLayout)(self, _cmd);
    if (!TMOn(@"bannersNewProfileLayout")) return;
    for (UIView *sub in ((UIView *)self).subviews) {
        if ([NSStringFromClass([sub class]) containsString:@"Banner"]) {
            sub.hidden = NO;
            sub.alpha = 1.0;
        }
    }
}

// --- Photo-mode entry (#34) ---
static void TMHook_PhotoButton(id self, SEL _cmd, BOOL show) {
    if (TMOn(@"hidePhotoMode")) show = NO;
    ((void (*)(id, SEL, BOOL))g_orig_PhotoButton)(self, _cmd, show);
}

// --- Live badge (#35) ---
static BOOL TMHook_LiveBadge(id self, SEL _cmd) {
    if (TMOn(@"hideLiveEntries")) return NO;
    return ((BOOL (*)(id, SEL))g_orig_LiveBadge)(self, _cmd);
}

// --- Streak badges (#37) ---
static void TMHook_StreakView(id self, SEL _cmd, id model) {
    if (TMOn(@"hideStreakBadges")) return;
    ((void (*)(id, SEL, id))g_orig_StreakView)(self, _cmd, model);
}

static BOOL TMHook_StreakSwitch(id self, SEL _cmd) {
    if (TMOn(@"hideStreakBadges")) return YES;
    return ((BOOL (*)(id, SEL))g_orig_StreakSwitch)(self, _cmd);
}

// --- Series paid tag (#43, HIDE ONLY) ---
static void TMHook_SeriesTagSetup(id self, SEL _cmd) {
    ((void (*)(id, SEL))g_orig_SeriesTagSetup)(self, _cmd);
    if (TMOn(@"hideSeriesRows")) ((UIView *)self).hidden = YES;
}

// --- Startup screen (#40): AppDelegate launch hook, fallback is feed-root ---
static BOOL TMHook_AppDidFinishLaunching(id self, SEL _cmd, UIApplication *app, NSDictionary *opts) {
    BOOL result = ((BOOL (*)(id, SEL, id, id))g_orig_AppDidFinishLaunching)(self, _cmd, app, opts);
    if (TMOn(@"startupScreen")) [TikTokModV1 presentStartupScreen];
    return result;
}


// ---------------------------------------------------------------------------
// Installer
// ---------------------------------------------------------------------------

/// Install one runtime hook site: resolve the class, check the original
/// method exists and its return type matches (BOOL sites accept 'B' or 'c'),
/// then add our IMP under an alias selector and exchange implementations.
/// Fail-soft everywhere; returns NO (with NSLog) on any miss.
static BOOL TMInstallSite(NSString *className, SEL origSel, IMP newImp, IMP *outOrig,
                          BOOL classMethod, const char *retPrefix) {
    Class cls = [TikTokMod safeClass:className];
    if (!cls) return NO;
    Class target = classMethod ? object_getClass(cls) : cls;
    Method m = classMethod ? class_getClassMethod(cls, origSel)
                           : class_getInstanceMethod(cls, origSel);
    if (!m) {
        NSLog(@"[TikTokMod] V1 site %@ %@ not found, skipping (fail-soft)",
              className, NSStringFromSelector(origSel));
        return NO;
    }
    if (retPrefix) {
        const char *enc = method_getTypeEncoding(m);
        char got = enc ? enc[0] : '?';
        BOOL ok = (got == retPrefix[0]) ||
                  (retPrefix[0] == 'B' && got == 'c') ||
                  (retPrefix[0] == 'c' && got == 'B');
        if (!ok) {
            NSLog(@"[TikTokMod] V1 site %@ %@: unexpected return type '%c', skipping (fail-soft)",
                  className, NSStringFromSelector(origSel), got);
            return NO;
        }
    }
    NSString *aliasName = [@"tm_orig_" stringByAppendingString:NSStringFromSelector(origSel)];
    SEL aliasSel = NSSelectorFromString(aliasName);
    if (!class_addMethod(target, aliasSel, newImp, method_getTypeEncoding(m))) {
        NSLog(@"[TikTokMod] V1 site %@ %@: alias %@ already exists, skipping",
              className, NSStringFromSelector(origSel), aliasName);
        return NO;
    }
    *outOrig = method_getImplementation(m);
    Method aliasMethod = class_getInstanceMethod(target, aliasSel);
    method_exchangeImplementations(m, aliasMethod);
    NSLog(@"[TikTokMod] V1 hook installed: %@ %@", className, NSStringFromSelector(origSel));
    return YES;
}

static BOOL g_v1InstalledContainer = NO;
static BOOL g_v1InstalledRoot = NO;
static BOOL g_v1InstalledRootBar = NO;
static BOOL g_v1InstalledCell = NO;
static BOOL g_v1InstalledPlayerRate = NO;
static BOOL g_v1InstalledPlayerCurrentRate = NO;
static BOOL g_v1InstalledPlayerSeek = NO;
static BOOL g_v1InstalledEngineSpeed = NO;
static BOOL g_v1InstalledPiP1 = NO;
static BOOL g_v1InstalledPiP2 = NO;
static BOOL g_v1InstalledPiPGate = NO;
static BOOL g_v1InstalledReadAll = NO;
static BOOL g_v1InstalledStoryMount = NO;
static BOOL g_v1InstalledStoryBar = NO;
static BOOL g_v1InstalledDataSource = NO;
static BOOL g_v1InstalledBanner = NO;
static BOOL g_v1InstalledPhotoButton = NO;
static BOOL g_v1InstalledLiveBadge = NO;
static BOOL g_v1InstalledStreakView = NO;
static BOOL g_v1InstalledStreakSwitch = NO;
static BOOL g_v1InstalledSeriesTag = NO;
static BOOL g_v1InstalledAppDelegate = NO;

+ (void)retryDeferredInstalls {
    if (!g_v1InstalledContainer) {
        g_v1InstalledContainer = TMInstallSite(@"AWEFeedContainerViewController",
            @selector(viewDidLoad), (IMP)TMHook_Container_viewDidLoad,
            &g_orig_Container_viewDidLoad, NO, "v");
    }
    if (!g_v1InstalledRoot) {
        g_v1InstalledRoot = TMInstallSite(@"AWEFeedRootViewController",
            @selector(viewDidLoad), (IMP)TMHook_Root_viewDidLoad,
            &g_orig_Root_viewDidLoad, NO, "v");
    }
    if (!g_v1InstalledRootBar) {
        g_v1InstalledRootBar = TMInstallSite(@"AWEFeedRootViewController",
            @selector(prefersStatusBarHidden), (IMP)TMHook_Root_prefersStatusBarHidden,
            &g_orig_Root_prefersStatusBarHidden, NO, "B");
    }
    if (!g_v1InstalledCell) {
        g_v1InstalledCell = TMInstallSite(@"AWEFeedViewCell",
            @selector(setupViewController), (IMP)TMHook_Cell_setupViewController,
            &g_orig_Cell_setupViewController, NO, "v");
    }
    if (!g_v1InstalledPlayerRate) {
        g_v1InstalledPlayerRate = TMInstallSite(@"AWEVideoPlayerController",
            @selector(setPlaybackRate:), (IMP)TMHook_Player_setPlaybackRate,
            &g_orig_Player_setPlaybackRate, NO, "v");
    }
    if (!g_v1InstalledPlayerCurrentRate) {
        g_v1InstalledPlayerCurrentRate = TMInstallSite(@"AWEVideoPlayerController",
            @selector(setCurrentPlaybackRate:), (IMP)TMHook_Player_setCurrentPlaybackRate,
            &g_orig_Player_setCurrentPlaybackRate, NO, "v");
    }
    if (!g_v1InstalledPlayerSeek) {
        g_v1InstalledPlayerSeek = TMInstallSite(@"AWEVideoPlayerController",
            NSSelectorFromString(@"_seekToTime:shouldPlay:"),
            (IMP)TMHook_Player_seekToTime, &g_orig_Player_seekToTime, NO, "v");
    }
    if (!g_v1InstalledEngineSpeed) {
        g_v1InstalledEngineSpeed = TMInstallSite(@"TTVideoEngine",
            @selector(setPlaybackSpeed:), (IMP)TMHook_Engine_setPlaybackSpeed,
            &g_orig_Engine_setPlaybackSpeed, NO, "v");
    }
    if (!g_v1InstalledPiP1) {
        g_v1InstalledPiP1 = TMInstallSite(@"TTKMediaPiPController",
            @selector(isPictureInPictureSupported), (IMP)TMHook_PiP1_supported,
            &g_orig_PiP1_supported, NO, "B");
    }
    if (!g_v1InstalledPiP2) {
        g_v1InstalledPiP2 = TMInstallSite(@"TTPictureInPictureController",
            @selector(isPictureInPictureSupported), (IMP)TMHook_PiP2_supported,
            &g_orig_PiP2_supported, NO, "B");
    }
    if (!g_v1InstalledPiPGate) {
        g_v1InstalledPiPGate = TMInstallSite(@"TTKFeedAppDiffComponent",
            @selector(feedPictureInPictureEntrance), (IMP)TMHook_PiPGate,
            &g_orig_PiPGate, NO, "B");
    }
    if (!g_v1InstalledReadAll) {
        g_v1InstalledReadAll = TMInstallSite(@"AWEIMModuleService",
            @selector(inboxReadAllEnable), (IMP)TMHook_ReadAllEnable,
            &g_orig_ReadAllEnable, YES, "B");
    }
    if (!g_v1InstalledStoryMount) {
        g_v1InstalledStoryMount = TMInstallSite(@"TTKStory2FeedOverlayViewComponent",
            @selector(componentMount), (IMP)TMHook_StoryMount,
            &g_orig_StoryMount, NO, "v");
    }
    if (!g_v1InstalledStoryBar) {
        g_v1InstalledStoryBar = TMInstallSite(@"AWEAwemeModel",
            @selector(hideStoryBottomBar), (IMP)TMHook_StoryBar,
            &g_orig_StoryBar, NO, "B");
    }
    if (!g_v1InstalledDataSource) {
        g_v1InstalledDataSource = TMInstallSite(@"AWEListDataController",
            @selector(filteredDataSource), (IMP)TMHook_DataSource_filteredDataSource,
            &g_orig_DataSource, NO, "@");
    }
    if (!g_v1InstalledBanner) {
        g_v1InstalledBanner = TMInstallSite(@"TTKStandardProfileBannerContainer",
            @selector(layoutSubviews), (IMP)TMHook_BannerLayout,
            &g_orig_BannerLayout, NO, "v");
    }
    if (!g_v1InstalledPhotoButton) {
        g_v1InstalledPhotoButton = TMInstallSite(@"TTKPhotoModeCommentEntranceView",
            @selector(setShouldShowPhotoButton:), (IMP)TMHook_PhotoButton,
            &g_orig_PhotoButton, NO, "v");
    }
    if (!g_v1InstalledLiveBadge) {
        g_v1InstalledLiveBadge = TMInstallSite(@"AWEFeedContainerViewController",
            @selector(shouldShowLiveBadge), (IMP)TMHook_LiveBadge,
            &g_orig_LiveBadge, NO, "B");
    }
    if (!g_v1InstalledStreakView) {
        g_v1InstalledStreakView = TMInstallSite(@"AWEManagedStreakView",
            @selector(updateStreakModel:), (IMP)TMHook_StreakView,
            &g_orig_StreakView, NO, "v");
    }
    if (!g_v1InstalledStreakSwitch) {
        g_v1InstalledStreakSwitch = TMInstallSite(@"_TtC17TikTokIMImplSwift24AWEIMExtensionStreakInfo",
            @selector(disableStreak), (IMP)TMHook_StreakSwitch,
            &g_orig_StreakSwitch, NO, "B");
    }
    if (!g_v1InstalledSeriesTag) {
        g_v1InstalledSeriesTag = TMInstallSite(@"AWEFeedPaidContentPreviewTagView",
            NSSelectorFromString(@"_setupUI"), (IMP)TMHook_SeriesTagSetup,
            &g_orig_SeriesTagSetup, NO, "v");
    }
    if (!g_v1InstalledAppDelegate) {
        g_v1InstalledAppDelegate = TMInstallSite(@"AppDelegate",
            @selector(application:didFinishLaunchingWithOptions:),
            (IMP)TMHook_AppDidFinishLaunching, &g_orig_AppDidFinishLaunching, NO, "B");
    }
}

+ (void)tm_settingsChanged:(NSNotification *)note {
    NSString *key = note.userInfo[@"key"];
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self tm_settingsChanged:note]; });
        return;
    }
    // #2: re-apply the stored rate to the active player immediately.
    if ([key isEqualToString:@"playbackSpeed3x"] && TMOn(@"playbackSpeed3x") && g_activePlayer) {
        if ([g_activePlayer respondsToSelector:@selector(setPlaybackRate:)]) {
            ((void (*)(id, SEL, float))objc_msgSend)(g_activePlayer, @selector(setPlaybackRate:),
                                                     [TMSettings() playbackRateValue]);
        }
    }
    [self refreshOverlays];
}

+ (void)refreshOverlays {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshOverlays]; });
        return;
    }
    UIView *host = TMOverlayHost();
    if (host) [self tm_updateOverlayVisibilityForView:host];
    // Draw button follows its toggle too.
    if (host) {
        UIView *drawBtn = [host viewWithTag:kTMTagDrawButton];
        if (drawBtn) drawBtn.hidden = !TMOn(@"drawingTool");
        else if (TMOn(@"drawingTool")) [self tm_addDrawButtonToView:host];
    }
    // Read-all button follows its toggle on the visible inbox VC.
    UIViewController *top = TMTopViewController();
    if (top && ([NSStringFromClass([top class]) containsString:@"Inbox"] ||
                [NSStringFromClass([top class]) containsString:@"ConversationList"])) {
        [self tm_addReadAllButtonToVC:top];
    }
}

+ (void)tm_feedRootAppeared:(UIViewController *)vc {
    [self retryDeferredInstalls];
    if (vc.view && TMOn(@"customBackground")) {
        [self tm_applyCustomBackgroundToView:vc.view];
    }
    // #40 fallback: AppDelegate hook missed (class not yet loaded) — show here.
    if (TMOn(@"startupScreen")) [self presentStartupScreen];
}

+ (void)tm_feedContainerAppeared:(UIViewController *)vc {
    UIView *view = vc.view;
    if (!view) return;
    [self tm_addModButtonToView:view];
    [self tm_addPiPButtonToView:view];
    [self tm_addSliderToView:view];
    [self tm_addFakeStatusBarToView:view];
    [self tm_addBurnInOverlayToView:view];
    [self tm_addDrawButtonToView:view];
    [self tm_installEditorGestureOnView:view];
    if (TMOn(@"customBackground")) [self tm_applyCustomBackgroundToView:view];
}

+ (void)tm_addDrawButtonToView:(UIView *)host {
    if (!host || [host viewWithTag:kTMTagDrawButton]) return;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.tag = kTMTagDrawButton;
    [b setTitle:@"Draw" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    b.layer.cornerRadius = 14;
    b.frame = CGRectMake(host.bounds.size.width - 72, 128, 56, 28);
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    b.hidden = !TMOn(@"drawingTool");
    [b addTarget:self action:@selector(tm_drawButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:b];
}

+ (void)tm_drawButtonTapped {
    UIView *host = TMOverlayHost();
    if (!host || [host viewWithTag:kTMTagDrawOverlay]) return;
    TikTokModDrawView *d = [[TikTokModDrawView alloc] initWithFrame:host.bounds];
    d.tag = kTMTagDrawOverlay;
    d.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:d];
    NSLog(@"[TikTokMod] #38 drawing overlay opened");
}

+ (void)tm_addReadAllButtonToVC:(UIViewController *)vc {
    if (!vc || !TMOn(@"readAllChats")) return;
    UIBarButtonItem *existing = vc.navigationItem.rightBarButtonItem;
    if (existing && [existing.title isEqualToString:@"Read all"]) return;
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Read all" style:UIBarButtonItemStylePlain
               target:[TikTokModV1 class] action:@selector(tm_readAllTapped:)];
}

@end
