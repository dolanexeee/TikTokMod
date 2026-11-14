//
//  TikTokModSettings.h
//  TikTokMod — toggle slot for every feature in the 44-feature list
//  (TIKTOK-YOU-ANALYSIS.md, "COMPLETE FEATURE LIST — TikTok You 5.0").
//
//  Toggle count: 40. NOT toggles:
//    #11 black-stories bugfix (Android-mod bugfix, not a portable feature),
//    #12 hiding-rules maintenance note (re-verify hooks per TikTok update),
//    #19 offline-video limit (Android-only cache tuning).
//  #15 OTA updates merges into #41 (mod hub + in-app updates).
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
/// Stub for now: logs the stored choice. The real overlay background view
/// (behind the feed, must not break video rendering or text readability)
/// lands with the research hooks — do NOT call this as if it worked yet.
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
