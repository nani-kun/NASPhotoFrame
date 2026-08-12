#import "PFCredentialStore.h"
#import <Security/Security.h>

static NSString * const PFCredentialService = @"com.wangxiaoxiang.nasphotoframe.smb";
static NSString * const PFCredentialAccount = @"nas-password";

@implementation PFCredentialStore

+ (NSMutableDictionary *)query {
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: PFCredentialService,
        (__bridge id)kSecAttrAccount: PFCredentialAccount
    } mutableCopy];
}

+ (NSString *)password {
    NSMutableDictionary *query = [self query];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return @"";
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

+ (BOOL)savePassword:(NSString *)password error:(NSError **)error {
    NSData *data = [(password ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *query = [self query];
    NSDictionary *changes = @{(__bridge id)kSecValueData: data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                    (__bridge CFDictionaryRef)changes);
    if (status == errSecItemNotFound) {
        query[(__bridge id)kSecValueData] = data;
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    if (status != errSecSuccess && error) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
    return status == errSecSuccess;
}

@end
