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
        ];
    }
    if ([section isEqualToString:@"Profile & Appearance"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *icon in [TikTokModV1 alternateIcons]) {
            [rows addObject:@{@"id": [@"icon-" stringByAppendingString:icon[@"title"]],
                              @"title": [@"App icon: " stringByAppendingString:icon[@"title"]]}];
        }
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
        return @"TikTokMod 47.7.0 V1 — 24 features implemented per DYLIB-DESIGN.md §4. "
               @"Compile-verified only: no iOS device exists on the build VM, so no hook is "
               @"runtime-tested — test on a secondary account only. Series unlock is impossible "
               @"and is never attempted (hide only). UNVERIFIED rows lift a client limit the "
               @"server may still enforce — do not present them as working.";
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
