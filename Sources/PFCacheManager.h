#import <Foundation/Foundation.h>

@interface PFCacheManager : NSObject
- (instancetype)initWithDirectory:(NSString *)directory limitBytes:(unsigned long long)limitBytes;
@property (nonatomic) unsigned long long limitBytes;
- (NSString *)destinationPathForRemotePath:(NSString *)remotePath;
- (BOOL)isValidFileAtPath:(NSString *)path expectedSize:(uint64_t)expectedSize;
- (void)touchPath:(NSString *)path;
- (void)removeFilesExceptPaths:(NSSet *)preservedPaths;
- (void)evictIfNeededPreservingPath:(NSString *)preservedPath;
@end
