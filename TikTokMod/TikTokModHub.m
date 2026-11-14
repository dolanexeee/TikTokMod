//
//  TikTokModHub.m
//  Hub rows come from [TikTokModSettings allFeatures] — no hardcoded list here.
//  Server-side-caution features (comment reposts, 9-image comments, hashtag
//  limit, repost character limit, send/pin limits) show their UNVERIFIED note
//  and are NOT presented as working. Series is hide-only, never an unlock.
//
#import "TikTokModHub.h"
#import "TikTokModSettings.h"

@interface TikTokModHub () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) NSArray<NSString *> *sections;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSDictionary *> *> *featuresBySection;
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
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[(NSUInteger)section];
}

- (BOOL)isCustomBackgroundPickerRow:(NSIndexPath *)indexPath {
    return [self.sections[(NSUInteger)indexPath.section] isEqualToString:kCustomBackgroundPickerSection]
        && indexPath.row == (NSInteger)self.featuresBySection[kCustomBackgroundPickerSection].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = (NSInteger)self.featuresBySection[self.sections[(NSUInteger)section]].count;
    if ([self.sections[(NSUInteger)section] isEqualToString:kCustomBackgroundPickerSection]) count += 1;  // #45 picker row
    return count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == (NSInteger)self.sections.count - 1) {
        return @"TikTokMod 47.7.0 skeleton — 40 toggles are stubs, no real TikTok hooks yet. "
               @"Test on a secondary account only. Series unlock is impossible and is never attempted. "
               @"UNVERIFIED rows lift a client limit the server may still enforce — do not present them as working.";
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
    if ([self isCustomBackgroundPickerRow:indexPath]) {
        // #45 picker row: tap to choose an image or a color.
        TikTokModSettings *settings = [TikTokModSettings shared];
        UITableViewCell *pickerCell = [tableView dequeueReusableCellWithIdentifier:CellID];
        if (!pickerCell) {
            pickerCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellID];
        }
        pickerCell.textLabel.text = @"Custom background: pick image or color";
        pickerCell.textLabel.numberOfLines = 0;
        pickerCell.textLabel.font = [UIFont systemFontOfSize:15];
        NSString *mode = settings.customBackgroundMode;
        if ([mode isEqualToString:@"image"]) {
            pickerCell.detailTextLabel.text = @"Image set — tap to change";
        } else if ([mode isEqualToString:@"color"]) {
            pickerCell.detailTextLabel.text = [NSString stringWithFormat:@"Color %@ — tap to change", settings.customBackgroundColorHex ?: @"?"];
        } else {
            pickerCell.detailTextLabel.text = @"No background set — tap to pick";
        }
        pickerCell.detailTextLabel.numberOfLines = 0;
        pickerCell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        pickerCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        pickerCell.accessoryView = nil;
        return pickerCell;
    }
    NSDictionary *feature = self.featuresBySection[self.sections[(NSUInteger)indexPath.section]][(NSUInteger)indexPath.row];
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

#pragma mark - #45 Custom Background picker

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isCustomBackgroundPickerRow:indexPath]) {
        [self presentBackgroundChooser];
    }
}

- (void)presentBackgroundChooser {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Custom background"
                                                                   message:@"Pick an image from your photo library, or choose a color. Applied later as an overlay behind the feed."
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
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
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
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
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
