#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "PFOfflineGeocoder.h"
#import "PFLocationUtilities.h"

@interface PFOfflineGeocoder (Tests)
+ (NSString *)nearestCityInDatabase:(sqlite3 *)database latitude:(double)latitude longitude:(double)longitude;
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
    ++checks;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static sqlite3 *Fixture(void) {
    sqlite3 *db = NULL;
    Check(sqlite3_open(":memory:", &db) == SQLITE_OK, @"Open fixture");
    Check(sqlite3_exec(db, "CREATE TABLE cities (name TEXT, admin1_name TEXT, country_code TEXT, latitude REAL, longitude REAL)", NULL, NULL, NULL) == SQLITE_OK, @"Create fixture");
    return db;
}

static void Add(sqlite3 *db, NSString *name, double latitude, double longitude) {
    sqlite3_stmt *stmt = NULL;
    Check(sqlite3_prepare_v2(db, "INSERT INTO cities VALUES (?, '', '', ?, ?)", -1, &stmt, NULL) == SQLITE_OK, @"Prepare fixture row");
    sqlite3_bind_text(stmt, 1, name.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 2, latitude);
    sqlite3_bind_double(stmt, 3, longitude);
    Check(sqlite3_step(stmt) == SQLITE_DONE, @"Insert fixture row");
    sqlite3_finalize(stmt);
}

static NSString *Resolve(sqlite3 *db, double latitude, double longitude) {
    return [PFOfflineGeocoder nearestCityInDatabase:db latitude:latitude longitude:longitude];
}

static BOOL Names(sqlite3 *db, double latitude, double longitude, NSString *name) {
    NSString *result = Resolve(db, latitude, longitude);
    return result && [result rangeOfString:name].location != NSNotFound;
}

// Independent spherical distance reference using 3D vectors and atan2.
static double Distance(double lat1, double lon1, double lat2, double lon2) {
    lat1 *= M_PI / 180.0; lon1 *= M_PI / 180.0;
    lat2 *= M_PI / 180.0; lon2 *= M_PI / 180.0;
    double a[] = {cos(lat1)*cos(lon1), cos(lat1)*sin(lon1), sin(lat1)};
    double b[] = {cos(lat2)*cos(lon2), cos(lat2)*sin(lon2), sin(lat2)};
    double x = a[1]*b[2] - a[2]*b[1];
    double y = a[2]*b[0] - a[0]*b[2];
    double z = a[0]*b[1] - a[1]*b[0];
    return 6371.0088 * atan2(sqrt(x*x + y*y + z*z), a[0]*b[0] + a[1]*b[1] + a[2]*b[2]);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc >= 2, @"Supply bundled database path");
        NSString *a = PFLocationCacheKey(31.228, 121.431, @"offline", @"zh-Hans");
        NSString *b = PFLocationCacheKey(31.233, 121.428, @"offline", @"zh-Hans");
        Check(![a isEqualToString:b], @"Shanghai regression: neighbouring photos must not share cached names");
        Check(![a isEqualToString:PFLocationCacheKey(31.2280000001, 121.431, @"offline", @"zh-Hans")], @"Preserve fine coordinate differences");
        Check([PFLocationCacheKey(0.0, 0.0, @"offline", @"en") isEqualToString:PFLocationCacheKey(-0.0, -0.0, @"offline", @"en")], @"Canonical zero cache key");
        Check(![a isEqualToString:PFLocationCacheKey(31.228, 121.431, @"online", @"zh-Hans")], @"Isolate resolver caches");
        Check(![a isEqualToString:PFLocationCacheKey(31.228, 121.431, @"offline", @"en")], @"Isolate language caches");
        Check([a hasPrefix:@"v4:"], @"Invalidate old rounded caches");
        Check(!PFLocationCacheKey(NAN, 0, @"offline", @"en"), @"Reject invalid cache coordinates");

        sqlite3 *db = Fixture();
        Check(!Resolve(db, 0, 0), @"Empty database falls back to coordinates");
        Add(db, @"FartherInsideOldBox", 80.3, 0.99);
        Add(db, @"CloserOutsideOldBox", 80.0, 1.01);
        Check(Names(db, 80, 0, @"CloserOutsideOldBox"), @"Do not stop at first occupied box");
        sqlite3_close(db);

        db = Fixture();
        Add(db, @"AcrossDateLine", 0, -179.9);
        Add(db, @"SameSideFarther", 0, 179.5);
        Check(Names(db, 0, 179.9, @"AcrossDateLine"), @"Wrap east across date line");
        Check(Names(db, 0, -180, @"AcrossDateLine"), @"Accept west date line endpoint");
        Check(Names(db, 0, 180, @"AcrossDateLine"), @"Accept east date line endpoint");
        sqlite3_close(db);

        db = Fixture();
        Add(db, @"AcrossNorthPole", 89.99, 180);
        Add(db, @"FartherNorth", 89.9, 0);
        Add(db, @"AcrossSouthPole", -89.99, 180);
        Check(Names(db, 89.99, 0, @"AcrossNorthPole"), @"Nearest across north pole");
        Check(Names(db, -89.99, 0, @"AcrossSouthPole"), @"Nearest across south pole");
        sqlite3_close(db);

        db = Fixture();
        Add(db, @"TooFar", 50.1 / 6371.0088 * 180 / M_PI, 0);
        Check(!Resolve(db, 0, 0), @"Reject place beyond 50 km");
        Add(db, @"WithinLimit", 49.9 / 6371.0088 * 180 / M_PI, 0);
        Check(Names(db, 0, 0, @"WithinLimit"), @"Accept place within 50 km");
        Check(!Resolve(db, NAN, 0) && !Resolve(db, 0, INFINITY) && !Resolve(db, 91, 0) && !Resolve(db, 0, -181), @"Reject non-finite and out-of-range coordinates");
        Check(!Resolve(NULL, 0, 0), @"Missing database falls back to coordinates");
        NSString *nearby = Resolve(db, 0, 0);
        Check([nearby hasPrefix:@"附近："] || [nearby hasPrefix:@"Nearby: "], @"Label approximate results as nearby");
        sqlite3_close(db);

        Check(sqlite3_open_v2(argv[1], &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK, @"Open bundled database");
        Check(Names(db, 31.228, 121.431, @"长宁"), @"Shanghai first coordinate");
        Check(Names(db, 31.233, 121.428, @"静安"), @"Shanghai second coordinate");
        Check(!Resolve(db, 0, -30), @"Atlantic regression: do not display distant Brazilian city");
        Check(!Resolve(db, 36.5434, 110.5255), @"Reject both distant cities in old early-exit regression");
        Check(Names(db, 30.2741, 120.1551, @"杭州"), @"Keep ordinary city results");

        sqlite3_stmt *stmt = NULL;
        Check(sqlite3_prepare_v2(db, "SELECT name,latitude,longitude FROM cities ORDER BY geoname_id", -1, &stmt, NULL) == SQLITE_OK, @"Load independent reference");
        NSMutableArray *cities = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [cities addObject:@[[NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)], @(sqlite3_column_double(stmt, 1)), @(sqlite3_column_double(stmt, 2))]];
        }
        sqlite3_finalize(stmt);
        // Compare against an exhaustive scan, both on land and in sparse areas.
        for (NSUInteger i = 0; i < 150; ++i) {
            NSArray *city = cities[(i * 227) % cities.count];
            double lat = i % 2 ? [city[1] doubleValue] + 0.1 : -89.0 + fmod(i * 37.19, 178.0);
            double lon = i % 2 ? [city[2] doubleValue] : -180.0 + fmod(i * 79.13, 360.0);
            double bestDistance = 50.0;
            NSString *best = nil;
            for (NSArray *candidate in cities) {
                double distance = Distance(lat, lon, [candidate[1] doubleValue], [candidate[2] doubleValue]);
                if (distance < bestDistance) { bestDistance = distance; best = candidate[0]; }
            }
            NSString *actual = Resolve(db, lat, lon);
            Check(best ? actual && [actual rangeOfString:best].location != NSNotFound : !actual,
                  [NSString stringWithFormat:@"Exhaustive reference at %.6f,%.6f expected %@ got %@", lat, lon, best, actual]);
        }
        sqlite3_close(db);
        printf("PASS: %lu geocoder checks\n", (unsigned long)checks);
    }
    return 0;
}
