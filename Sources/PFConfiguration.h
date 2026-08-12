#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, PFPlaybackMode) {
    PFPlaybackModeSequential = 0,
    PFPlaybackModeRandom = 1
};

@interface PFConfiguration : NSObject <NSCopying>
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *share;
@property (nonatomic, copy) NSString *rootPath;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *domain;
@property (nonatomic) NSTimeInterval scanInterval;
@property (nonatomic) NSTimeInterval slideDuration;
@property (nonatomic) unsigned long long cacheLimitBytes;
@property (nonatomic) PFPlaybackMode playbackMode;
@property (nonatomic) BOOL swipeNavigationEnabled;
@property (nonatomic) BOOL photoPanEnabled;
@property (nonatomic) BOOL kenBurnsEnabled;
@property (nonatomic) BOOL photoInfoEnabled;
@property (nonatomic, readonly, getter=isComplete) BOOL complete;
+ (instancetype)load;
- (void)save;
@end
