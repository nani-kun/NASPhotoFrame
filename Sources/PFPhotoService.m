#import "PFPhotoService.h"
#import "PFConfiguration.h"
#import "PFCredentialStore.h"
#import "PFSMBClient.h"
#import "PFPhotoIndex.h"
#import "PFCacheManager.h"
#import "PFImageDecoder.h"
#import "PFPhoto.h"
#import "PFLocalization.h"

NSString * const PFPhotoServiceScanDidFinishNotification = @"PFPhotoServiceScanDidFinishNotification";
NSString * const PFPhotoServiceScanErrorKey = @"error";
NSString * const PFPhotoServicePhotoCountKey = @"photoCount";
static const NSTimeInterval PFScanFailureRetryDelay = 60.0;

@interface PFPhotoService ()
@property (nonatomic, strong) PFConfiguration *currentConfiguration;
@property (nonatomic, strong) PFPhotoIndex *index;
@property (nonatomic, strong) PFCacheManager *cache;
@property (nonatomic, strong) PFSMBClient *client;
@property (nonatomic) dispatch_queue_t scanQueue;
@property (nonatomic) dispatch_queue_t downloadQueue;
@property (nonatomic) BOOL scanInProgress;
@property (nonatomic) NSTimeInterval networkUnavailableUntil;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation PFPhotoService

+ (instancetype)sharedService {
    static PFPhotoService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ service = [[self alloc] initPrivate]; });
    return service;
}

- (instancetype)init { return [PFPhotoService sharedService]; }

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _currentConfiguration = [PFConfiguration load];
        _client = [[PFSMBClient alloc] init];
        _scanQueue = dispatch_queue_create("com.wangxiaoxiang.nasphotoframe.scan", DISPATCH_QUEUE_SERIAL);
        _downloadQueue = dispatch_queue_create("com.wangxiaoxiang.nasphotoframe.download", DISPATCH_QUEUE_SERIAL);
        NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        if (!support) support = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [[NSFileManager defaultManager] createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
        _index = [[PFPhotoIndex alloc] initWithDatabasePath:[support stringByAppendingPathComponent:@"photos.sqlite3"]];
        _cache = [[PFCacheManager alloc] initWithDirectory:[support stringByAppendingPathComponent:@"PhotoCache"] limitBytes:_currentConfiguration.cacheLimitBytes];
    }
    return self;
}

- (PFConfiguration *)configuration {
    @synchronized (self) { return [self.currentConfiguration copy]; }
}

- (void)applyConfiguration:(PFConfiguration *)configuration {
    @synchronized (self) {
        self.currentConfiguration = [configuration copy];
        self.cache.limitBytes = configuration.cacheLimitBytes;
    }
    [self installTimer];
    [self requestScan];
}

- (void)start {
    [self installTimer];
    if (self.configuration.isComplete) [self requestScan];
}

- (void)applicationDidBecomeActive {
    NSTimeInterval last = [[NSUserDefaults standardUserDefaults] doubleForKey:@"PFLastSuccessfulScan"];
    if ([NSDate timeIntervalSinceReferenceDate] - last >= self.configuration.scanInterval) [self requestScan];
}

- (void)installTimer {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.timer invalidate];
        NSTimeInterval interval = MAX(self.configuration.scanInterval, 15.0 * 60.0);
        self.timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(scanTimerFired:) userInfo:nil repeats:YES];
    });
}

- (void)scanTimerFired:(NSTimer *)timer { [self requestScan]; }

- (void)requestScan {
    PFConfiguration *configuration = self.configuration;
    if (!configuration.isComplete) return;
    @synchronized (self) {
        if (self.scanInProgress) return;
        self.scanInProgress = YES;
    }
    dispatch_async(self.scanQueue, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSArray *photos = [self.client enumeratePhotosWithConfiguration:configuration password:[PFCredentialStore password] error:&error];
            if (photos) {
                NSString *scanID = [[NSUUID UUID] UUIDString];
                if ([self.index replaceRemoteSnapshot:photos scanIdentifier:scanID error:&error]) {
                    // Serialize reconciliation with downloads so a newly
                    // downloaded file cannot be removed before its local path
                    // is recorded in the index.
                    dispatch_sync(self.downloadQueue, ^{
                        NSMutableSet *referencedPaths = [NSMutableSet set];
                        for (PFPhoto *photo in [self.index allPhotos]) {
                            if (photo.localPath.length) [referencedPaths addObject:photo.localPath];
                        }
                        [self.cache removeFilesExceptPaths:referencedPaths];
                    });
                    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate] forKey:@"PFLastSuccessfulScan"];
                    [[NSUserDefaults standardUserDefaults] setInteger:photos.count forKey:@"PFLastSuccessfulPhotoCount"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                }
            }
            @synchronized (self) { self.scanInProgress = NO; }
            [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                                      forKey:@"PFLastScanAttempt"];
            if (error) {
                [[NSUserDefaults standardUserDefaults] setObject:error.localizedDescription ?: @""
                                                          forKey:@"PFLastScanError"];
            } else {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"PFLastScanError"];
            }
            [[NSUserDefaults standardUserDefaults] synchronize];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableDictionary *info = [NSMutableDictionary dictionary];
                if (error) {
                    info[PFPhotoServiceScanErrorKey] = error;
                    NSLog(@"[NASPhotoFrame] NAS scan failed: domain=%@ code=%ld description=%@", error.domain, (long)error.code, error.localizedDescription);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PFScanFailureRetryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self requestScan];
                    });
                }
                info[PFPhotoServicePhotoCountKey] = @(photos.count);
                [[NSNotificationCenter defaultCenter] postNotificationName:PFPhotoServiceScanDidFinishNotification object:self userInfo:info];
            });
        }
    });
}

- (void)photosWithCompletion:(void (^)(NSArray *))completion {
    dispatch_async(self.downloadQueue, ^{
        NSArray *photos = [self.index allPhotos];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(photos); });
    });
}

- (void)indexSummaryWithCompletion:(void (^)(NSDictionary *))completion {
    dispatch_async(self.downloadQueue, ^{
        NSDictionary *summary = [self.index summary];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(summary); });
    });
}

- (void)testConfiguration:(PFConfiguration *)configuration password:(NSString *)password completion:(void (^)(NSError *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        [self.client testConfiguration:configuration password:password error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
    });
}

- (void)loadImageForPhoto:(PFPhoto *)photo maximumPixelSize:(CGFloat)maximumPixelSize completion:(void (^)(UIImage *, NSDictionary *, NSError *))completion {
    PFConfiguration *configuration = self.configuration;
    dispatch_async(self.downloadQueue, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSString *localPath = photo.localPath;
            if (![self.cache isValidFileAtPath:localPath expectedSize:photo.fileSize]) {
                localPath = [self.cache destinationPathForRemotePath:photo.remotePath];
                if (![self.cache isValidFileAtPath:localPath expectedSize:photo.fileSize]) {
                    NSString *temporary = [localPath stringByAppendingString:@".part"];
                    [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
                    BOOL mayUseNetwork = [NSDate timeIntervalSinceReferenceDate] >= self.networkUnavailableUntil;
                    BOOL downloaded = NO;
                    if (mayUseNetwork) {
                        downloaded = [self.client downloadRemotePath:photo.remotePath configuration:configuration password:[PFCredentialStore password] destinationPath:temporary error:&error];
                        self.networkUnavailableUntil = downloaded ? 0 : [NSDate timeIntervalSinceReferenceDate] + 60.0;
                    } else {
                        error = [NSError errorWithDomain:@"PFPhotoService" code:2 userInfo:@{NSLocalizedDescriptionKey: PFL(@"error.nasTemporarilyUnavailable")}];
                    }
                    if (downloaded) {
                        [[NSFileManager defaultManager] removeItemAtPath:localPath error:nil];
                        if (![[NSFileManager defaultManager] moveItemAtPath:temporary toPath:localPath error:&error]) localPath = nil;
                    } else localPath = nil;
                }
                if (localPath) [self.index setLocalPath:localPath forRemotePath:photo.remotePath];
            }
            NSDictionary *metadata = nil;
            UIImage *image = localPath ? [PFImageDecoder screenImageAtPath:localPath maximumPixelSize:maximumPixelSize metadata:&metadata] : nil;
            if (image) {
                [self.cache touchPath:localPath];
                [self.index markPlayedRemotePath:photo.remotePath];
                [self.cache evictIfNeededPreservingPath:localPath];
            } else if (localPath) {
                [[NSFileManager defaultManager] removeItemAtPath:localPath error:nil];
                [self.index clearLocalPathForRemotePath:photo.remotePath];
                if (!error) error = [NSError errorWithDomain:@"PFImageDecoder" code:1 userInfo:@{NSLocalizedDescriptionKey: PFL(@"error.photoDecodeFailed")}];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(image, metadata, error); });
        }
    });
}

@end
