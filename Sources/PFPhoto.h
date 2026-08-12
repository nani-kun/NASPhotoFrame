#import <Foundation/Foundation.h>

@interface PFPhoto : NSObject
@property (nonatomic, copy) NSString *remotePath;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic) uint64_t fileSize;
@property (nonatomic) NSTimeInterval modificationTime;
@property (nonatomic) NSTimeInterval creationTime;
@property (nonatomic, copy) NSString *localPath;
@end
