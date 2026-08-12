#import "PFPhotoIndex.h"
#import "PFPhoto.h"
#import <sqlite3.h>

static NSString * const PFIndexErrorDomain = @"PFPhotoIndexErrorDomain";

@interface PFPhotoIndex () {
    sqlite3 *_database;
    dispatch_queue_t _queue;
}
@property (nonatomic, copy) NSString *path;
@end

@implementation PFPhotoIndex

- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = [path copy];
        _queue = dispatch_queue_create("com.wangxiaoxiang.nasphotoframe.index", DISPATCH_QUEUE_SERIAL);
        dispatch_sync(_queue, ^{ [self openDatabase]; });
    }
    return self;
}

- (void)dealloc {
    if (_database) sqlite3_close(_database);
}

- (void)openDatabase {
    if (sqlite3_open([self.path fileSystemRepresentation], &_database) != SQLITE_OK) return;
    sqlite3_busy_timeout(_database, 3000);
    sqlite3_exec(_database, "PRAGMA journal_mode=WAL", NULL, NULL, NULL);
    sqlite3_exec(_database, "PRAGMA synchronous=NORMAL", NULL, NULL, NULL);
    const char *schema =
        "CREATE TABLE IF NOT EXISTS photos ("
        "remote_path TEXT PRIMARY KEY NOT NULL, file_name TEXT NOT NULL,"
        "file_size INTEGER NOT NULL, mtime REAL NOT NULL, btime REAL NOT NULL DEFAULT 0, local_path TEXT,"
        "last_seen_scan TEXT, last_played REAL NOT NULL DEFAULT 0);"
        "CREATE INDEX IF NOT EXISTS photos_seen ON photos(last_seen_scan);"
        "CREATE INDEX IF NOT EXISTS photos_path ON photos(remote_path);";
    sqlite3_exec(_database, schema, NULL, NULL, NULL);
    // Existing installations predate the SMB creation-time column. SQLite
    // returns an error when the column already exists, which is safe to ignore.
    sqlite3_exec(_database, "ALTER TABLE photos ADD COLUMN btime REAL NOT NULL DEFAULT 0", NULL, NULL, NULL);
}

- (BOOL)replaceRemoteSnapshot:(NSArray *)photos scanIdentifier:(NSString *)scanIdentifier error:(NSError **)error {
    __block BOOL success = YES;
    __block NSString *message = nil;
    dispatch_sync(_queue, ^{
        if (!self->_database) { success = NO; message = @"无法打开照片索引"; return; }
        sqlite3_exec(self->_database, "BEGIN IMMEDIATE", NULL, NULL, NULL);
        const char *insertSQL = "INSERT OR IGNORE INTO photos(remote_path,file_name,file_size,mtime,btime,last_seen_scan) VALUES(?,?,?,?,?,?)";
        const char *updateSQL = "UPDATE photos SET file_name=?, local_path=CASE WHEN file_size<>? OR mtime<>? THEN NULL ELSE local_path END, file_size=?, mtime=?, btime=?, last_seen_scan=? WHERE remote_path=?";
        sqlite3_stmt *insert = NULL;
        sqlite3_stmt *update = NULL;
        if (sqlite3_prepare_v2(self->_database, insertSQL, -1, &insert, NULL) != SQLITE_OK ||
            sqlite3_prepare_v2(self->_database, updateSQL, -1, &update, NULL) != SQLITE_OK) {
            success = NO;
        }
        for (PFPhoto *photo in photos) {
            if (!success) break;
            sqlite3_bind_text(insert, 1, photo.remotePath.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(insert, 2, photo.fileName.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(insert, 3, (sqlite3_int64)photo.fileSize);
            sqlite3_bind_double(insert, 4, photo.modificationTime);
            sqlite3_bind_double(insert, 5, photo.creationTime);
            sqlite3_bind_text(insert, 6, scanIdentifier.UTF8String, -1, SQLITE_TRANSIENT);
            success = sqlite3_step(insert) == SQLITE_DONE;
            sqlite3_reset(insert); sqlite3_clear_bindings(insert);

            sqlite3_bind_text(update, 1, photo.fileName.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(update, 2, (sqlite3_int64)photo.fileSize);
            sqlite3_bind_double(update, 3, photo.modificationTime);
            sqlite3_bind_int64(update, 4, (sqlite3_int64)photo.fileSize);
            sqlite3_bind_double(update, 5, photo.modificationTime);
            sqlite3_bind_double(update, 6, photo.creationTime);
            sqlite3_bind_text(update, 7, scanIdentifier.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(update, 8, photo.remotePath.UTF8String, -1, SQLITE_TRANSIENT);
            success = success && sqlite3_step(update) == SQLITE_DONE;
            sqlite3_reset(update); sqlite3_clear_bindings(update);
        }
        sqlite3_finalize(insert);
        sqlite3_finalize(update);
        if (success) {
            sqlite3_stmt *prune = NULL;
            sqlite3_prepare_v2(self->_database, "DELETE FROM photos WHERE last_seen_scan IS NULL OR last_seen_scan<>?", -1, &prune, NULL);
            sqlite3_bind_text(prune, 1, scanIdentifier.UTF8String, -1, SQLITE_TRANSIENT);
            success = sqlite3_step(prune) == SQLITE_DONE;
            sqlite3_finalize(prune);
        }
        if (success) sqlite3_exec(self->_database, "COMMIT", NULL, NULL, NULL);
        else {
            message = self->_database ? [NSString stringWithUTF8String:sqlite3_errmsg(self->_database)] : @"索引未打开";
            sqlite3_exec(self->_database, "ROLLBACK", NULL, NULL, NULL);
        }
    });
    if (!success && error) *error = [NSError errorWithDomain:PFIndexErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message ?: @"更新索引失败"}];
    return success;
}

- (NSArray *)allPhotos {
    __block NSMutableArray *photos = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        sqlite3_stmt *statement = NULL;
        const char *sql = "SELECT remote_path,file_name,file_size,mtime,btime,local_path FROM photos ORDER BY remote_path COLLATE NOCASE";
        if (sqlite3_prepare_v2(self->_database, sql, -1, &statement, NULL) != SQLITE_OK) return;
        while (sqlite3_step(statement) == SQLITE_ROW) {
            PFPhoto *photo = [[PFPhoto alloc] init];
            const unsigned char *remote = sqlite3_column_text(statement, 0);
            const unsigned char *name = sqlite3_column_text(statement, 1);
            const unsigned char *local = sqlite3_column_text(statement, 5);
            photo.remotePath = remote ? [NSString stringWithUTF8String:(const char *)remote] : @"";
            photo.fileName = name ? [NSString stringWithUTF8String:(const char *)name] : @"";
            photo.fileSize = (uint64_t)sqlite3_column_int64(statement, 2);
            photo.modificationTime = sqlite3_column_double(statement, 3);
            photo.creationTime = sqlite3_column_double(statement, 4);
            photo.localPath = local ? [NSString stringWithUTF8String:(const char *)local] : nil;
            [photos addObject:photo];
        }
        sqlite3_finalize(statement);
    });
    return photos;
}

- (NSDictionary *)summary {
    __block NSUInteger count = 0;
    __block NSTimeInterval earliestTime = 0;
    __block NSTimeInterval latestTime = 0;
    dispatch_sync(_queue, ^{
        sqlite3_stmt *statement = NULL;
        const char *sql = "SELECT COUNT(*),MIN(NULLIF(btime,0)),MAX(NULLIF(btime,0)) FROM photos";
        if (sqlite3_prepare_v2(self->_database, sql, -1, &statement, NULL) != SQLITE_OK) return;
        if (sqlite3_step(statement) == SQLITE_ROW) {
            count = (NSUInteger)sqlite3_column_int64(statement, 0);
            if (count > 0) {
                earliestTime = sqlite3_column_double(statement, 1);
                latestTime = sqlite3_column_double(statement, 2);
            }
        }
        sqlite3_finalize(statement);
    });
    return @{
        @"count": @(count),
        @"earliestTime": @(earliestTime),
        @"latestTime": @(latestTime)
    };
}

- (void)setLocalPath:(NSString *)localPath forRemotePath:(NSString *)remotePath {
    [self executeUpdate:"UPDATE photos SET local_path=? WHERE remote_path=?" first:localPath second:remotePath];
}

- (void)clearLocalPathForRemotePath:(NSString *)remotePath {
    [self setLocalPath:nil forRemotePath:remotePath];
}

- (void)markPlayedRemotePath:(NSString *)remotePath {
    dispatch_async(_queue, ^{
        sqlite3_stmt *statement = NULL;
        sqlite3_prepare_v2(self->_database, "UPDATE photos SET last_played=? WHERE remote_path=?", -1, &statement, NULL);
        sqlite3_bind_double(statement, 1, [NSDate timeIntervalSinceReferenceDate]);
        sqlite3_bind_text(statement, 2, remotePath.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
    });
}

- (void)executeUpdate:(const char *)sql first:(NSString *)first second:(NSString *)second {
    dispatch_sync(_queue, ^{
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(self->_database, sql, -1, &statement, NULL) != SQLITE_OK) return;
        if (first) sqlite3_bind_text(statement, 1, first.UTF8String, -1, SQLITE_TRANSIENT); else sqlite3_bind_null(statement, 1);
        sqlite3_bind_text(statement, 2, second.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
    });
}

@end
