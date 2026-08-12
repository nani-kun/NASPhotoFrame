#import "PFSMBClient.h"
#import "PFConfiguration.h"
#import "PFPhoto.h"
#import "PFLocalization.h"
#import <smb2/smb2.h>
#import <smb2/libsmb2.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static NSString * const PFSMBErrorDomain = @"PFSMBErrorDomain";

static NSString *PFNormalizeRemotePath(NSString *path) {
    NSString *value = [path ?: @"" stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([value hasPrefix:@"/"]) value = [value substringFromIndex:1];
    while ([value hasSuffix:@"/"] && value.length > 0) value = [value substringToIndex:value.length - 1];
    return value;
}

static NSError *PFSMBError(struct smb2_context *context, NSInteger code, NSString *operation) {
    const char *detail = context ? smb2_get_error(context) : NULL;
    NSString *text = detail ? [NSString stringWithUTF8String:detail] : PFL(@"error.smb.unknown");
    NSString *message = [NSString stringWithFormat:PFL(@"error.operationFailed"), operation, text ?: PFL(@"error.unknown")];
    return [NSError errorWithDomain:PFSMBErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static struct smb2_context *PFCreateConnectedContext(PFConfiguration *configuration, NSString *password, NSError **error) {
    struct smb2_context *context = smb2_init_context();
    if (!context) {
        if (error) *error = [NSError errorWithDomain:PFSMBErrorDomain code:ENOMEM userInfo:@{NSLocalizedDescriptionKey: PFL(@"error.smb.createSession")}];
        return NULL;
    }
    smb2_set_timeout(context, 20);
    smb2_set_version(context, SMB2_VERSION_ANY);
    smb2_set_authentication(context, SMB2_SEC_NTLMSSP);
    smb2_set_security_mode(context, SMB2_NEGOTIATE_SIGNING_ENABLED);
    smb2_set_user(context, configuration.username.UTF8String);
    smb2_set_password(context, (password ?: @"").UTF8String);
    if (configuration.domain.length) smb2_set_domain(context, configuration.domain.UTF8String);
    int result = smb2_connect_share(context, configuration.host.UTF8String,
                                    configuration.share.UTF8String,
                                    configuration.username.UTF8String);
    if (result < 0) {
        if (error) *error = PFSMBError(context, result, PFL(@"operation.connectNAS"));
        smb2_destroy_context(context);
        return NULL;
    }
    return context;
}

static void PFDestroyContext(struct smb2_context *context) {
    if (!context) return;
    smb2_disconnect_share(context);
    smb2_destroy_context(context);
}

@implementation PFSMBClient

- (BOOL)testConfiguration:(PFConfiguration *)configuration password:(NSString *)password error:(NSError **)error {
    struct smb2_context *context = PFCreateConnectedContext(configuration, password, error);
    if (!context) return NO;
    NSString *root = PFNormalizeRemotePath(configuration.rootPath);
    struct smb2dir *directory = smb2_opendir(context, root.UTF8String);
    if (!directory) {
        if (error) *error = PFSMBError(context, -1, PFL(@"operation.openPhotoDirectory"));
        PFDestroyContext(context);
        return NO;
    }
    smb2_closedir(context, directory);
    PFDestroyContext(context);
    return YES;
}

- (NSArray *)enumeratePhotosWithConfiguration:(PFConfiguration *)configuration password:(NSString *)password error:(NSError **)error {
    struct smb2_context *context = NULL;
    NSMutableArray *photos = [NSMutableArray array];
    NSString *rootPath = PFNormalizeRemotePath(configuration.rootPath);
    NSMutableArray *pending = [NSMutableArray arrayWithObject:rootPath];
    NSSet *extensions = [NSSet setWithObjects:@"jpg", @"jpeg", @"png", @"gif", @"bmp", @"tif", @"tiff", nil];
    BOOL failed = NO;
    NSUInteger skippedDirectoryCount = 0;
    __strong NSError *scanError = nil;

    while (pending.count && photos.count < 100000) {
        @autoreleasepool {
            NSString *directoryPath = pending.lastObject;
            [pending removeLastObject];
            struct smb2dir *directory = NULL;
            // A long recursive scan may outlive an SMB session on older NAS
            // devices. Reconnect and retry this directory instead of throwing
            // away all work completed earlier in the scan.
            BOOL shouldSkipDirectory = NO;
            for (NSUInteger attempt = 0; attempt < 3 && !directory; attempt++) {
                if (!context) {
                    NSError *connectionError = nil;
                    context = PFCreateConnectedContext(configuration, password, &connectionError);
                    if (!context) {
                        scanError = connectionError;
                        continue;
                    }
                }
                directory = smb2_opendir(context, directoryPath.UTF8String);
                if (!directory) {
                    NSString *displayPath = directoryPath.length ? directoryPath : @"/";
                    scanError = PFSMBError(context, -1, [NSString stringWithFormat:PFL(@"operation.scanDirectory"), displayPath]);
                    uint32_t ntStatus = (uint32_t)smb2_get_nterror(context);
                    // Shares often contain administrative or private folders
                    // that the photo account intentionally cannot list. A
                    // denied child folder must not invalidate the accessible
                    // portion of an otherwise successful snapshot.
                    if (ntStatus == SMB2_STATUS_ACCESS_DENIED && ![directoryPath isEqualToString:rootPath]) {
                        skippedDirectoryCount++;
                        NSLog(@"[NASPhotoFrame] Skipping inaccessible NAS directory %@: %@", displayPath, scanError.localizedDescription);
                        shouldSkipDirectory = YES;
                    }
                    PFDestroyContext(context);
                    context = NULL;
                    if (shouldSkipDirectory) break;
                }
            }
            if (shouldSkipDirectory) continue;
            if (!directory) { failed = YES; break; }
            struct smb2dirent *entry = NULL;
            while ((entry = smb2_readdir(context, directory))) {
                @autoreleasepool {
                    if (!entry->name) continue;
                    NSString *name = [NSString stringWithUTF8String:entry->name];
                    if (!name.length || [name isEqualToString:@"."] || [name isEqualToString:@".."] || [name hasPrefix:@"."]) continue;
                    NSString *path = directoryPath.length ? [directoryPath stringByAppendingFormat:@"/%@", name] : name;
                    if (entry->st.smb2_type == SMB2_TYPE_DIRECTORY) {
                        if (pending.count < 100000) [pending addObject:path];
                    } else if (entry->st.smb2_type == SMB2_TYPE_FILE && [extensions containsObject:name.pathExtension.lowercaseString]) {
                        PFPhoto *photo = [[PFPhoto alloc] init];
                        photo.remotePath = path;
                        photo.fileName = name;
                        photo.fileSize = entry->st.smb2_size;
                        photo.modificationTime = (NSTimeInterval)entry->st.smb2_mtime;
                        photo.creationTime = (NSTimeInterval)entry->st.smb2_btime;
                        [photos addObject:photo];
                    }
                }
            }
            smb2_closedir(context, directory);
        }
    }
    PFDestroyContext(context);
    if (!failed && skippedDirectoryCount) {
        NSLog(@"[NASPhotoFrame] NAS scan completed; skipped %lu inaccessible director%@", (unsigned long)skippedDirectoryCount, skippedDirectoryCount == 1 ? @"y" : @"ies");
    }
    if (failed && error) *error = scanError ?: [NSError errorWithDomain:PFSMBErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: PFL(@"error.nasScanFailed")}];
    return failed ? nil : photos;
}

- (BOOL)downloadRemotePath:(NSString *)remotePath configuration:(PFConfiguration *)configuration password:(NSString *)password destinationPath:(NSString *)destinationPath error:(NSError **)error {
    struct smb2_context *context = PFCreateConnectedContext(configuration, password, error);
    if (!context) return NO;
    struct smb2fh *file = smb2_open(context, PFNormalizeRemotePath(remotePath).UTF8String, O_RDONLY);
    if (!file) {
        if (error) *error = PFSMBError(context, -1, PFL(@"operation.openPhoto"));
        PFDestroyContext(context);
        return NO;
    }
    int output = open(destinationPath.fileSystemRepresentation, O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (output < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        smb2_close(context, file); PFDestroyContext(context); return NO;
    }
    uint8_t *buffer = malloc(256 * 1024);
    uint64_t offset = 0;
    BOOL success = buffer != NULL;
    while (success) {
        int count = smb2_pread(context, file, buffer, 256 * 1024, offset);
        if (count == -EAGAIN) continue;
        if (count == 0) break;
        if (count < 0) { success = NO; if (error) *error = PFSMBError(context, count, PFL(@"operation.readPhoto")); break; }
        ssize_t written = 0;
        while (written < count) {
            ssize_t part = write(output, buffer + written, (size_t)(count - written));
            if (part <= 0) { success = NO; if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; break; }
            written += part;
        }
        offset += (uint64_t)count;
    }
    if (!buffer && error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOMEM userInfo:nil];
    free(buffer);
    fsync(output);
    close(output);
    smb2_close(context, file);
    PFDestroyContext(context);
    if (!success) [[NSFileManager defaultManager] removeItemAtPath:destinationPath error:nil];
    return success;
}

@end
