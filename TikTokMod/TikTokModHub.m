//
//  TikTokModHub.m
//  V1 hub redesign (#9): sections + search + per-feature notes (UNVERIFIED
//  rows stay marked) + control rows for the features that need more than a
//  toggle: playback speed (#2), hide-UI / burn-in opacity (#29/#8), fake
//  status bar (#39), app icons (#20), OTA updates (#41/#15), Telegram (#42),
//  startup screen (#40), unhide-all (#1). Rows still come from
//  [TikTokModSettings allFeatures] — no hardcoded feature list here.
//  Series is hide-only, never an unlock.
//
#import "TikTokModHub.h"
#import "TikTokModSettings.h"
#import "TikTokModV1.h"
#import "TikTokModV2.h"
#import "TikTokModHard.h"

@interface TikTokModHub () <UIImagePickerControllerDelegate, UINavigationControllerDelegate,
                            UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSString *> *sections;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSDictionary *> *> *featuresBySection;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredFeatures;
@end

// Extra picker row appended to the "Profile & Appearance" section (#45).
static NSString * const kCustomBackgroundPickerSection = @"Profile & Appearance";

@implementation TikTokModHub

+ (BOOL)presentHub {
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = [self presentHub]; });
        return result;
    }
    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            window = ((UIWindowScene *)scene).keyWindow;
            if (window) break;
        }
    }
    if (!window) {
        window = [UIApplication sharedApplication].keyWindow;
    }
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    if (!root) {
        NSLog(@"[TikTokMod] presentHub: no root view controller available, hub not presented");
        return NO;
    }
    TikTokModHub *hub = [[TikTokModHub alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:hub];
    [root presentViewController:nav animated:YES completion:nil];
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TikTokMod";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(doneTapped)];
    self.sections = [TikTokModSettings sections];
    NSMutableDictionary *grouped = [NSMutableDictionary dictionary];
    for (NSDictionary *f in [TikTokModSettings allFeatures]) {
        NSString *section = f[@"section"];
        NSMutableArray *rows = grouped[section];
        if (!rows) { rows = [NSMutableArray array]; grouped[section] = rows; }
        [rows addObject:f];
    }
    self.featuresBySection = [grouped copy];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search features";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Search (#9)

- (BOOL)tm_isSearching {
    return self.searchController.isActive &&
           self.searchController.searchBar.text.length > 0;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text.lowercaseString;
    if (query.length == 0) {
        self.filteredFeatures = @[];
    } else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *f, NSDictionary *b) {
            NSString *title = ((NSString *)f[@"title"]).lowercaseString;
            NSString *section = ((NSString *)f[@"section"]).lowercaseString;
            return [title containsString:query] || [section containsString:query];
        }];
        self.filteredFeatures = [[TikTokModSettings allFeatures] filteredArrayUsingPredicate:p];
    }
    [self.tableView reloadData];
}

#pragma mark - Extra control rows (#9)

/// Control rows appended after the feature toggles of a section.
/// Each entry: @{@"id", @"title"}. Detail text is computed in
/// -detailForExtraRowId:.
- (NSArray<NSDictionary *> *)extraRowsForSection:(NSString *)section {
    if ([section isEqualToString:@"Player"]) {
        return @[
            @{@"id": @"speed", @"title": @"Playback speed — current rate (#2)"},
            @{@"id": @"hideUIOpacity", @"title": @"Hide-UI opacity (#29)"},
            @{@"id": @"burnInOpacity", @"title": @"Anti-burn-in dim opacity (#8)"},
            @{@"id": @"fakeStatusBar", @"title": @"Fake status bar — signal / Wi-Fi (#39)"},
            @{@"id": @"autoScroll", @"title": @"Auto-scroll options — delay / mode (#31)"},
        ];
    }
    if ([section isEqualToString:@"Posting & Camera"]) {
        return @[
            @{@"id": @"flash", @"title": @"Colored selfie flash — experimental (#7)"},
        ];
    }
    if ([section isEqualToString:@"Chats & Comments"]) {
        return @[
            @{@"id": @"streaks", @"title": @"Automatic streaks — recipients / sticker / timing (#16)"},
            @{@"id": @"streakSendNow", @"title": @"Send one streak round now (#16)"},
        ];
    }
    if ([section isEqualToString:@"Downloads"]) {
        return @[
            @{@"id": @"offlineCount", @"title": @"Offline video count (#19)"},
            @{@"id": @"qualityPicker", @"title": @"Download current video — pick quality (#10)"},
            @{@"id": @"webSource", @"title": @"Download from web source / paste URL (#18)"},
            @{@"id": @"audioDownload", @"title": @"Download current video's audio (#25)"},
            @{@"id": @"pinningStatus", @"title": @"Pinning-bypass status (HARD gate)"},
        ];
    }
    if ([section isEqualToString:@"Profile & Appearance"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *icon in [TikTokModV1 alternateIcons]) {
            [rows addObject:@{@"id": [@"icon-" stringByAppendingString:icon[@"title"]],
                              @"title": [@"App icon: " stringByAppendingString:icon[@"title"]]}];
        }
        [rows addObject:@{@"id": @"customFont", @"title": @"Custom font — system or named (#32)"}];
        [rows addObject:@{@"id": @"themeAccent", @"title": @"Theme accent color — feed chrome (#33)"}];
        [rows addObject:@{@"id": @"themeBackground", @"title": @"Theme background color — feed chrome (#33)"}];
        return [rows copy];
    }
    if ([section isEqualToString:@"Mod"]) {
        return @[
            @{@"id": @"otaCheck", @"title": @"Check for mod updates (#41, incl. #15)"},
            @{@"id": @"telegram", @"title": @"Telegram community (#42)"},
            @{@"id": @"startupShow", @"title": @"Show startup screen again (#40)"},
        ];
    }
    if ([section isEqualToString:@"Feed & Discovery"]) {
        return @[
            @{@"id": @"unhideAll", @"title": @"Unhide all elements hidden by the editor (#1)"},
            @{@"id": @"filterWords", @"title": @"Content filter words & tags (#22)"},
            @{@"id": @"filterMinLikes", @"title": @"Content filter — minimum likes (#22)"},
            @{@"id": @"filterMinViews", @"title": @"Content filter — minimum views (#22)"},
            @{@"id": @"keywordEditor", @"title": @"Open TikTok's own keyword editor (#22)"},
            @{@"id": @"regionPicker", @"title": @"Region — pick country code (#24, PARTIAL)"},
        ];
    }
    return @[];
}

- (nullable NSString *)detailForExtraRowId:(NSString *)rowId {
    TikTokModSettings *s = [TikTokModSettings shared];
    if ([rowId isEqualToString:@"speed"]) {
        return [NSString stringWithFormat:@"%.2fx — tap to change (0.5–3.0)", s.playbackRateValue];
    }
    if ([rowId isEqualToString:@"hideUIOpacity"]) {
        return [NSString stringWithFormat:@"%.0f%% — tap to change", s.hideUIOpacityValue * 100];
    }
    if ([rowId isEqualToString:@"burnInOpacity"]) {
        return [NSString stringWithFormat:@"%.0f%% — tap to change", s.feedOverlayOpacity * 100];
    }
    if ([rowId isEqualToString:@"fakeStatusBar"]) {
        return [NSString stringWithFormat:@"Signal %ld/4, Wi-Fi %@ (user-set values, not live readings)",
                (long)s.fakeStatusBarSignalBars, s.fakeStatusBarWifiEnabled ? @"on" : @"off"];
    }
    if ([rowId hasPrefix:@"icon-"]) {
        NSString *name = [rowId substringFromIndex:5];
        NSString *current = s.selectedAlternateIconName;
        BOOL isCurrent = (current == nil && [name isEqualToString:@"Default (stock)"]) ||
                         [current isEqualToString:name];
        if ([name isEqualToString:@"Default (stock)"] && current == nil) isCurrent = YES;
        return isCurrent ? @"Current" : nil;
    }
    if ([rowId isEqualToString:@"otaCheck"]) {
        return [NSString stringWithFormat:@"You have %@ — tap to check GitHub releases", kTikTokModVersion];
    }
    if ([rowId isEqualToString:@"telegram"]) {
        NSString *url = s.telegramCommunityURL;
        return url.length > 0 ? url : @"No link configured — tap to set it";
    }
    if ([rowId isEqualToString:@"startupShow"]) return @"Opens the check / download / FAQ / legal / stats screen";
    if ([rowId isEqualToString:@"unhideAll"]) {
        return [NSString stringWithFormat:@"%lu element class(es) hidden",
                (unsigned long)(s.hiddenElementClasses.count)];
    }
    if ([rowId isEqualToString:@"autoScroll"]) {
        return [NSString stringWithFormat:@"Delay %.0fs, %@ — tap to change",
                s.autoScrollDelaySeconds,
                s.autoScrollOnlyAfterFullWatch ? @"only after full watch" : @"timed (always)"];
    }
    if ([rowId isEqualToString:@"flash"]) {
        return [NSString stringWithFormat:@"Sub-toggle %@, color %@ — tap to change (EXPERIMENTAL, PARTIAL)",
                s.coloredSelfieFlashEnabled ? @"ON" : @"OFF", s.frontFlashColorHex];
    }
    if ([rowId isEqualToString:@"streaks"]) {
        return [NSString stringWithFormat:@"%lu recipient(s), every %ld min, sticker %@ — tap to change",
                (unsigned long)(s.streakRecipients.count), (long)s.streakIntervalMinutes,
                s.streakStickerID.length > 0 ? s.streakStickerID : @"none"];
    }
    if ([rowId isEqualToString:@"streakSendNow"]) {
        return @"Sends one round now via the stock send path";
    }
    if ([rowId isEqualToString:@"filterWords"]) {
        return [NSString stringWithFormat:@"%lu word(s), %lu tag(s) — tap to change",
                (unsigned long)(s.filterWords.count), (unsigned long)(s.filterTags.count)];
    }
    if ([rowId isEqualToString:@"filterMinLikes"]) {
        return [NSString stringWithFormat:@"Min likes: %ld (0 = no floor) — tap to change", (long)s.filterMinLikes];
    }
    if ([rowId isEqualToString:@"filterMinViews"]) {
        return [NSString stringWithFormat:@"Min views: %ld (0 = no floor) — tap to change", (long)s.filterMinViews];
    }
    if ([rowId isEqualToString:@"keywordEditor"]) {
        return @"Opens TikTok's own keyword-filter editor";
    }
    if ([rowId isEqualToString:@"offlineCount"]) {
        return [NSString stringWithFormat:@"Fetch count: %ld (default 500) — tap to change", (long)s.offlineVideoCount];
    }
    if ([rowId isEqualToString:@"customFont"]) {
        return [NSString stringWithFormat:@"Font: %@ — tap to change", s.customFontName];
    }
    if ([rowId isEqualToString:@"themeAccent"]) {
        return [NSString stringWithFormat:@"Accent: %@ (feed chrome only) — tap to change",
                s.themeAccentColorHex ?: @"stock"];
    }
    if ([rowId isEqualToString:@"themeBackground"]) {
        return [NSString stringWithFormat:@"Background: %@ (feed chrome only) — tap to change",
                s.themeBackgroundColorHex ?: @"stock"];
    }
    // --- HARD rows (#10 / #18 / #24 / #25 + bypass status) ---
    if ([rowId isEqualToString:@"qualityPicker"]) {
        NSString *choice = s.downloadQualityChoice;
        return [NSString stringWithFormat:@"Remembered quality: %@ — tap to download the current video (UNVERIFIED-RUNTIME)",
                choice];
    }
    if ([rowId isEqualToString:@"webSource"]) {
        return @"Paste a URL or reuse the last stock source — tap to open the picker (UNVERIFIED-RUNTIME)";
    }
    if ([rowId isEqualToString:@"audioDownload"]) {
        return @"Saves to Documents/TikTokMod/Music/ — tap to download the current video's audio (UNVERIFIED-RUNTIME)";
    }
    if ([rowId isEqualToString:@"pinningStatus"]) {
        return @"Tap for the full bypass status (ObjC surfaces only — TTNet native layer NOT covered)";
    }
    if ([rowId isEqualToString:@"regionPicker"]) {
        NSString *code = s.regionCode;
        return [NSString stringWithFormat:@"Region: %@ — tap to change (PARTIAL — server decides the feed)",
                code.length > 0 ? code : @"stock"];
    }
    return nil;
}

#pragma mark - Table view

- (NSArray<NSString *> *)tm_visibleSections {
    if ([self tm_isSearching]) return @[@"Results"];
    return self.sections;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)[self tm_visibleSections].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self tm_visibleSections][(NSUInteger)section];
}

- (BOOL)isCustomBackgroundPickerRow:(NSIndexPath *)indexPath {
    if ([self tm_isSearching]) return NO;
    return [[self tm_visibleSections][(NSUInteger)indexPath.section] isEqualToString:kCustomBackgroundPickerSection]
        && indexPath.row == (NSInteger)self.featuresBySection[kCustomBackgroundPickerSection].count;
}

- (nullable NSDictionary *)extraRowForIndexPath:(NSIndexPath *)indexPath {
    if ([self tm_isSearching]) return nil;
    NSString *section = [self tm_visibleSections][(NSUInteger)indexPath.section];
    NSArray *features = self.featuresBySection[section];
    NSInteger extraStart = (NSInteger)features.count;
    if ([section isEqualToString:kCustomBackgroundPickerSection]) extraStart += 1; // #45 picker row
    NSInteger extraIndex = indexPath.row - extraStart;
    NSArray *extras = [self extraRowsForSection:section];
    if (extraIndex < 0 || extraIndex >= (NSInteger)extras.count) return nil;
    return extras[(NSUInteger)extraIndex];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self tm_isSearching]) return (NSInteger)self.filteredFeatures.count;
    NSString *name = [self tm_visibleSections][(NSUInteger)section];
    NSInteger count = (NSInteger)self.featuresBySection[name].count;
    if ([name isEqualToString:kCustomBackgroundPickerSection]) count += 1;  // #45 picker row
    count += (NSInteger)[self extraRowsForSection:name].count;
    return count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == (NSInteger)[self tm_visibleSections].count - 1 && ![self tm_isSearching]) {
        return @"TikTokMod 47.7.0 V3 — 42 features implemented per DYLIB-DESIGN.md §4. "
               @"Compile-verified only: no iOS device exists on the build VM, so no hook is "
               @"runtime-tested — test on a secondary account only. Series unlock is impossible "
               @"and is never attempted (hide only). UNVERIFIED rows lift a client limit the "
               @"server may still enforce — do not present them as working. HARD phase "
               @"(#10 #18 #25 downloads, #27 ads) is UNVERIFIED-RUNTIME: the pinning bypass "
               @"covers ObjC surfaces only and is unproven without a traffic capture; #24 region "
               @"is PARTIAL (server decides the feed); #44 watermark-free stays DEFERRED and OFF.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellID = @"TikTokModHubCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if ([self tm_isSearching]) {
        NSDictionary *feature = self.filteredFeatures[(NSUInteger)indexPath.row];
        NSString *key = feature[@"key"];
        cell.textLabel.text = feature[@"title"];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.text = feature[@"note"];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor systemOrangeColor];
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [[TikTokModSettings shared] boolForKey:key];
        toggle.accessibilityIdentifier = key;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    if ([self isCustomBackgroundPickerRow:indexPath]) {
        // #45 picker row: tap to choose an image or a color.
        TikTokModSettings *settings = [TikTokModSettings shared];
        cell.textLabel.text = @"Custom background: pick image or color";
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        NSString *mode = settings.customBackgroundMode;
        if ([mode isEqualToString:@"image"]) {
            cell.detailTextLabel.text = @"Image set — tap to change";
        } else if ([mode isEqualToString:@"color"]) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Color %@ — tap to change", settings.customBackgroundColorHex ?: @"?"];
        } else {
            cell.detailTextLabel.text = @"No background set — tap to pick";
        }
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSDictionary *extra = [self extraRowForIndexPath:indexPath];
    if (extra) {
        cell.textLabel.text = extra[@"title"];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.text = [self detailForExtraRowId:extra[@"id"]];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    NSString *section = [self tm_visibleSections][(NSUInteger)indexPath.section];
    NSDictionary *feature = self.featuresBySection[section][(NSUInteger)indexPath.row];
    NSString *key = feature[@"key"];
    cell.textLabel.text = feature[@"title"];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    NSString *note = feature[@"note"];
    cell.detailTextLabel.text = note;  // nil for verified features
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.textColor = [UIColor systemOrangeColor];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = [[TikTokModSettings shared] boolForKey:key];
    toggle.accessibilityIdentifier = key;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSString *key = sender.accessibilityIdentifier;
    if (!key) return;
    [[TikTokModSettings shared] setBool:sender.isOn forKey:key];
    NSLog(@"[TikTokMod] toggle %@ = %@", key, sender.isOn ? @"ON" : @"OFF");
}

#pragma mark - Row selection (extra rows + #45 picker)

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self tm_isSearching]) return;
    if ([self isCustomBackgroundPickerRow:indexPath]) {
        [self presentBackgroundChooser];
        return;
    }
    NSDictionary *extra = [self extraRowForIndexPath:indexPath];
    if (!extra) return;
    [self handleExtraRow:extra[@"id"]];
}

#pragma mark - V2 config helpers (text entry + comma lists)

- (void)tm_presentTextEntryWithTitle:(NSString *)title
                             message:(NSString *)message
                         placeholders:(NSArray<NSString *> *)placeholders
                             initials:(NSArray<NSString *> *)initials
                              handler:(void (^)(NSArray<NSString *> *texts))handler {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    for (NSUInteger i = 0; i < placeholders.count; i++) {
        NSString *ph = placeholders[i];
        NSString *initial = i < initials.count ? initials[i] : nil;
        [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = ph;
            tf.text = initial;
        }];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
                                        handler:^(__unused UIAlertAction *act) {
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        for (UITextField *tf in a.textFields) [texts addObject:tf.text ?: @""];
        if (handler) handler([texts copy]);
        [self.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSArray<NSString *> *)tm_commaListFromString:(NSString *)string {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *part in [string componentsSeparatedByString:@","]) {
        NSString *t = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) [out addObject:t];
    }
    return [out copy];
}

- (void)handleExtraRow:(NSString *)rowId {
    TikTokModSettings *s = [TikTokModSettings shared];
    if ([rowId isEqualToString:@"speed"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Playback speed (#2)"
            message:@"Applies to the active player and persists between videos." preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *rate in @[@0.5, @0.75, @1.0, @1.25, @1.5, @2.0, @2.5, @3.0]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%.2fx", rate.floatValue]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.playbackRateValue = rate.floatValue;
                s.playbackSpeed3x = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"hideUIOpacity"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Hide-UI opacity (#29)"
            message:@"Alpha applied to the feed interaction elements." preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *pct in @[@0, @25, @50, @75, @100]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@%%", pct]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.hideUIOpacityValue = pct.floatValue / 100.0f;
                s.hideUIOpacity = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"burnInOpacity"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Anti-burn-in dim opacity (#8)"
            message:@"Alpha of the dimming overlay over the feed." preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *pct in @[@5, @12, @25, @40]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@%%", pct]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.feedOverlayOpacity = pct.floatValue / 100.0f;
                s.antiBurnInHideSystemBars = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"fakeStatusBar"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Fake status bar (#39)"
            message:@"Signal / Wi-Fi are user-set values — iOS has no public live API for them. Battery is live."
            preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSInteger bars = 0; bars <= 4; bars++) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Signal: %ld/4 bars", (long)bars]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.fakeStatusBarSignalBars = bars;
                s.fakeStatusBarPreview = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:s.fakeStatusBarWifiEnabled ? @"Wi-Fi: turn OFF" : @"Wi-Fi: turn ON"
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            s.fakeStatusBarWifiEnabled = !s.fakeStatusBarWifiEnabled;
            s.fakeStatusBarPreview = YES;
            [self.tableView reloadData];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId hasPrefix:@"icon-"]) {
        NSString *name = [rowId substringFromIndex:5];
        NSString *iconName = nil;
        for (NSDictionary *icon in [TikTokModV1 alternateIcons]) {
            if ([icon[@"title"] isEqualToString:name]) {
                id v = icon[@"iconName"];
                iconName = [v isKindOfClass:[NSNull class]] ? nil : v;
            }
        }
        [TikTokModV1 applyAlternateIconNamed:iconName fromViewController:self];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
    } else if ([rowId isEqualToString:@"otaCheck"]) {
        [TikTokModV1 checkForUpdatesFromViewController:self];
    } else if ([rowId isEqualToString:@"telegram"]) {
        [TikTokModV1 openTelegramFromViewController:self];
    } else if ([rowId isEqualToString:@"startupShow"]) {
        [TikTokModV1 presentStartupScreenNow];
    } else if ([rowId isEqualToString:@"unhideAll"]) {
        [s setHiddenElementClasses:nil];
        NSLog(@"[TikTokMod] #1 unhid all editor-hidden elements");
        [self.tableView reloadData];
    } else if ([rowId isEqualToString:@"autoScroll"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Auto-scroll (#31)"
            message:@"Advance to the next video automatically. End-of-video mode waits for the video to finish; timed mode advances after the delay even mid-video."
            preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *secs in @[@0, @1, @3, @5]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Delay: %@s", secs]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.autoScrollDelaySeconds = secs.floatValue;
                s.autoScrollAutoPlayNext = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Mode: only after full watch" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *a) {
            s.autoScrollOnlyAfterFullWatch = YES;
            s.autoScrollAutoPlayNext = YES;
            [self.tableView reloadData];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Mode: timed — advance even mid-video" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *a) {
            s.autoScrollOnlyAfterFullWatch = NO;
            s.autoScrollAutoPlayNext = YES;
            [self.tableView reloadData];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"flash"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Colored selfie flash (#7)"
            message:@"EXPERIMENTAL (PARTIAL): frontFlashColor is a real field, not a proven user-facing toggle. Verify on device whether a colored flash UI appears."
            preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:s.coloredSelfieFlashEnabled ? @"Flash color: turn OFF" : @"Flash color: turn ON"
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            s.coloredSelfieFlashEnabled = !s.coloredSelfieFlashEnabled;
            s.cameraExtras = YES;
            [self.tableView reloadData];
        }]];
        for (NSArray<NSString *> *choice in @[@[@"White", @"#FFFFFF"], @[@"Warm", @"#FFE0B2"],
                                               @[@"Cyan", @"#25F4EE"], @[@"Pink", @"#FE2C55"],
                                               @[@"Blue", @"#3B82F6"]]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ (%@)", choice[0], choice[1]]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.frontFlashColorHex = choice[1];
                s.coloredSelfieFlashEnabled = YES;
                s.cameraExtras = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"streaks"]) {
        [self tm_presentTextEntryWithTitle:@"Automatic streaks (#16)"
            message:@"Conversation IDs that receive the streak invite (comma-separated, your picks only), the sticker ID, and the interval in minutes. The timer drives the stock send path — it never sends to anyone you did not list."
            placeholders:@[@"Conversation IDs, comma-separated", @"Sticker ID (optional)", @"Interval in minutes"]
            initials:@[[[s streakRecipients] componentsJoinedByString:@", "] ?: @"",
                       [s streakStickerID] ?: @"",
                       [NSString stringWithFormat:@"%ld", (long)s.streakIntervalMinutes]]
            handler:^(NSArray<NSString *> *texts) {
                s.streakRecipients = [self tm_commaListFromString:texts[0]];
                s.streakStickerID = texts[1].length > 0 ? texts[1] : nil;
                NSInteger mins = [texts[2] integerValue];
                s.streakIntervalMinutes = mins > 0 ? mins : 60;
                s.automaticStreaks = YES;
                [TikTokModV2 refreshStreakTimer];
            }];
    } else if ([rowId isEqualToString:@"streakSendNow"]) {
        [TikTokModV2 sendStreaksNow];
        [self.tableView reloadData];
    } else if ([rowId isEqualToString:@"filterWords"]) {
        [self tm_presentTextEntryWithTitle:@"Content filters (#22)"
            message:@"Words and tags (comma-separated). A feed item whose caption or hashtags contain a word/tag is hidden. Likes/views floors are set in their own rows."
            placeholders:@[@"Words, comma-separated", @"Tags, comma-separated"]
            initials:@[[[s filterWords] componentsJoinedByString:@", "] ?: @"",
                       [[s filterTags] componentsJoinedByString:@", "] ?: @""]
            handler:^(NSArray<NSString *> *texts) {
                s.filterWords = [self tm_commaListFromString:texts[0]];
                s.filterTags = [self tm_commaListFromString:texts[1]];
                s.contentFilters = YES;
            }];
    } else if ([rowId isEqualToString:@"filterMinLikes"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Minimum likes (#22)"
            message:@"Feed items with fewer likes than this are hidden. 0 = no floor."
            preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *n in @[@0, @100, @1000, @10000, @100000]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ likes", n]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.filterMinLikes = n.integerValue;
                s.contentFilters = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"filterMinViews"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Minimum views (#22)"
            message:@"Feed items with fewer views than this are hidden. 0 = no floor."
            preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *n in @[@0, @1000, @10000, @100000, @1000000]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ views", n]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.filterMinViews = n.integerValue;
                s.contentFilters = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"keywordEditor"]) {
        [TikTokModV2 openStockKeywordFilterFromViewController:self];
    } else if ([rowId isEqualToString:@"offlineCount"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Offline video count (#19)"
            message:@"How many videos the offline fetcher requests. No iOS twin of Android's \"2,000\" exists — this tunes the count path instead."
            preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSNumber *n in @[@100, @250, @500, @1000]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ videos", n]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.offlineVideoCount = n.integerValue;
                s.offlineVideoLimit = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"customFont"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Custom font (#32)"
            message:@"System = the iOS system font for every request. A named font must be installed on the device (PostScript name); an unknown name falls back to the system font."
            preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *name in @[@"System", @"HelveticaNeue", @"Georgia", @"Courier", @"AvenirNext-Regular"]) {
            [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction *a) {
                s.customFontName = name;
                s.customFonts = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Type a PostScript name…" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *a) {
            [self tm_presentTextEntryWithTitle:@"Custom font (#32)"
                message:@"Enter the font's PostScript name exactly."
                placeholders:@[@"PostScript font name"]
                initials:@[[s customFontName] ?: @"System"]
                handler:^(NSArray<NSString *> *texts) {
                    if (texts[0].length > 0) {
                        s.customFontName = texts[0];
                        s.customFonts = YES;
                    }
                }];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"themeAccent"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Theme accent color (#33)"
            message:@"Feed chrome only (right rail + container tint). Per-surface — no global theme engine (DEFER)."
            preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"None (stock)" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *a) {
            s.themeAccentColorHex = nil;
            [self.tableView reloadData];
        }]];
        for (NSArray<NSString *> *choice in @[@[@"TikTok cyan", @"#25F4EE"], @[@"TikTok red", @"#FE2C55"],
                                               @[@"Purple", @"#8B5CF6"], @[@"Green", @"#22C55E"],
                                               @[@"Orange", @"#F97316"]]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ (%@)", choice[0], choice[1]]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.themeAccentColorHex = choice[1];
                s.customColorsTheming = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"themeBackground"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Theme background color (#33)"
            message:@"Feed chrome only (bottom bar / tab bar). Per-surface — no global theme engine (DEFER)."
            preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"None (stock)" style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *a) {
            s.themeBackgroundColorHex = nil;
            [self.tableView reloadData];
        }]];
        for (NSArray<NSString *> *choice in @[@[@"Black", @"#000000"], @[@"Dark gray", @"#1F1F1F"],
                                               @[@"Navy", @"#1A1A2E"], @[@"Dark purple", @"#2D1B4E"]]) {
            [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ (%@)", choice[0], choice[1]]
                style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                s.themeBackgroundColorHex = choice[1];
                s.customColorsTheming = YES;
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentActionSheet:sheet];
    } else if ([rowId isEqualToString:@"qualityPicker"]) {
        [TikTokModHard downloadCurrentVideoFromViewController:self];
    } else if ([rowId isEqualToString:@"webSource"]) {
        [TikTokModHard downloadFromWebSourceFromViewController:self];
    } else if ([rowId isEqualToString:@"audioDownload"]) {
        [TikTokModHard downloadCurrentAudioFromViewController:self];
    } else if ([rowId isEqualToString:@"pinningStatus"]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Pinning-bypass status (HARD gate)"
            message:[[TikTokModHard pinningBypassStatus]
                stringByAppendingString:@"\n\nUNVERIFIED-RUNTIME: only a traffic capture showing Aweme API JSON proves the bypass. The TTNet native libvcn/boringssl layer is NOT covered."]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else if ([rowId isEqualToString:@"regionPicker"]) {
        [TikTokModHard pickRegionFromViewController:self];
    }
}

- (void)presentActionSheet:(UIAlertController *)sheet {
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - #45 Custom Background picker

- (void)presentBackgroundChooser {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Custom background"
                                                                   message:@"Pick an image from your photo library, or choose a color. Applied as a bottom overlay behind the feed (video stays opaque)."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Pick image from library" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [self presentImagePicker];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose a color" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [self presentColorChoices];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear background" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [[TikTokModSettings shared] clearCustomBackgroundImage];
        [self.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentActionSheet:sheet];
}

- (void)presentImagePicker {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        NSLog(@"[TikTokMod] image picker: photo library unavailable (fail-soft)");
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentColorChoices {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Background color"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSArray<NSString *> *> *choices = @[
        @[@"Black", @"#000000"], @[@"White", @"#FFFFFF"],
        @[@"Dark blue", @"#1A1A2E"], @[@"Dark purple", @"#2D1B4E"],
        @[@"Dark green", @"#0F2E1F"], @[@"Dark red", @"#3A0D0D"],
    ];
    for (NSArray<NSString *> *choice in choices) {
        NSString *name = choice[0];
        NSString *hex = choice[1];
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ (%@)", name, hex]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *a) {
            TikTokModSettings *settings = [TikTokModSettings shared];
            settings.customBackgroundColorHex = hex;
            settings.customBackgroundMode = @"color";
            NSLog(@"[TikTokMod] custom background color set: %@", hex);
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentActionSheet:sheet];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (image) {
            [[TikTokModSettings shared] saveCustomBackgroundImage:image];
        } else {
            NSLog(@"[TikTokMod] image picker: no image returned (fail-soft)");
        }
        [self.tableView reloadData];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end
