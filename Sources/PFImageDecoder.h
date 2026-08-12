#import <UIKit/UIKit.h>

@interface PFImageDecoder : NSObject
+ (UIImage *)screenImageAtPath:(NSString *)path
             maximumPixelSize:(CGFloat)maximumPixelSize
                      metadata:(NSDictionary **)metadata;
@end
