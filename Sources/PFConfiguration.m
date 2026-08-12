#import "PFConfiguration.h"

static NSString * const PFConfigurationDefaultsKey = @"PFConfiguration";

@implementation PFConfiguration

+ (instancetype)load {
    PFConfiguration *configuration = [[self alloc] init];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PFConfigurationDefaultsKey];
    configuration.host = saved[@"host"] ?: @"";
    configuration.share = saved[@"share"] ?: @"";
    configuration.rootPath = saved[@"rootPath"] ?: @"";
    configuration.username = saved[@"username"] ?: @"";
    configuration.domain = saved[@"domain"] ?: @"";
    configuration.scanInterval = [saved[@"scanInterval"] doubleValue] ?: (3.0 * 60.0 * 60.0);
    configuration.slideDuration = [saved[@"slideDuration"] doubleValue] ?: 20.0;
    configuration.cacheLimitBytes = [saved[@"cacheLimitBytes"] unsignedLongLongValue] ?: (1024ULL * 1024ULL * 1024ULL);
    configuration.playbackMode = [saved[@"playbackMode"] integerValue];
    NSNumber *swipeNavigationEnabled = saved[@"swipeNavigationEnabled"];
    configuration.swipeNavigationEnabled = swipeNavigationEnabled ? [swipeNavigationEnabled boolValue] : YES;
    NSNumber *photoPanEnabled = saved[@"photoPanEnabled"];
    configuration.photoPanEnabled = photoPanEnabled ? [photoPanEnabled boolValue] : YES;
    NSNumber *kenBurnsEnabled = saved[@"kenBurnsEnabled"];
    configuration.kenBurnsEnabled = kenBurnsEnabled ? [kenBurnsEnabled boolValue] : NO;
    NSNumber *photoInfoEnabled = saved[@"photoInfoEnabled"];
    configuration.photoInfoEnabled = photoInfoEnabled ? [photoInfoEnabled boolValue] : YES;
    return configuration;
}

- (BOOL)isComplete {
    return self.host.length > 0 && self.share.length > 0 && self.username.length > 0;
}

- (void)save {
    NSDictionary *values = @{
        @"host": self.host ?: @"",
        @"share": self.share ?: @"",
        @"rootPath": self.rootPath ?: @"",
        @"username": self.username ?: @"",
        @"domain": self.domain ?: @"",
        @"scanInterval": @(MAX(self.scanInterval, 15.0 * 60.0)),
        @"slideDuration": @(MAX(self.slideDuration, 3.0)),
        @"cacheLimitBytes": @(MAX(self.cacheLimitBytes, (unsigned long long)(100ULL * 1024ULL * 1024ULL))),
        @"playbackMode": @(self.playbackMode),
        @"swipeNavigationEnabled": @(self.swipeNavigationEnabled),
        @"photoPanEnabled": @(self.photoPanEnabled),
        @"kenBurnsEnabled": @(self.kenBurnsEnabled),
        @"photoInfoEnabled": @(self.photoInfoEnabled)
    };
    [[NSUserDefaults standardUserDefaults] setObject:values forKey:PFConfigurationDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (id)copyWithZone:(NSZone *)zone {
    PFConfiguration *copy = [[[self class] allocWithZone:zone] init];
    copy.host = self.host;
    copy.share = self.share;
    copy.rootPath = self.rootPath;
    copy.username = self.username;
    copy.domain = self.domain;
    copy.scanInterval = self.scanInterval;
    copy.slideDuration = self.slideDuration;
    copy.cacheLimitBytes = self.cacheLimitBytes;
    copy.playbackMode = self.playbackMode;
    copy.swipeNavigationEnabled = self.swipeNavigationEnabled;
    copy.photoPanEnabled = self.photoPanEnabled;
    copy.kenBurnsEnabled = self.kenBurnsEnabled;
    copy.photoInfoEnabled = self.photoInfoEnabled;
    return copy;
}

@end
