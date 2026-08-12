#import <Foundation/Foundation.h>

@interface PFCredentialStore : NSObject
+ (NSString *)password;
+ (BOOL)savePassword:(NSString *)password error:(NSError **)error;
@end
