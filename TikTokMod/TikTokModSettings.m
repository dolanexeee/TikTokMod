//
//  TikTokModSettings.m
//  Dictionary-backed toggles: every lookup goes through boolForKey: /
//  setBool:forKey: against the NSUserDefaults suite. The hub reads
//  +allFeatures, so a new toggle is one registry line.
//
#import "TikTokModSettings.h"

static NSString * const kTikTokModSettingsSuite = @"com.tiktokmod.settings";
NSString * const TikTokModSettingsDidChangeNotification = @"TikTokModSettingsDidChangeNotification";

@interface TikTokModSettings ()
- (void)postChangeForKey:(NSString *)key;
- (NSString *)customBackgroundImageDirectory;
@end

/// Tag shared with TikTokModV1 overlays for the custom-background view.
static const NSInteger kTMCustomBackgroundTag = 7008;

@implementation TikTokModSettings

+ (instancetype)shared {
    static TikTokModSettings *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

+ (NSUserDefaults *)defaults {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kTikTokModSettingsSuite];
    if (!defaults) {
        NSLog(@"[TikTokMod] WARNING: could not open defaults suite %@, falling back to standardUserDefaults", kTikTokModSettingsSuite);
        defaults = [NSUserDefaults standardUserDefaults];
    }
    return defaults;
}

+ (NSArray<NSDictionary *> *)allFeatures {
    static NSArray<NSDictionary *> *features = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        features = @[
        @{@"num": @1, @"key": @"interfaceEditor", @"title": @"Interface editor — hide any element, one tap", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @2, @"key": @"playbackSpeed3x", @"title": @"Playback speed picker up to 3x (persists)", @"section": @"Player", @"unverified": @NO},
        @{@"num": @3, @"key": @"pictureInPicture", @"title": @"Picture-in-picture mode", @"section": @"Player", @"unverified": @NO},
        @{@"num": @4, @"key": @"readAllChats", @"title": @"\"Read all\" button when selecting chats", @"section": @"Chats & Comments", @"unverified": @NO},
        @{@"num": @5, @"key": @"comments9Images", @"title": @"Comments with up to 9 images", @"section": @"Chats & Comments", @"unverified": @YES, @"note": @"UNVERIFIED — server may still enforce"},
        @{@"num": @6, @"key": @"hashtagLimitRemoval", @"title": @"Removed hashtag limit when posting", @"section": @"Posting & Camera", @"unverified": @YES, @"note": @"UNVERIFIED — server may still enforce"},
        @{@"num": @7, @"key": @"cameraExtras", @"title": @"Camera extras: teleprompter, green screen, selfie flash, AI meme", @"section": @"Posting & Camera", @"unverified": @NO},
        @{@"num": @8, @"key": @"antiBurnInHideSystemBars", @"title": @"Anti-burn-in hides system bars (translucent, adjustable opacity)", @"section": @"Player", @"unverified": @NO},
        @{@"num": @9, @"key": @"redesignedModSettings", @"title": @"Redesigned mod settings (hub layout)", @"section": @"Mod", @"unverified": @NO},
        @{@"num": @10, @"key": @"downloadQualitySelection", @"title": @"Download quality selection (manual pick + skip-quality)", @"section": @"Downloads", @"unverified": @NO},
        @{@"num": @13, @"key": @"commentReposts", @"title": @"Comment reposts", @"section": @"Chats & Comments", @"unverified": @YES, @"note": @"UNVERIFIED — server may still enforce"},
        @{@"num": @14, @"key": @"bannersNewProfileLayout", @"title": @"Banners unlocked (new profile layout DEFERRED — no gate found)", @"section": @"Profile & Appearance", @"unverified": @NO, @"note": @"Banners only. The layout half has no evidence in either research pass — do not claim it."},
        @{@"num": @16, @"key": @"automaticStreaks", @"title": @"Automatic streaks — recipients + sticker, configurable timing", @"section": @"Chats & Comments", @"unverified": @NO},
        @{@"num": @17, @"key": @"sendPinLimitRemoval", @"title": @"Removed limits on sending videos + pinning chats", @"section": @"Chats & Comments", @"unverified": @YES, @"note": @"UNVERIFIED — server may still enforce"},
        @{@"num": @18, @"key": @"downloadWebSources", @"title": @"Downloads: web sources in source picker", @"section": @"Downloads", @"unverified": @NO},
        @{@"num": @20, @"key": @"appIconSelection", @"title": @"App icon selection (7 launcher styles)", @"section": @"Profile & Appearance", @"unverified": @NO, @"note": @"Icon sets must exist in the bundle at assembly time (TikTokMod/Icons/ + CFBundleAlternateIcons)."},
        @{@"num": @21, @"key": @"postDatesForYou", @"title": @"Post dates shown in the For You feed", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @22, @"key": @"contentFilters", @"title": @"Content filters — words, tags, likes, views", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @23, @"key": @"stickerDownloads", @"title": @"Sticker downloads", @"section": @"Downloads", @"unverified": @NO},
        @{@"num": @24, @"key": @"regionSwitching", @"title": @"Region switching (268 flags)", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @25, @"key": @"audioOnlyDownload", @"title": @"Audio-only download (to Music/TikTok)", @"section": @"Downloads", @"unverified": @NO},
        @{@"num": @26, @"key": @"repostCharacterLimitRemoval", @"title": @"Removed character limit on reposts", @"section": @"Posting & Camera", @"unverified": @YES, @"note": @"UNVERIFIED — server may still enforce"},
        @{@"num": @27, @"key": @"adBlocking", @"title": @"Ad blocking / clean feed", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @28, @"key": @"hideStory", @"title": @"Hide story", @"section": @"Player", @"unverified": @NO},
        @{@"num": @29, @"key": @"hideUIOpacity", @"title": @"Hide UI with opacity control", @"section": @"Player", @"unverified": @NO},
        @{@"num": @30, @"key": @"videoSliderSeekBar", @"title": @"Video slider / seek bar", @"section": @"Player", @"unverified": @NO},
        @{@"num": @31, @"key": @"autoScrollAutoPlayNext", @"title": @"Auto-scroll / auto-play \"autotease\" (+options/order)", @"section": @"Player", @"unverified": @NO},
        @{@"num": @32, @"key": @"customFonts", @"title": @"Custom fonts + system font", @"section": @"Profile & Appearance", @"unverified": @NO},
        @{@"num": @33, @"key": @"customColorsTheming", @"title": @"Custom colors / theming", @"section": @"Profile & Appearance", @"unverified": @NO},
        @{@"num": @34, @"key": @"hidePhotoMode", @"title": @"Hide photo mode", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @35, @"key": @"hideLiveEntries", @"title": @"Hide live entries + live badge", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @36, @"key": @"hideLikeViewCounts", @"title": @"Hide like / view counts", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @37, @"key": @"hideStreakBadges", @"title": @"Hide streak badges", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @38, @"key": @"drawingTool", @"title": @"Drawing tool \"risovalca\"", @"section": @"Player", @"unverified": @NO},
        @{@"num": @39, @"key": @"fakeStatusBarPreview", @"title": @"Fake status-bar preview (battery / signal / wifi)", @"section": @"Player", @"unverified": @NO},
        @{@"num": @40, @"key": @"startupScreen", @"title": @"Startup screen: check, download, FAQ, legal, stats", @"section": @"Mod", @"unverified": @NO},
        @{@"num": @41, @"key": @"modHubInAppUpdates", @"title": @"Mod hub / settings + in-app mod updates (OTA, incl. #15)", @"section": @"Mod", @"unverified": @NO},
        @{@"num": @42, @"key": @"telegramCommunityLink", @"title": @"Telegram community link", @"section": @"Mod", @"unverified": @NO},
        @{@"num": @43, @"key": @"hideSeriesRows", @"title": @"Hide Series rows — HIDE ONLY, never unlock", @"section": @"Feed & Discovery", @"unverified": @NO},
        @{@"num": @44, @"key": @"watermarkFreeDownloads", @"title": @"Watermark-free downloads", @"section": @"Downloads", @"unverified": @YES, @"note": @"NOT VERIFIED from code — do not claim unless proven"},
        @{@"num": @45, @"key": @"customBackground", @"title": @"Custom background — image or color (feed / profile / chat)", @"section": @"Profile & Appearance", @"unverified": @NO, @"note": @"Mustafa's own request (#45) — pick image or color in the hub"}
        ];
    });
    return features;
}

+ (NSArray<NSString *> *)allFeatureKeys {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSDictionary *f in [self allFeatures]) {
        [keys addObject:f[@"key"]];
    }
    return [keys copy];
}

+ (nullable NSDictionary *)featureForKey:(NSString *)key {
    for (NSDictionary *f in [self allFeatures]) {
        if ([f[@"key"] isEqualToString:key]) return f;
    }
    return nil;
}

+ (NSArray<NSString *> *)sections {
    NSMutableArray<NSString *> *sections = [NSMutableArray array];
    for (NSDictionary *f in [self allFeatures]) {
        NSString *section = f[@"section"];
        if (![sections containsObject:section]) [sections addObject:section];
    }
    return [sections copy];
}

- (BOOL)boolForKey:(NSString *)key {
    if (!key) return NO;
    return [[[self class] defaults] boolForKey:key];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    if (!key) return;
    NSUserDefaults *defaults = [[self class] defaults];
    [defaults setBool:value forKey:key];
    [defaults synchronize];
    [self postChangeForKey:key];
}

- (void)postChangeForKey:(NSString *)key {
    if (!key) return;
    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:TikTokModSettingsDidChangeNotification
                          object:self userInfo:@{@"key": key}];
    };
    if ([NSThread isMainThread]) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

- (float)floatForKey:(NSString *)key defaultValue:(float)defaultValue {
    if (!key) return defaultValue;
    NSUserDefaults *defaults = [[self class] defaults];
    if (![defaults objectForKey:key]) return defaultValue;
    return [defaults floatForKey:key];
}

- (void)setFloat:(float)value forKey:(NSString *)key {
    if (!key) return;
    NSUserDefaults *defaults = [[self class] defaults];
    [defaults setFloat:value forKey:key];
    [defaults synchronize];
    [self postChangeForKey:key];
}

- (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    if (!key) return defaultValue;
    NSUserDefaults *defaults = [[self class] defaults];
    if (![defaults objectForKey:key]) return defaultValue;
    return [defaults integerForKey:key];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    if (!key) return;
    NSUserDefaults *defaults = [[self class] defaults];
    [defaults setInteger:value forKey:key];
    [defaults synchronize];
    [self postChangeForKey:key];
}

- (nullable NSString *)stringForKey:(NSString *)key {
    if (!key) return nil;
    return [[[self class] defaults] stringForKey:key];
}

- (void)setString:(nullable NSString *)value forKey:(NSString *)key {
    if (!key) return;
    NSUserDefaults *defaults = [[self class] defaults];
    if (value) [defaults setObject:value forKey:key];
    else [defaults removeObjectForKey:key];
    [defaults synchronize];
    [self postChangeForKey:key];
}

- (nullable NSArray<NSString *> *)arrayForKey:(NSString *)key {
    if (!key) return nil;
    return [[[self class] defaults] arrayForKey:key];
}

- (void)setArray:(nullable NSArray<NSString *> *)value forKey:(NSString *)key {
    if (!key) return;
    NSUserDefaults *defaults = [[self class] defaults];
    if (value) [defaults setObject:value forKey:key];
    else [defaults removeObjectForKey:key];
    [defaults synchronize];
    [self postChangeForKey:key];
}

- (float)playbackRateValue { return [self floatForKey:@"playbackRateValue" defaultValue:1.0f]; }
- (void)setPlaybackRateValue:(float)value { [self setFloat:value forKey:@"playbackRateValue"]; }
- (float)feedOverlayOpacity { return [self floatForKey:@"feedOverlayOpacity" defaultValue:0.12f]; }
- (void)setFeedOverlayOpacity:(float)value { [self setFloat:value forKey:@"feedOverlayOpacity"]; }
- (float)hideUIOpacityValue { return [self floatForKey:@"hideUIOpacityValue" defaultValue:0.0f]; }
- (void)setHideUIOpacityValue:(float)value { [self setFloat:value forKey:@"hideUIOpacityValue"]; }
- (NSInteger)fakeStatusBarSignalBars { return [self integerForKey:@"fakeStatusBarSignalBars" defaultValue:4]; }
- (void)setFakeStatusBarSignalBars:(NSInteger)value { [self setInteger:value forKey:@"fakeStatusBarSignalBars"]; }
- (BOOL)fakeStatusBarWifiEnabled {
    NSUserDefaults *d = [[self class] defaults];
    if (![d objectForKey:@"fakeStatusBarWifiEnabled"]) return YES;
    return [d boolForKey:@"fakeStatusBarWifiEnabled"];
}
- (void)setFakeStatusBarWifiEnabled:(BOOL)value { [self setBool:value forKey:@"fakeStatusBarWifiEnabled"]; }
- (nullable NSString *)telegramCommunityURL { return [self stringForKey:@"telegramCommunityURL"]; }
- (void)setTelegramCommunityURL:(nullable NSString *)value { [self setString:value forKey:@"telegramCommunityURL"]; }
- (nullable NSString *)selectedAlternateIconName { return [self stringForKey:@"selectedAlternateIconName"]; }
- (void)setSelectedAlternateIconName:(nullable NSString *)value { [self setString:value forKey:@"selectedAlternateIconName"]; }
- (nullable NSArray<NSString *> *)hiddenElementClasses { return [self arrayForKey:@"hiddenElementClasses"]; }
- (void)setHiddenElementClasses:(nullable NSArray<NSString *> *)value { [self setArray:value forKey:@"hiddenElementClasses"]; }
- (nullable NSString *)modButtonCenter { return [self stringForKey:@"modButtonCenter"]; }
- (void)setModButtonCenter:(nullable NSString *)value { [self setString:value forKey:@"modButtonCenter"]; }

- (BOOL)interfaceEditor { return [self boolForKey:@"interfaceEditor"]; }
- (void)setInterfaceEditor:(BOOL)value { [self setBool:value forKey:@"interfaceEditor"]; }
- (BOOL)playbackSpeed3x { return [self boolForKey:@"playbackSpeed3x"]; }
- (void)setPlaybackSpeed3x:(BOOL)value { [self setBool:value forKey:@"playbackSpeed3x"]; }
- (BOOL)pictureInPicture { return [self boolForKey:@"pictureInPicture"]; }
- (void)setPictureInPicture:(BOOL)value { [self setBool:value forKey:@"pictureInPicture"]; }
- (BOOL)readAllChats { return [self boolForKey:@"readAllChats"]; }
- (void)setReadAllChats:(BOOL)value { [self setBool:value forKey:@"readAllChats"]; }
- (BOOL)comments9Images { return [self boolForKey:@"comments9Images"]; }
- (void)setComments9Images:(BOOL)value { [self setBool:value forKey:@"comments9Images"]; }
- (BOOL)hashtagLimitRemoval { return [self boolForKey:@"hashtagLimitRemoval"]; }
- (void)setHashtagLimitRemoval:(BOOL)value { [self setBool:value forKey:@"hashtagLimitRemoval"]; }
- (BOOL)cameraExtras { return [self boolForKey:@"cameraExtras"]; }
- (void)setCameraExtras:(BOOL)value { [self setBool:value forKey:@"cameraExtras"]; }
- (BOOL)antiBurnInHideSystemBars { return [self boolForKey:@"antiBurnInHideSystemBars"]; }
- (void)setAntiBurnInHideSystemBars:(BOOL)value { [self setBool:value forKey:@"antiBurnInHideSystemBars"]; }
- (BOOL)redesignedModSettings { return [self boolForKey:@"redesignedModSettings"]; }
- (void)setRedesignedModSettings:(BOOL)value { [self setBool:value forKey:@"redesignedModSettings"]; }
- (BOOL)downloadQualitySelection { return [self boolForKey:@"downloadQualitySelection"]; }
- (void)setDownloadQualitySelection:(BOOL)value { [self setBool:value forKey:@"downloadQualitySelection"]; }
- (BOOL)commentReposts { return [self boolForKey:@"commentReposts"]; }
- (void)setCommentReposts:(BOOL)value { [self setBool:value forKey:@"commentReposts"]; }
- (BOOL)bannersNewProfileLayout { return [self boolForKey:@"bannersNewProfileLayout"]; }
- (void)setBannersNewProfileLayout:(BOOL)value { [self setBool:value forKey:@"bannersNewProfileLayout"]; }
- (BOOL)automaticStreaks { return [self boolForKey:@"automaticStreaks"]; }
- (void)setAutomaticStreaks:(BOOL)value { [self setBool:value forKey:@"automaticStreaks"]; }
- (BOOL)sendPinLimitRemoval { return [self boolForKey:@"sendPinLimitRemoval"]; }
- (void)setSendPinLimitRemoval:(BOOL)value { [self setBool:value forKey:@"sendPinLimitRemoval"]; }
- (BOOL)downloadWebSources { return [self boolForKey:@"downloadWebSources"]; }
- (void)setDownloadWebSources:(BOOL)value { [self setBool:value forKey:@"downloadWebSources"]; }
- (BOOL)appIconSelection { return [self boolForKey:@"appIconSelection"]; }
- (void)setAppIconSelection:(BOOL)value { [self setBool:value forKey:@"appIconSelection"]; }
- (BOOL)postDatesForYou { return [self boolForKey:@"postDatesForYou"]; }
- (void)setPostDatesForYou:(BOOL)value { [self setBool:value forKey:@"postDatesForYou"]; }
- (BOOL)contentFilters { return [self boolForKey:@"contentFilters"]; }
- (void)setContentFilters:(BOOL)value { [self setBool:value forKey:@"contentFilters"]; }
- (BOOL)stickerDownloads { return [self boolForKey:@"stickerDownloads"]; }
- (void)setStickerDownloads:(BOOL)value { [self setBool:value forKey:@"stickerDownloads"]; }
- (BOOL)regionSwitching { return [self boolForKey:@"regionSwitching"]; }
- (void)setRegionSwitching:(BOOL)value { [self setBool:value forKey:@"regionSwitching"]; }
- (BOOL)audioOnlyDownload { return [self boolForKey:@"audioOnlyDownload"]; }
- (void)setAudioOnlyDownload:(BOOL)value { [self setBool:value forKey:@"audioOnlyDownload"]; }
- (BOOL)repostCharacterLimitRemoval { return [self boolForKey:@"repostCharacterLimitRemoval"]; }
- (void)setRepostCharacterLimitRemoval:(BOOL)value { [self setBool:value forKey:@"repostCharacterLimitRemoval"]; }
- (BOOL)adBlocking { return [self boolForKey:@"adBlocking"]; }
- (void)setAdBlocking:(BOOL)value { [self setBool:value forKey:@"adBlocking"]; }
- (BOOL)hideStory { return [self boolForKey:@"hideStory"]; }
- (void)setHideStory:(BOOL)value { [self setBool:value forKey:@"hideStory"]; }
- (BOOL)hideUIOpacity { return [self boolForKey:@"hideUIOpacity"]; }
- (void)setHideUIOpacity:(BOOL)value { [self setBool:value forKey:@"hideUIOpacity"]; }
- (BOOL)videoSliderSeekBar { return [self boolForKey:@"videoSliderSeekBar"]; }
- (void)setVideoSliderSeekBar:(BOOL)value { [self setBool:value forKey:@"videoSliderSeekBar"]; }
- (BOOL)autoScrollAutoPlayNext { return [self boolForKey:@"autoScrollAutoPlayNext"]; }
- (void)setAutoScrollAutoPlayNext:(BOOL)value { [self setBool:value forKey:@"autoScrollAutoPlayNext"]; }
- (BOOL)customFonts { return [self boolForKey:@"customFonts"]; }
- (void)setCustomFonts:(BOOL)value { [self setBool:value forKey:@"customFonts"]; }
- (BOOL)customColorsTheming { return [self boolForKey:@"customColorsTheming"]; }
- (void)setCustomColorsTheming:(BOOL)value { [self setBool:value forKey:@"customColorsTheming"]; }
- (BOOL)hidePhotoMode { return [self boolForKey:@"hidePhotoMode"]; }
- (void)setHidePhotoMode:(BOOL)value { [self setBool:value forKey:@"hidePhotoMode"]; }
- (BOOL)hideLiveEntries { return [self boolForKey:@"hideLiveEntries"]; }
- (void)setHideLiveEntries:(BOOL)value { [self setBool:value forKey:@"hideLiveEntries"]; }
- (BOOL)hideLikeViewCounts { return [self boolForKey:@"hideLikeViewCounts"]; }
- (void)setHideLikeViewCounts:(BOOL)value { [self setBool:value forKey:@"hideLikeViewCounts"]; }
- (BOOL)hideStreakBadges { return [self boolForKey:@"hideStreakBadges"]; }
- (void)setHideStreakBadges:(BOOL)value { [self setBool:value forKey:@"hideStreakBadges"]; }
- (BOOL)drawingTool { return [self boolForKey:@"drawingTool"]; }
- (void)setDrawingTool:(BOOL)value { [self setBool:value forKey:@"drawingTool"]; }
- (BOOL)fakeStatusBarPreview { return [self boolForKey:@"fakeStatusBarPreview"]; }
- (void)setFakeStatusBarPreview:(BOOL)value { [self setBool:value forKey:@"fakeStatusBarPreview"]; }
- (BOOL)startupScreen { return [self boolForKey:@"startupScreen"]; }
- (void)setStartupScreen:(BOOL)value { [self setBool:value forKey:@"startupScreen"]; }
- (BOOL)modHubInAppUpdates { return [self boolForKey:@"modHubInAppUpdates"]; }
- (void)setModHubInAppUpdates:(BOOL)value { [self setBool:value forKey:@"modHubInAppUpdates"]; }
- (BOOL)telegramCommunityLink { return [self boolForKey:@"telegramCommunityLink"]; }
- (void)setTelegramCommunityLink:(BOOL)value { [self setBool:value forKey:@"telegramCommunityLink"]; }
- (BOOL)hideSeriesRows { return [self boolForKey:@"hideSeriesRows"]; }
- (void)setHideSeriesRows:(BOOL)value { [self setBool:value forKey:@"hideSeriesRows"]; }
- (BOOL)watermarkFreeDownloads { return [self boolForKey:@"watermarkFreeDownloads"]; }
- (void)setWatermarkFreeDownloads:(BOOL)value { [self setBool:value forKey:@"watermarkFreeDownloads"]; }
- (BOOL)customBackground { return [self boolForKey:@"customBackground"]; }
- (void)setCustomBackground:(BOOL)value { [self setBool:value forKey:@"customBackground"]; }

#pragma mark - #45 Custom Background

- (NSString *)customBackgroundMode {
    NSString *mode = [[[self class] defaults] stringForKey:@"customBackgroundMode"];
    if (!mode || (![mode isEqualToString:@"image"] && ![mode isEqualToString:@"color"])) return @"none";
    return mode;
}

- (void)setCustomBackgroundMode:(NSString *)mode {
    if (!mode) mode = @"none";
    NSUserDefaults *defaults = [[self class] defaults];
    [defaults setObject:mode forKey:@"customBackgroundMode"];
    [defaults synchronize];
}

- (NSString *)customBackgroundColorHex {
    return [[[self class] defaults] stringForKey:@"customBackgroundColorHex"];
}

- (void)setCustomBackgroundColorHex:(NSString *)hex {
    NSUserDefaults *defaults = [[self class] defaults];
    if (hex) [defaults setObject:hex forKey:@"customBackgroundColorHex"];
    else [defaults removeObjectForKey:@"customBackgroundColorHex"];
    [defaults synchronize];
}

- (NSString *)customBackgroundImagePath {
    return [[[self class] defaults] stringForKey:@"customBackgroundImagePath"];
}

- (void)setCustomBackgroundImagePath:(NSString *)path {
    NSUserDefaults *defaults = [[self class] defaults];
    if (path) [defaults setObject:path forKey:@"customBackgroundImagePath"];
    else [defaults removeObjectForKey:@"customBackgroundImagePath"];
    [defaults synchronize];
}

- (NSString *)customBackgroundImageDirectory {
    NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.firstObject ?: NSTemporaryDirectory();
    return [base stringByAppendingPathComponent:@"TikTokMod"];
}

- (nullable UIImage *)customBackgroundImage {
    NSString *path = self.customBackgroundImagePath;
    if (!path) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

- (BOOL)saveCustomBackgroundImage:(UIImage *)image {
    if (!image) {
        NSLog(@"[TikTokMod] saveCustomBackgroundImage: nil image, skipping (fail-soft)");
        return NO;
    }
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.85);
    if (!jpeg) {
        NSLog(@"[TikTokMod] saveCustomBackgroundImage: could not encode JPEG");
        return NO;
    }
    NSString *dir = [self customBackgroundImageDirectory];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSLog(@"[TikTokMod] saveCustomBackgroundImage: mkdir failed: %@", error);
        return NO;
    }
    NSString *path = [dir stringByAppendingPathComponent:@"custom-background.jpg"];
    if (![jpeg writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[TikTokMod] saveCustomBackgroundImage: write failed: %@", error);
        return NO;
    }
    self.customBackgroundImagePath = path;
    self.customBackgroundMode = @"image";
    NSLog(@"[TikTokMod] custom background image saved: %@", path);
    return YES;
}

- (void)clearCustomBackgroundImage {
    NSString *path = self.customBackgroundImagePath;
    if (path) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    self.customBackgroundImagePath = nil;
    self.customBackgroundMode = @"none";
    NSLog(@"[TikTokMod] custom background cleared");
}

- (nullable UIColor *)customBackgroundColor {
    NSString *hex = self.customBackgroundColorHex;
    if (!hex) return nil;
    NSString *clean = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length != 6) {
        NSLog(@"[TikTokMod] customBackgroundColor: bad hex %@", hex);
        return nil;
    }
    unsigned rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

- (void)applyCustomBackgroundToView:(UIView *)view {
    // Real implementation (DYLIB-DESIGN.md §2.6): bottom subview only.
    // The video layer stays topmost and opaque; a dark scrim behind captions
    // is added per-cell by TikTokModV1. Never translucent video.
    if (!view) return;
    UIView *old = [view viewWithTag:kTMCustomBackgroundTag];
    if (old) [old removeFromSuperview];
    if (!self.customBackground) return;
    NSString *mode = self.customBackgroundMode;
    if ([mode isEqualToString:@"none"]) return;
    UIView *bg = nil;
    if ([mode isEqualToString:@"image"]) {
        UIImage *image = self.customBackgroundImage;
        if (!image) {
            NSLog(@"[TikTokMod] applyCustomBackgroundToView: image mode but no image stored (fail-soft)");
            return;
        }
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        bg = imageView;
    } else if ([mode isEqualToString:@"color"]) {
        UIColor *color = self.customBackgroundColor;
        if (!color) {
            NSLog(@"[TikTokMod] applyCustomBackgroundToView: color mode but bad hex %@ (fail-soft)",
                  self.customBackgroundColorHex ?: @"-");
            return;
        }
        bg = [[UIView alloc] init];
        bg.backgroundColor = color;
    } else {
        return;
    }
    bg.tag = kTMCustomBackgroundTag;
    bg.frame = view.bounds;
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view insertSubview:bg atIndex:0];
    NSLog(@"[TikTokMod] #45 custom background applied (mode=%@) as bottom subview", mode);
}

@end
