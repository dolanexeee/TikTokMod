//
//  TikTokModHub.h
//  TikTokMod — settings hub UI (plain UITableViewController), driven by
//  the TikTokModSettings feature registry (42 toggles, grouped by section).
//  Skeleton only: rows toggle stub settings; no TikTok hooks.
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TikTokModHub : UITableViewController

/// Present the hub modally from the key window's root view controller.
/// Fail-soft: logs and returns NO if no window / view controller is available.
+ (BOOL)presentHub;

@end

NS_ASSUME_NONNULL_END
