#import "PFOfflineGeocoder.h"
#import "PFLocalization.h"
#import <sqlite3.h>
#include <math.h>
#import "PFLocationUtilities.h"

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
        if (path.length && sqlite3_open_v2(path.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
            sqlite3_close(database);
            database = NULL;
        }
    });
    dispatch_async(queue, ^{
        NSString *result = database ? [self nearestCityInDatabase:database latitude:latitude longitude:longitude] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); });
    });
}

+ (NSString *)nearestCityInDatabase:(sqlite3 *)database latitude:(double)latitude longitude:(double)longitude {
    if (!database || !PFCoordinateIsValid(latitude, longitude)) return nil;

    // A city point is only an approximation, not an administrative boundary.
    // Beyond 50 km, let the caller display the original coordinates instead.
    static const double earthRadiusKilometres = 6371.0088;
    static const double maximumDistanceKilometres = 50.0;
    double angularRadius = maximumDistanceKilometres / earthRadiusKilometres;
    double latitudeSpan = angularRadius * 180.0 / M_PI;
    double latitudeRadians = latitude * M_PI / 180.0;
    double bestDistance = pow(sin(angularRadius / 2.0), 2.0);
    NSString *bestName = nil;
    NSString *bestAdministrativeArea = nil;
    NSString *bestCountryCode = nil;

    // Every point within the distance limit lies in this latitude band. Scan
    // the complete band using its index, so an occupied smaller box cannot
    // hide a closer city. Haversine also handles poles and the date line.
    sqlite3_stmt *statement = NULL;
    const char *sql = "SELECT name,admin1_name,country_code,latitude,longitude FROM cities WHERE latitude BETWEEN ? AND ?";
    if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) return nil;
    sqlite3_bind_double(statement, 1, MAX(latitude - latitudeSpan, -90.0));
    sqlite3_bind_double(statement, 2, MIN(latitude + latitudeSpan, 90.0));
    int stepResult;
    while ((stepResult = sqlite3_step(statement)) == SQLITE_ROW) {
        double cityLatitude = sqlite3_column_double(statement, 3);
        double cityLongitude = sqlite3_column_double(statement, 4);
        if (!PFCoordinateIsValid(cityLatitude, cityLongitude)) continue;
        double cityLatitudeRadians = cityLatitude * M_PI / 180.0;
        double latitudeDelta = (cityLatitude - latitude) * M_PI / 180.0;
        double longitudeDelta = remainder(cityLongitude - longitude, 360.0) * M_PI / 180.0;
        double latitudeSine = sin(latitudeDelta / 2.0);
        double longitudeSine = sin(longitudeDelta / 2.0);
        double distance = latitudeSine * latitudeSine + cos(latitudeRadians) *
                          cos(cityLatitudeRadians) * longitudeSine * longitudeSine;
        if (distance > bestDistance) continue;
        const unsigned char *name = sqlite3_column_text(statement, 0);
        NSString *candidateName = name ? [NSString stringWithUTF8String:(const char *)name] : nil;
        if (!candidateName.length) continue;
        bestDistance = distance;
        bestName = candidateName;
        const unsigned char *administrativeArea = sqlite3_column_text(statement, 1);
        const unsigned char *country = sqlite3_column_text(statement, 2);
        bestAdministrativeArea = administrativeArea ? [NSString stringWithUTF8String:(const char *)administrativeArea] : nil;
        bestCountryCode = country ? [NSString stringWithUTF8String:(const char *)country] : nil;
    }
    sqlite3_finalize(statement);
    if (stepResult != SQLITE_DONE || !bestName.length) return nil;
    NSLocale *locale = PFLocalizationLocale();
    NSString *countryName = bestCountryCode.length ? [locale displayNameForKey:NSLocaleCountryCode value:bestCountryCode] : nil;
    NSMutableArray *parts = [NSMutableArray arrayWithObject:bestName];
    if (bestAdministrativeArea.length && ![parts containsObject:bestAdministrativeArea]) {
        [parts addObject:bestAdministrativeArea];
    }
    if (countryName.length && ![parts containsObject:countryName]) [parts addObject:countryName];
    return [NSString stringWithFormat:PFL(@"location.nearby"), [parts componentsJoinedByString:@" · "]];
}

@end
