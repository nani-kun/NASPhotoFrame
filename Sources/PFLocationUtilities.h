#import <Foundation/Foundation.h>
#include <math.h>

// GPS/GeoNames coordinates are decimal degrees in WGS84.
static inline BOOL PFCoordinateIsValid(double latitude, double longitude) {
    return isfinite(latitude) && isfinite(longitude) &&
           latitude >= -90.0 && latitude <= 90.0 &&
           longitude >= -180.0 && longitude <= 180.0;
}

static inline NSString *PFLocationCacheKey(double latitude, double longitude,
                                         NSString *resolver, NSString *language) {
    if (!PFCoordinateIsValid(latitude, longitude)) return nil;
    // 17 significant digits preserve the original double instead of sharing a
    // kilometre-sized rounded cell. Version and resolver isolate older results.
    return [NSString stringWithFormat:@"v4:%@:%@:%.17g,%.17g", resolver, language,
            latitude == 0.0 ? 0.0 : latitude, longitude == 0.0 ? 0.0 : longitude];
}
