//
//  TikTokModSettings.h
//  TikTokMod — toggle slot for every feature in the 44-feature list
//  (TIKTOK-YOU-ANALYSIS.md, "COMPLETE FEATURE LIST — TikTok You 5.0").
//
//  Toggle count: 42. NOT toggles:
//    #11 black-stories bugfix (Android-mod bugfix, not a portable feature),
//    #12 hiding-rules maintenance note (re-verify hooks per TikTok update).
//  #15 OTA updates merges into #41 (mod hub + in-app updates).
//  V2 added #19 (offline-video limit) — the registry line the design calls for.
//
//  EXTENSIBILITY: toggles are dictionary-backed, keyed by feature ID
//  (see +allFeatures in TikTokModSettings.m). Adding a toggle later is
//  ONE LINE in that registry — the hub row, persistence and lookup follow
//  automatically. The BOOL properties below are convenience wrappers over
//  the same dictionary-backed store. Persisted in NSUserDefaults suite
//  "com.tiktokmod.settings". Skeleton only: toggles are stubs, no real
//  TikTok hooks yet.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted (main thread) whenever a toggle or value key changes.
/// userInfo: @{@"key": <changed key>}. Overlays listen and re-apply.
extern NSString * const TikTokModSettingsDidChangeNotification;

@interface TikTokModSettings : NSObject

+ (instancetype)shared;
+ (NSUserDefaults *)defaults;

/// The full feature registry. Each entry: num (44-list number), key
/// (feature ID), title, section (hub grouping), unverified (YES when the
/// feature only lifts a CLIENT limit the server may still enforce),
/// note (optional caution string shown in the hub).
+ (NSArray<NSDictionary *> *)allFeatures;
+ (NSArray<NSString *> *)allFeatureKeys;
+ (nullable NSDictionary *)featureForKey:(NSString *)key;
+ (NSArray<NSString *> *)sections;

- (BOOL)boolForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;

// Generic value keys (V1, DYLIB-DESIGN.md §2.3). All post the change notification.
- (float)floatForKey:(NSString *)key defaultValue:(float)defaultValue;
- (void)setFloat:(float)value forKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (nullable NSString *)stringForKey:(NSString *)key;
- (void)setString:(nullable NSString *)value forKey:(NSString *)key;
- (nullable NSArray<NSString *> *)arrayForKey:(NSString *)key;
- (void)setArray:(nullable NSArray<NSString *> *)value forKey:(NSString *)key;

/// #2 — last chosen playback rate (default 1.0).
@property (nonatomic, assign) float playbackRateValue;
/// #8 — burn-in dim overlay alpha (default 0.12).
@property (nonatomic, assign) float feedOverlayOpacity;
/// #29 — hide-UI opacity applied to the interaction elements (default 0.0 = hidden).
@property (nonatomic, assign) float hideUIOpacityValue;
/// #39 — fake status bar: user-set signal bars 0-4 (default 4). No live API exists.
@property (nonatomic, assign) NSInteger fakeStatusBarSignalBars;
/// #39 — fake status bar: show the Wi-Fi glyph (default YES). User-set, not live.
@property (nonatomic, assign) BOOL fakeStatusBarWifiEnabled;
/// #42 — Telegram community URL (hub config; no concrete URL exists in the research).
@property (nonatomic, copy, nullable) NSString *telegramCommunityURL;
/// #20 — selected alternate icon name (nil = stock Default).
@property (nonatomic, copy, nullable) NSString *selectedAlternateIconName;
/// #1 — element class names hidden by the interface editor.
@property (nonatomic, copy, nullable) NSArray<NSString *> *hiddenElementClasses;
/// #9 — persisted Mod-button position ("x,y") after the user drags it.
@property (nonatomic, copy, nullable) NSString *modButtonCenter;

// --- V2 value keys (DYLIB-DESIGN.md §2.3) ---
/// #16 — conversation IDs that receive automatic streak invites (user-picked only).
@property (nonatomic, copy, nullable) NSArray<NSString *> *streakRecipients;
/// #16 — sticker ID sent with the streak invite (stored; the verified tracker
/// selector has no sticker slot — see TikTokModV2.m for the honest limit).
@property (nonatomic, copy, nullable) NSString *streakStickerID;
/// #16 — minutes between automatic streak sends (default 60).
@property (nonatomic, assign) NSInteger streakIntervalMinutes;
/// #22 — words/tags that hide a feed item (caption + hashtags match).
@property (nonatomic, copy, nullable) NSArray<NSString *> *filterWords;
@property (nonatomic, copy, nullable) NSArray<NSString *> *filterTags;
/// #22 — minimum likes / views a feed item must have to stay (default 0 = no floor).
@property (nonatomic, assign) NSInteger filterMinLikes;
@property (nonatomic, assign) NSInteger filterMinViews;
/// #19 — offline fetch count (default 500). No iOS twin of Android's "2,000" exists.
@property (nonatomic, assign) NSInteger offlineVideoCount;
/// #31 — seconds to wait after a video ends before auto-scrolling (default 1).
@property (nonatomic, assign) float autoScrollDelaySeconds;
/// #31 — YES (default): advance only after a video fully plays to the end.
@property (nonatomic, assign) BOOL autoScrollOnlyAfterFullWatch;
/// #32 — PostScript font name, or @"System" (default) for the system font.
@property (nonatomic, copy, nullable) NSString *customFontName;
/// #33 — feed-chrome theme colors as hex (nil = stock). Per-surface only.
@property (nonatomic, copy, nullable) NSString *themeAccentColorHex;
@property (nonatomic, copy, nullable) NSString *themeBackgroundColorHex;
/// #7 — experimental colored-selfie-flash sub-toggle (default OFF; PARTIAL).
@property (nonatomic, assign) BOOL coloredSelfieFlashEnabled;
/// #7 — flash color hex (default #FFFFFF).
@property (nonatomic, copy, nullable) NSString *frontFlashColorHex;

// --- #45 Custom Background (Mustafa's own request, not from TikTok You) ---
// Toggle itself is the `customBackground` BOOL property (registry #45).
// Mode: @"image" | @"color" | @"none". Image is stored as a JPEG file under
// the app's Documents/TikTokMod/ (path kept in the settings suite);
// color is stored as a hex string (e.g. @"#1A1A2E").
@property (nonatomic, copy, nullable) NSString *customBackgroundMode;
@property (nonatomic, copy, nullable) NSString *customBackgroundColorHex;
@property (nonatomic, copy, nullable) NSString *customBackgroundImagePath;
- (nullable UIImage *)customBackgroundImage;
- (BOOL)saveCustomBackgroundImage:(UIImage *)image;
- (void)clearCustomBackgroundImage;
- (nullable UIColor *)customBackgroundColor;
/// Inserts the stored background (image or color) as the BOTTOM subview of
/// `view` — behind the video layer, which stays topmost and opaque (§2.6).
/// Removing it when the toggle is OFF / mode is none. Fail-soft: nil view,
/// missing image or bad hex = log and do nothing.
- (void)applyCustomBackgroundToView:(UIView *)view;

@property (nonatomic, assign) BOOL interfaceEditor;  // #1 Interface editor — hide any element, one tap
@property (nonatomic, assign) BOOL playbackSpeed3x;  // #2 Playback speed picker up to 3x (persists)
@property (nonatomic, assign) BOOL pictureInPicture;  // #3 Picture-in-picture mode
@property (nonatomic, assign) BOOL readAllChats;  // #4 "Read all" button when selecting chats
@property (nonatomic, assign) BOOL comments9Images;  // #5 Comments with up to 9 images
@property (nonatomic, assign) BOOL hashtagLimitRemoval;  // #6 Removed hashtag limit when posting
@property (nonatomic, assign) BOOL cameraExtras;  // #7 Camera extras: teleprompter, green screen, selfie flash, AI meme
@property (nonatomic, assign) BOOL antiBurnInHideSystemBars;  // #8 Anti-burn-in hides system bars (translucent, adjustable opacity)
@property (nonatomic, assign) BOOL redesignedModSettings;  // #9 Redesigned mod settings (hub layout)
@property (nonatomic, assign) BOOL downloadQualitySelection;  // #10 Download quality selection (manual pick + skip-quality)
@property (nonatomic, assign) BOOL commentReposts;  // #13 Comment reposts
@property (nonatomic, assign) BOOL bannersNewProfileLayout;  // #14 Banners + new profile layout unlocked
@property (nonatomic, assign) BOOL automaticStreaks;  // #16 Automatic streaks — recipients + sticker, configurable timing
@property (nonatomic, assign) BOOL sendPinLimitRemoval;  // #17 Removed limits on sending videos + pinning chats
@property (nonatomic, assign) BOOL downloadWebSources;  // #18 Downloads: web sources in source picker
@property (nonatomic, assign) BOOL offlineVideoLimit;  // #19 Offline video limit (V2: tunes the offline fetch count)
@property (nonatomic, assign) BOOL appIconSelection;  // #20 App icon selection (7 launcher styles)
@property (nonatomic, assign) BOOL postDatesForYou;  // #21 Post dates shown in the For You feed
@property (nonatomic, assign) BOOL contentFilters;  // #22 Content filters — words, tags, likes, views
@property (nonatomic, assign) BOOL stickerDownloads;  // #23 Sticker downloads
@property (nonatomic, assign) BOOL regionSwitching;  // #24 Region switching (268 flags)
@property (nonatomic, assign) BOOL audioOnlyDownload;  // #25 Audio-only download (to Music/TikTok)
@property (nonatomic, assign) BOOL repostCharacterLimitRemoval;  // #26 Removed character limit on reposts
@property (nonatomic, assign) BOOL adBlocking;  // #27 Ad blocking / clean feed
@property (nonatomic, assign) BOOL hideStory;  // #28 Hide story
@property (nonatomic, assign) BOOL hideUIOpacity;  // #29 Hide UI with opacity control
@property (nonatomic, assign) BOOL videoSliderSeekBar;  // #30 Video slider / seek bar
@property (nonatomic, assign) BOOL autoScrollAutoPlayNext;  // #31 Auto-scroll / auto-play "autotease" (+options/order)
@property (nonatomic, assign) BOOL customFonts;  // #32 Custom fonts + system font
@property (nonatomic, assign) BOOL customColorsTheming;  // #33 Custom colors / theming
@property (nonatomic, assign) BOOL hidePhotoMode;  // #34 Hide photo mode
@property (nonatomic, assign) BOOL hideLiveEntries;  // #35 Hide live entries + live badge
@property (nonatomic, assign) BOOL hideLikeViewCounts;  // #36 Hide like / view counts
@property (nonatomic, assign) BOOL hideStreakBadges;  // #37 Hide streak badges
@property (nonatomic, assign) BOOL drawingTool;  // #38 Drawing tool "risovalca"
@property (nonatomic, assign) BOOL fakeStatusBarPreview;  // #39 Fake status-bar preview (battery / signal / wifi)
@property (nonatomic, assign) BOOL startupScreen;  // #40 Startup screen: check, download, FAQ, legal, stats
@property (nonatomic, assign) BOOL modHubInAppUpdates;  // #41 Mod hub / settings + in-app mod updates (OTA, incl. #15)
@property (nonatomic, assign) BOOL telegramCommunityLink;  // #42 Telegram community link
@property (nonatomic, assign) BOOL hideSeriesRows;  // #43 Hide Series rows — HIDE ONLY, never unlock
@property (nonatomic, assign) BOOL watermarkFreeDownloads;  // #44 Watermark-free downloads
@property (nonatomic, assign) BOOL customBackground;  // #45 Custom background — image or color (feed / profile / chat)

@end

NS_ASSUME_NONNULL_END
