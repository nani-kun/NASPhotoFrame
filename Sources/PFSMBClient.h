#import <Foundation/Foundation.h>
@class PFConfiguration;

@interface PFSMBClient : NSObject
- (BOOL)testConfiguration:(PFConfiguration *)configuration password:(NSString *)password error:(NSError **)error;
- (NSArray *)enumeratePhotosWithConfiguration:(PFConfiguration *)configuration password:(NSString *)password error:(NSError **)error;
- (BOOL)downloadRemotePath:(NSString *)remotePath configuration:(PFConfiguration *)configuration password:(NSString *)password destinationPath:(NSString *)destinationPath error:(NSError **)error;
@end
