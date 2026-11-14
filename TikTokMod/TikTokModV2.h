//
//  TikTokModV2.h
//  TikTokMod V2 (DYLIB-DESIGN.md §4): 13 features — #5, #6, #7, #13, #16, #17,
//  #19, #22, #23, #26, #31, #32, #33 (per-surface only; global theme engine DEFER).
//  Same binding rules as V1: every class/selector below comes from
//  RESEARCH-LOG.md / INJECTION-ANALYSIS.md / class-map.txt. Nothing invented.
//  Runtime IMP injection only for TikTok classes (alias prefix "tm2_orig_") —
//  no categories on TikTok classes, no link-time refs to TikTok classes.
//  Missing target = no-op + NSLog, never a crash. Every hook reads its live
//  toggle per call and falls through to stock behaviour when OFF.
//  No iOS device exists on the build VM, so NOTHING here is runtime-verified:
//  compile + artifact level only. Test on a secondary account only.
//  UNVERIFIED (client lift only, server may refuse): #5, #6, #13, #17, #26.
//  PARTIAL: #7 colored selfie flash (frontFlashColor is a real field, not a
//  proven user-facing toggle) — shipped as an experimental sub-toggle.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TikTokModV2 : NSObject

/// Install every V2 hook site that resolves. Missed sites are retried from
/// AWEFeedRootViewController viewDidLoad via +retryDeferredInstalls (called
/// from TikTokModV1's feed-root appearance path).
+ (void)installV2Hooks;

/// Re-attempt V2 hook sites whose class was not yet loaded at launch.
+ (void)retryDeferredInstalls;

/// #22 — feed-item predicate used by V1's filteredDataSource hook.
/// Returns YES when the item must be dropped (words/tags/likes/views).
/// Toggle-gated: returns NO whenever contentFilters is OFF.
+ (BOOL)shouldDropFeedItem:(id)item;

/// #22 — open TikTok's stock keyword-filter editor
/// (PNSFeedFilterKeywordsManager openFilterKeywordWithEnterFrom:popup:).
+ (void)openStockKeywordFilterFromViewController:(UIViewController *)vc;

/// #16 — send one streak invite round now (same path the timer drives).
+ (void)sendStreaksNow;

/// #16 — (re)start or stop the automatic-streak timer from the live toggle.
+ (void)refreshStreakTimer;

@end

NS_ASSUME_NONNULL_END
