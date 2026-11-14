//
//  TikTokModHard.h
//  TikTokMod HARD phase (DYLIB-DESIGN.md §4): 5 features — #10 download
//  quality, #18 web sources, #24 region (PARTIAL), #25 audio-only download,
//  #27 ad blocking — all gated on the §2.5 pinning bypass.
//  #44 watermark-free stays DEFER — NOT implemented here.
//
//  Same binding rules as V1/V2: every class/selector below comes from
//  RESEARCH-LOG.md / INJECTION-ANALYSIS.md / class-map.txt. Nothing invented.
//  Runtime IMP injection only for TikTok classes (alias prefix "tm3_orig_") —
//  no categories on TikTok classes, no link-time refs to TikTok classes.
//  Missing target = no-op + NSLog, never a crash. Every hook reads its live
//  toggle per call and falls through to stock behaviour when OFF.
//
//  HONEST LIMITS (read before claiming anything works):
//  • No iOS device exists on the build VM, so NOTHING here is
//    runtime-verified: compile + artifact level only.
//  • The pinning bypass covers ONLY the three ObjC surfaces in §2.5
//    (AFSecurityPolicy, NSURLSession delegate challenges, Alamofire
//    ServerTrustManager). Pinning may ALSO live in TTNet's native
//    libvcn/boringssl layer — that layer is NOT hooked here. Only a runtime
//    traffic capture showing Aweme API JSON proves the bypass. Until then
//    every HARD download feature is UNVERIFIED-RUNTIME.
//  • #24 is PARTIAL by design: the feed region is largely server-side
//    (IP, SIM, account). Changing what the client reports does not guarantee
//    what the server serves. Never promise a region change.
//  • #27's ad-marker accessor is unverified (isAd/adInfo are string-level
//    names from R2, not confirmed selectors). The filter drops an item ONLY
//    when an isAd/is_ad key reads YES as a BOOL; anything else is logged,
//    never dropped. A wrong filter must never blank the feed.
//  • #18's webSource evidence is weak (4 hits in R2). The picker is
//    dylib-built; a pasted direct URL needs no capture and works even if the
//    bypass is unproven.
//  Test on a secondary account only.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TikTokModHard : NSObject

/// Install every HARD hook site that resolves. Missed sites are retried from
/// AWEFeedRootViewController viewDidLoad via +retryDeferredInstalls (called
/// from TikTokModV1's feed-root appearance path, same as V2).
+ (void)installHardHooks;

/// Re-attempt HARD hook sites whose class was not yet loaded at launch.
+ (void)retryDeferredInstalls;

/// One-line pinning-bypass status for the hub row, e.g.
/// @"AFSecurityPolicy: hooked • NSURLSession delegate: hooked • Alamofire: absent".
+ (NSString *)pinningBypassStatus;

/// #27 — conservative ad predicate used by V1's filteredDataSource hook.
/// Returns YES only when an isAd/is_ad key reads YES as a BOOL. Toggle-gated:
/// returns NO whenever adBlocking is OFF. Anything unverified is logged,
/// never dropped.
+ (BOOL)shouldDropAdItem:(id)item;

/// #27 — hide ad UI views (AWEAdFeed* / AdLearnMore / AdDrawer) inside a feed
/// cell view. Called from V1's applyCellOverlays. Toggle-gated.
+ (void)hideAdViewsInView:(UIView *)cellView;

/// #10 — quality variants (playAddr keys) found on the CURRENT video's aweme
/// model, as @{variantKey: URL string}. Empty when no model/URL is reachable.
/// Variant keys come from INJECTION-ANALYSIS.md (playAddr, playAddr265,
/// playAddrH264, playAddrLowbr, playAddrBytevc1, playAddr3DFallback,
/// downloadUrl). #44's download_no_watermark_addr is deliberately NOT read.
+ (NSDictionary<NSString *, NSString *> *)currentVideoQualityURLs;

/// #10 — URLs last seen passed to AWEMediaDownloadAwemeStage
/// downloadVideoWithURLList: (stock download path). Used as the picker
/// fallback when the aweme model yields nothing.
+ (NSArray *)lastCapturedDownloadURLs;

/// #10 — download the current video at the chosen quality. If qualityChoice
/// is @"auto" (or nil) a picker sheet is shown; otherwise the stored variant
/// is used silently ("skip quality"). Presents from `vc`. No-op + alert when
/// no URL can be found.
+ (void)downloadCurrentVideoFromViewController:(UIViewController *)vc;

/// #18 — source picker: paste a URL (or reuse the last stock source URL) and
/// download its bytes to Documents/TikTokMod/Downloads/. A pasted direct URL
/// needs no capture and works even if the pinning bypass is unproven.
+ (void)downloadFromWebSourceFromViewController:(UIViewController *)vc;

/// #24 — region picker: enter an ISO country code (or restore stock region).
/// Applies the spoof immediately; PARTIAL by design (see the header).
+ (void)pickRegionFromViewController:(UIViewController *)vc;

/// #24 — (re)apply the stored regionCode: locale/carrier spoof + region
/// manager call + feed refresh attempt. Called on toggle/value change.
+ (void)applyStoredRegion;

/// #25 — download the CURRENT video's audio (music play URL from the aweme's
/// music model) to Documents/TikTokMod/Music/. No-op + alert when no audio
/// URL can be found.
+ (void)downloadCurrentAudioFromViewController:(UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
