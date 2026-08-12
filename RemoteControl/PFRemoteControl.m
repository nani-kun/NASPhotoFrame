#import <Foundation/Foundation.h>
#import "PFCredentialStore.h"

#include <errno.h>
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString * const kPFPreferencesPath = @"/var/mobile/Library/Preferences/com.wangxiaoxiang.nasphotoframe.plist";
static NSString * const kPFConfigurationKey = @"PFConfiguration";
static NSString * const kPFIndexPath = @"/var/mobile/Library/Application Support/photos.sqlite3";
static NSString * const kPFCachePath = @"/var/mobile/Library/Application Support/PhotoCache";
static NSString * const kPFAppInfoPath = @"/Applications/NASPhotoFrame.app/Info.plist";
static const NSTimeInterval kPFAppleReferenceToUnix = 978307200.0;

static void PFPrintJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    if (data != nil) {
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
    }
}

static NSMutableDictionary *PFPreferenceRoot(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:kPFPreferencesPath];
    return saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

static NSDictionary *PFPublicSettings(NSDictionary *saved) {
    NSNumber *swipe = saved[@"swipeNavigationEnabled"];
    NSNumber *pan = saved[@"photoPanEnabled"];
    NSNumber *kenBurns = saved[@"kenBurnsEnabled"];
    NSNumber *info = saved[@"photoInfoEnabled"];
    double scanInterval = [saved[@"scanInterval"] doubleValue];
    double slideDuration = [saved[@"slideDuration"] doubleValue];
    unsigned long long cacheBytes = [saved[@"cacheLimitBytes"] unsignedLongLongValue];
    return @{
        @"host": saved[@"host"] ?: @"",
        @"share": saved[@"share"] ?: @"",
        @"rootPath": saved[@"rootPath"] ?: @"",
        @"username": saved[@"username"] ?: @"",
        @"domain": saved[@"domain"] ?: @"",
        @"scanIntervalHours": @((scanInterval > 0.0 ? scanInterval : 10800.0) / 3600.0),
        @"slideDuration": @(slideDuration > 0.0 ? slideDuration : 20.0),
        @"cacheLimitGB": @((cacheBytes > 0 ? cacheBytes : 1073741824ULL) / 1073741824.0),
        @"playbackMode": @([saved[@"playbackMode"] integerValue]),
        @"swipeNavigationEnabled": swipe ?: @YES,
        @"photoPanEnabled": pan ?: @YES,
        @"kenBurnsEnabled": kenBurns ?: @NO,
        @"photoInfoEnabled": info ?: @YES,
        @"passwordConfigured": @([PFCredentialStore password].length > 0)
    };
}

static NSDictionary *PFClientInfo(void) {
    NSDictionary *root = PFPreferenceRoot();
    NSDictionary *configuration = [root objectForKey:kPFConfigurationKey] ?: @{};
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    sqlite3 *database = NULL;
    NSUInteger indexedCount = 0;
    NSUInteger cachedIndexedCount = 0;
    NSTimeInterval earliest = 0;
    NSTimeInterval latest = 0;
    if (sqlite3_open_v2([kPFIndexPath fileSystemRepresentation], &database,
                        SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        sqlite3_busy_timeout(database, 3000);
        sqlite3_stmt *statement = NULL;
        const char *sql = "SELECT COUNT(*),MIN(NULLIF(btime,0)),MAX(NULLIF(btime,0)),SUM(CASE WHEN local_path IS NOT NULL THEN 1 ELSE 0 END) FROM photos";
        if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) == SQLITE_OK &&
            sqlite3_step(statement) == SQLITE_ROW) {
            indexedCount = (NSUInteger)sqlite3_column_int64(statement, 0);
            earliest = sqlite3_column_double(statement, 1);
            latest = sqlite3_column_double(statement, 2);
            cachedIndexedCount = (NSUInteger)sqlite3_column_int64(statement, 3);
        }
        sqlite3_finalize(statement);
        sqlite3_close(database);
    }
    [info setObject:@(indexedCount) forKey:@"indexedCount"];
    [info setObject:@(cachedIndexedCount) forKey:@"cachedIndexedCount"];
    [info setObject:@(earliest) forKey:@"earliestTime"];
    [info setObject:@(latest) forKey:@"latestTime"];

    NSNumber *lastPhotoCount = [root objectForKey:@"PFLastSuccessfulPhotoCount"];
    [info setObject:lastPhotoCount ?: @(indexedCount) forKey:@"nasPhotoCount"];
    NSTimeInterval lastScanReference = [[root objectForKey:@"PFLastSuccessfulScan"] doubleValue];
    NSTimeInterval lastScanUnix = lastScanReference > 0
        ? lastScanReference + kPFAppleReferenceToUnix : 0;
    [info setObject:@(lastScanUnix) forKey:@"lastSuccessfulScan"];
    double scanInterval = [[configuration objectForKey:@"scanInterval"] doubleValue];
    if (lastScanUnix > 0) {
        [info setObject:@(lastScanUnix + MAX(scanInterval, 900.0)) forKey:@"nextScheduledScan"];
    } else {
        [info setObject:@0 forKey:@"nextScheduledScan"];
    }
    NSTimeInterval lastAttemptReference = [[root objectForKey:@"PFLastScanAttempt"] doubleValue];
    [info setObject:@(lastAttemptReference > 0
        ? lastAttemptReference + kPFAppleReferenceToUnix : 0) forKey:@"lastScanAttempt"];
    [info setObject:[root objectForKey:@"PFLastScanError"] ?: @"" forKey:@"lastScanError"];

    unsigned long long cacheBytes = 0;
    NSUInteger cacheFileCount = 0;
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *name in [manager contentsOfDirectoryAtPath:kPFCachePath error:NULL]) {
        if ([name hasSuffix:@".part"]) continue;
        NSString *path = [kPFCachePath stringByAppendingPathComponent:name];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        if ([[attributes objectForKey:NSFileType] isEqual:NSFileTypeRegular]) {
            cacheBytes += [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
            cacheFileCount++;
        }
    }
    [info setObject:@(cacheBytes) forKey:@"cacheBytes"];
    [info setObject:@(cacheFileCount) forKey:@"cacheFileCount"];
    [info setObject:[configuration objectForKey:@"cacheLimitBytes"] ?: @(1073741824ULL)
              forKey:@"cacheLimitBytes"];

    NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:kPFAppInfoPath];
    [info setObject:[appInfo objectForKey:@"CFBundleShortVersionString"] ?: @""
              forKey:@"clientVersion"];
    [info setObject:[appInfo objectForKey:@"CFBundleVersion"] ?: @""
              forKey:@"clientBuild"];
    [info setObject:[configuration objectForKey:@"host"] ?: @"" forKey:@"host"];
    [info setObject:[configuration objectForKey:@"share"] ?: @"" forKey:@"share"];
    [info setObject:[configuration objectForKey:@"rootPath"] ?: @"" forKey:@"rootPath"];
    return info;
}

static NSString *PFString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL PFWriteSettings(NSDictionary *input, NSError **error) {
    NSString *host = [PFString(input[@"host"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *share = [PFString(input[@"share"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *username = [PFString(input[@"username"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (host.length == 0 || share.length == 0 || username.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"PFRemoteControl" code:1 userInfo:@{NSLocalizedDescriptionKey: @"NAS 服务器、共享名和用户名不能为空"}];
        return NO;
    }

    double scanHours = MAX([input[@"scanIntervalHours"] doubleValue], 0.25);
    double slideDuration = MAX([input[@"slideDuration"] doubleValue], 3.0);
    double cacheGB = MAX([input[@"cacheLimitGB"] doubleValue], 0.1);
    NSDictionary *configuration = @{
        @"host": host,
        @"share": share,
        @"rootPath": PFString(input[@"rootPath"]),
        @"username": username,
        @"domain": PFString(input[@"domain"]),
        @"scanInterval": @(scanHours * 3600.0),
        @"slideDuration": @(slideDuration),
        @"cacheLimitBytes": @((unsigned long long)(cacheGB * 1073741824.0)),
        @"playbackMode": @([input[@"playbackMode"] integerValue] == 1 ? 1 : 0),
        @"swipeNavigationEnabled": @([input[@"swipeNavigationEnabled"] boolValue]),
        @"photoPanEnabled": @([input[@"photoPanEnabled"] boolValue]),
        @"kenBurnsEnabled": @([input[@"kenBurnsEnabled"] boolValue]),
        @"photoInfoEnabled": @([input[@"photoInfoEnabled"] boolValue])
    };

    NSString *password = [input[@"password"] isKindOfClass:[NSString class]] ? input[@"password"] : nil;
    if (password.length > 0 && ![PFCredentialStore savePassword:password error:error]) {
        return NO;
    }

    NSMutableDictionary *root = PFPreferenceRoot();
    root[kPFConfigurationKey] = configuration;
    if (![root writeToFile:kPFPreferencesPath atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno ?: EIO userInfo:@{NSLocalizedDescriptionKey: @"无法写入相框设置文件"}];
        return NO;
    }
    chmod(kPFPreferencesPath.fileSystemRepresentation, 0600);
    chown(kPFPreferencesPath.fileSystemRepresentation, 501, 501);
    return YES;
}

static void PFUsage(const char *program) {
    fprintf(stderr, "Usage: %s get-settings|get-client-info|set-settings <base64-json>\n", program);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "get-settings") == 0) {
            NSDictionary *configuration = PFPreferenceRoot()[kPFConfigurationKey];
            PFPrintJSON(@{@"ok": @YES, @"settings": PFPublicSettings(configuration ?: @{})});
            return 0;
        }
        if (argc == 2 && strcmp(argv[1], "get-client-info") == 0) {
            PFPrintJSON(@{@"ok": @YES, @"client": PFClientInfo()});
            return 0;
        }
        if (argc == 3 && strcmp(argv[1], "set-settings") == 0) {
            NSString *encoded = [NSString stringWithUTF8String:argv[2]];
            NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            NSError *error = nil;
            id input = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
            if (![input isKindOfClass:[NSDictionary class]]) {
                PFPrintJSON(@{@"ok": @NO, @"error": error.localizedDescription ?: @"设置数据无效"});
                return 2;
            }
            if (!PFWriteSettings(input, &error)) {
                PFPrintJSON(@{@"ok": @NO, @"error": error.localizedDescription ?: @"保存失败"});
                return 1;
            }
            PFPrintJSON(@{@"ok": @YES});
            return 0;
        }
        PFUsage(argv[0]);
        return 2;
    }
}
