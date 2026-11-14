//
//  TikTokModHub.m
//  Hub rows come from [TikTokModSettings allFeatures] — no hardcoded list here.
//  Server-side-caution features (comment reposts, 9-image comments, hashtag
//  limit, repost character limit, send/pin limits) show their UNVERIFIED note
//  and are NOT presented as working. Series is hide-only, never an unlock.
//
#import "TikTokModHub.h"
#import "TikTokModSettings.h"

@interface TikTokModHub ()
@property (nonatomic, strong) NSArray<NSString *> *sections;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSDictionary *> *> *featuresBySection;
@end

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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.featuresBySection[self.sections[(NSUInteger)section]].count;
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

@end
