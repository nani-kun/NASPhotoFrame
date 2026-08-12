#import "PFCacheManager.h"

@interface PFCacheEntry : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) unsigned long long size;
@property (nonatomic, strong) NSDate *date;
@end
@implementation PFCacheEntry @end

@interface PFCacheManager ()
@property (nonatomic, copy) NSString *directory;
@end

@implementation PFCacheManager

- (instancetype)initWithDirectory:(NSString *)directory limitBytes:(unsigned long long)limitBytes {
    self = [super init];
    if (self) {
        _directory = [directory copy];
        _limitBytes = limitBytes;
        [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (NSString *)destinationPathForRemotePath:(NSString *)remotePath {
    const char *bytes = remotePath.UTF8String;
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger i = 0; bytes && bytes[i]; i++) { hash ^= (uint8_t)bytes[i]; hash *= 1099511628211ULL; }
    NSString *extension = remotePath.pathExtension.lowercaseString;
    if (!extension.length || extension.length > 5) extension = @"img";
    return [self.directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%016llx.%@", hash, extension]];
}

- (BOOL)isValidFileAtPath:(NSString *)path expectedSize:(uint64_t)expectedSize {
    if (!path.length) return NO;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attributes) return NO;
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    return size > 0 && (expectedSize == 0 || size == expectedSize);
}

- (void)touchPath:(NSString *)path {
    if (!path.length) return;
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: [NSDate date]} ofItemAtPath:path error:nil];
}

- (void)removeFilesExceptPaths:(NSSet *)preservedPaths {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *names = [manager contentsOfDirectoryAtPath:self.directory error:nil];
    for (NSString *name in names) {
        NSString *path = [self.directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
        if ([attributes[NSFileType] isEqual:NSFileTypeRegular] && ![preservedPaths containsObject:path]) {
            [manager removeItemAtPath:path error:nil];
        }
    }
}

- (void)evictIfNeededPreservingPath:(NSString *)preservedPath {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.directory error:nil];
    NSMutableArray *entries = [NSMutableArray array];
    unsigned long long total = 0;
    for (NSString *name in names) {
        if ([name hasSuffix:@".part"]) continue;
        NSString *path = [self.directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        if ([attributes[NSFileType] isEqual:NSFileTypeRegular]) {
            PFCacheEntry *entry = [[PFCacheEntry alloc] init];
            entry.path = path;
            entry.size = [attributes[NSFileSize] unsignedLongLongValue];
            entry.date = attributes[NSFileModificationDate] ?: [NSDate distantPast];
            total += entry.size;
            [entries addObject:entry];
        }
    }
    if (total <= self.limitBytes) return;
    [entries sortUsingComparator:^NSComparisonResult(PFCacheEntry *a, PFCacheEntry *b) { return [a.date compare:b.date]; }];
    for (PFCacheEntry *entry in entries) {
        if (total <= self.limitBytes) break;
        if ([entry.path isEqualToString:preservedPath]) continue;
        if ([[NSFileManager defaultManager] removeItemAtPath:entry.path error:nil]) total -= entry.size;
    }
}

@end
