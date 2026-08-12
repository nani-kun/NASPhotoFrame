#import <UIKit/UIKit.h>
@class PFConfiguration, PFPhoto;

extern NSString * const PFPhotoServiceScanDidFinishNotification;
extern NSString * const PFPhotoServiceScanErrorKey;
extern NSString * const PFPhotoServicePhotoCountKey;

@interface PFPhotoService : NSObject
+ (instancetype)sharedService;
- (PFConfiguration *)configuration;
- (void)applyConfiguration:(PFConfiguration *)configuration;
- (void)start;
- (void)applicationDidBecomeActive;
- (void)requestScan;
- (void)photosWithCompletion:(void (^)(NSArray *photos))completion;
- (void)indexSummaryWithCompletion:(void (^)(NSDictionary *summary))completion;
- (void)testConfiguration:(PFConfiguration *)configuration password:(NSString *)password completion:(void (^)(NSError *error))completion;
- (void)loadImageForPhoto:(PFPhoto *)photo maximumPixelSize:(CGFloat)maximumPixelSize completion:(void (^)(UIImage *image, NSDictionary *metadata, NSError *error))completion;
@end
