#import "PFAppDelegate.h"
#import "PFPlayerViewController.h"
#import "PFPhotoService.h"

static NSString * const kPFPolicyPath = @"/var/mobile/Library/Preferences/com.wangxiaoxiang.nasphotoframe.policy.plist";

@implementation PFAppDelegate

- (void)applyConfiguredBrightness {
    NSDictionary *policy = [NSDictionary dictionaryWithContentsOfFile:kPFPolicyPath];
    NSNumber *saved = [policy objectForKey:@"brightnessPercent"];
    if (![saved respondsToSelector:@selector(integerValue)]) {
        return;
    }
    NSInteger percent = MAX(5, MIN(100, [saved integerValue]));
    [UIScreen mainScreen].brightness = (CGFloat)percent / 100.0;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    application.idleTimerDisabled = YES;
    // iOS 8 can retain the previous status-bar visibility when a jailbroken
    // app is launched.  Set it explicitly in addition to the plist setting.
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.window.rootViewController = [[PFPlayerViewController alloc] init];
    [self.window makeKeyAndVisible];
    [self applyConfiguredBrightness];
    [[PFPhotoService sharedService] start];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    application.idleTimerDisabled = YES;
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    [self applyConfiguredBrightness];
    [[PFPhotoService sharedService] applicationDidBecomeActive];
}

@end
