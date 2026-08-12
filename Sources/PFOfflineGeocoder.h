#import <Foundation/Foundation.h>

@interface PFOfflineGeocoder : NSObject
+ (void)nearestCityForLatitude:(double)latitude
                    longitude:(double)longitude
                    completion:(void (^)(NSString *location))completion;
@end
