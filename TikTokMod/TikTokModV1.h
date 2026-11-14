//
//  TikTokModV1.h
//  TikTokMod V1 (DYLIB-DESIGN.md §4): 24 features — unlocks, overlays, easy.
//  Every hook is fail-soft: a missing TikTok class/selector is a no-op + NSLog.
//  No iOS device exists on the build VM, so NOTHING here is runtime-verified:
//  compile + artifact level only. Test on a secondary account only.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Current mod version, compared against the latest GitHub release tag by #41 OTA.
extern NSString * const kTikTokModVersion;

@interface TikTokModV1 : NSObject

/// Install every V1 hook site that resolves. Missed sites are retried from
/// AWEFeedRootViewController viewDidLoad (see +retryDeferredInstalls).
+ (void)installV1Hooks;

/// Re-attempt hook sites whose class was not yet loaded at launch.
/// Called on each AWEFeedRootViewController viewDidLoad until all install.
+ (void)retryDeferredInstalls;

/// Re-apply overlay visibility/state to the current feed (called when a
/// toggle changes via TikTokModSettingsDidChangeNotification).
+ (void)refreshOverlays;

/// Apply per-cell V1 overlays/hides to a feed cell view (#1, #21, #28, #29,
/// #35, #36, #43, #45 scrim). Called from the AWEFeedViewCell hook.
+ (void)applyCellOverlays:(UIView *)cellView;

/// #20 — alternate icons. 7 styles: Default (stock) + 6 from the APK.
/// Names match CFBundleAlternateIcons keys the assembler adds to Info.plist.
+ (NSArray<NSDictionary *> *)alternateIcons; // @{@"title", @"iconName" (NSNull = default)}
+ (void)applyAlternateIconNamed:(nullable NSString *)iconName
           fromViewController:(UIViewController *)vc;

/// #40 — present the startup screen now (also shown on launch when enabled).
+ (void)presentStartupScreen;

/// #40 — present the startup screen immediately (hub "show again", no once-guard).
+ (void)presentStartupScreenNow;

/// #41/#15 — check GitHub releases for a newer dylib; result shown in an alert.
+ (void)checkForUpdatesFromViewController:(UIViewController *)vc;

/// #42 — open the Telegram community URL from hub config (or ask for it).
+ (void)openTelegramFromViewController:(UIViewController *)vc;

/// #30 — the active player (weak), tracked by the player hooks, for the slider.
+ (nullable id)activePlayer;

@end

NS_ASSUME_NONNULL_END
