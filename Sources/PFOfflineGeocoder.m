#import "PFOfflineGeocoder.h"
#import <sqlite3.h>
#include <math.h>
#include <float.h>

@interface PFOfflineGeocoder ()
+ (NSString *)nearestCityInDatabase:(sqlite3 *)database latitude:(double)latitude longitude:(double)longitude;
@end

@implementation PFOfflineGeocoder

+ (void)nearestCityForLatitude:(double)latitude
                    longitude:(double)longitude
                    completion:(void (^)(NSString *))completion {
    static dispatch_queue_t queue;
    static sqlite3 *database = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.wangxiaoxiang.nasphotoframe.offline-geocoder", DISPATCH_QUEUE_SERIAL);
        NSString *path = [[NSBundle mainBundle] pathForResource:@"GeoNamesCities" ofType:@"sqlite3"];
        if (path.length) sqlite3_open_v2(path.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY, NULL);
    });
    dispatch_async(queue, ^{
        NSString *result = database ? [self nearestCityInDatabase:database latitude:latitude longitude:longitude] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); });
    });
}

+ (NSString *)nearestCityInDatabase:(sqlite3 *)database latitude:(double)latitude longitude:(double)longitude {
    static const double spans[] = {1.0, 3.0, 10.0, 180.0};
    NSString *bestName = nil;
    NSString *bestAdministrativeArea = nil;
    NSString *bestCountryCode = nil;
    double bestDistance = DBL_MAX;
    double longitudeScale = cos(latitude * M_PI / 180.0);
    longitudeScale *= longitudeScale;

    for (NSUInteger spanIndex = 0; spanIndex < sizeof(spans) / sizeof(spans[0]); spanIndex++) {
        double span = spans[spanIndex];
        sqlite3_stmt *statement = NULL;
        const char *sql = "SELECT name,admin1_name,country_code,latitude,longitude FROM cities WHERE latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?";
        if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) continue;
        sqlite3_bind_double(statement, 1, MAX(latitude - span, -90.0));
        sqlite3_bind_double(statement, 2, MIN(latitude + span, 90.0));
        sqlite3_bind_double(statement, 3, MAX(longitude - span, -180.0));
        sqlite3_bind_double(statement, 4, MIN(longitude + span, 180.0));
        while (sqlite3_step(statement) == SQLITE_ROW) {
            double cityLatitude = sqlite3_column_double(statement, 3);
            double cityLongitude = sqlite3_column_double(statement, 4);
            double latitudeDelta = cityLatitude - latitude;
            double longitudeDelta = cityLongitude - longitude;
            double distance = latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta * longitudeScale;
            if (distance >= bestDistance) continue;
            bestDistance = distance;
            const unsigned char *name = sqlite3_column_text(statement, 0);
            const unsigned char *administrativeArea = sqlite3_column_text(statement, 1);
            const unsigned char *country = sqlite3_column_text(statement, 2);
            bestName = name ? [NSString stringWithUTF8String:(const char *)name] : nil;
            bestAdministrativeArea = administrativeArea ? [NSString stringWithUTF8String:(const char *)administrativeArea] : nil;
            bestCountryCode = country ? [NSString stringWithUTF8String:(const char *)country] : nil;
        }
        sqlite3_finalize(statement);
        if (bestName.length) break;
    }
    if (!bestName.length) return nil;
    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];
    NSString *countryName = bestCountryCode.length ? [locale displayNameForKey:NSLocaleCountryCode value:bestCountryCode] : nil;
    NSMutableArray *parts = [NSMutableArray arrayWithObject:bestName];
    if (bestAdministrativeArea.length && ![parts containsObject:bestAdministrativeArea]) {
        [parts addObject:bestAdministrativeArea];
    }
    if (countryName.length && ![parts containsObject:countryName]) [parts addObject:countryName];
    return [parts componentsJoinedByString:@" · "];
}

@end
