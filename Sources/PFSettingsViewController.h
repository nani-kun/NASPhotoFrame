#import <UIKit/UIKit.h>
@class PFConfiguration;

@interface PFSettingsViewController : UITableViewController
@property (nonatomic, copy) void (^saveHandler)(PFConfiguration *configuration);
@property (nonatomic, copy) void (^closeHandler)(void);
@property (nonatomic) BOOL allowsCancel;
@end
