#import <Foundation/Foundation.h>
@class PFPhoto;

@interface PFPhotoIndex : NSObject
- (instancetype)initWithDatabasePath:(NSString *)path;
- (BOOL)replaceRemoteSnapshot:(NSArray *)photos scanIdentifier:(NSString *)scanIdentifier error:(NSError **)error;
- (NSArray *)allPhotos;
- (NSDictionary *)summary;
- (void)setLocalPath:(NSString *)localPath forRemotePath:(NSString *)remotePath;
- (void)clearLocalPathForRemotePath:(NSString *)remotePath;
- (void)markPlayedRemotePath:(NSString *)remotePath;
@end
