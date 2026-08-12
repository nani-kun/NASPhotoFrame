#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const unsigned int kPFPollSeconds = 30;
static const NSTimeInterval kPFHeartbeatSeconds = 60.0 * 60.0;
static const unsigned long long kPFMaxLogBytes = 512 * 1024;
static NSString * const kPFLogPath = @"/var/log/PFChargeLimiter.log";
static NSString * const kPFPreviousLogPath = @"/var/log/PFChargeLimiter.log.1";
static NSString * const kPFPolicyPath = @"/var/mobile/Library/Preferences/com.wangxiaoxiang.nasphotoframe.policy.plist";

static volatile sig_atomic_t gShouldExit = 0;

static NSDictionary *PFChargePolicy(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:kPFPolicyPath];
    return @{
        @"enabled": [saved objectForKey:@"chargeLimitEnabled"] ?: @YES,
        @"startPercent": [saved objectForKey:@"chargeStartPercent"] ?: @50,
        @"stopPercent": [saved objectForKey:@"chargeStopPercent"] ?: @70
    };
}

static NSString *PFTimestamp(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
    });
    return [formatter stringFromDate:[NSDate date]];
}

static void PFRotateLogIfNeeded(NSUInteger incomingBytes) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:kPFLogPath
                                                              error:NULL];
    unsigned long long currentBytes = [[attributes objectForKey:NSFileSize]
                                        unsignedLongLongValue];
    if (currentBytes + incomingBytes <= kPFMaxLogBytes) {
        return;
    }
    [fileManager removeItemAtPath:kPFPreviousLogPath error:NULL];
    [fileManager moveItemAtPath:kPFLogPath toPath:kPFPreviousLogPath error:NULL];
}

static void PFAppendLog(NSString *event, NSDictionary *fields) {
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    [record setObject:PFTimestamp() forKey:@"time"];
    [record setObject:event forKey:@"event"];
    if (fields != nil) {
        [record addEntriesFromDictionary:fields];
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:NULL];
    if (json == nil) {
        return;
    }
    NSMutableData *line = [json mutableCopy];
    const uint8_t newline = '\n';
    [line appendBytes:&newline length:1];
    PFRotateLogIfNeeded([line length]);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:kPFLogPath]) {
        [fileManager createFileAtPath:kPFLogPath contents:nil attributes:nil];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kPFLogPath];
    if (handle == nil) {
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:line];
    [handle closeFile];
}

static void PFPrintLog(void) {
    BOOL printed = NO;
    for (NSString *path in @[kPFPreviousLogPath, kPFLogPath]) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if ([data length] > 0) {
            fwrite([data bytes], 1, [data length], stdout);
            printed = YES;
        }
    }
    if (!printed) {
        fprintf(stderr, "PFChargeLimiter: no log has been recorded yet\n");
    }
}

static void PFHandleSignal(int signalNumber) {
    (void)signalNumber;
    gShouldExit = 1;
}

static io_service_t PFCopyPowerSourceService(void) {
    // iPad 4 exposes an AppleARMPMUPowerSource object derived from
    // IOPMPowerSource. Matching the superclass is the same fallback used by
    // ChargeLimiter on devices predating AppleSmartBattery.
    return IOServiceGetMatchingService(kIOMasterPortDefault,
                                       IOServiceMatching("IOPMPowerSource"));
}

static NSDictionary *PFCopyPowerSourceProperties(io_service_t service) {
    CFMutableDictionaryRef properties = NULL;
    kern_return_t result = IORegistryEntryCreateCFProperties(service,
                                                              &properties,
                                                              kCFAllocatorDefault,
                                                              0);
    if (result != KERN_SUCCESS || properties == NULL) {
        return nil;
    }
    return CFBridgingRelease(properties);
}

static BOOL PFBoolProperty(NSDictionary *properties, NSString *key) {
    id value = [properties objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

static BOOL PFExternalPowerConnected(NSDictionary *properties) {
    if (PFBoolProperty(properties, @"ExternalConnected") ||
        PFBoolProperty(properties, @"ExternalChargeCapable")) {
        return YES;
    }

    // Some old power-source drivers only publish adapter details while the
    // battery is inhibited.
    id adapterDetails = [properties objectForKey:@"AdapterDetails"];
    return [adapterDetails isKindOfClass:[NSDictionary class]] &&
           [(NSDictionary *)adapterDetails count] > 0;
}

static double PFChargePercent(NSDictionary *properties) {
    NSNumber *current = [properties objectForKey:@"CurrentCapacity"];
    NSNumber *maximum = [properties objectForKey:@"MaxCapacity"];
    if ([current respondsToSelector:@selector(doubleValue)] &&
        [maximum respondsToSelector:@selector(doubleValue)] &&
        [maximum doubleValue] > 100.0) {
        return 100.0 * [current doubleValue] / [maximum doubleValue];
    }

    // Newer power-source drivers publish CurrentCapacity directly as 0..100.
    if ([current respondsToSelector:@selector(doubleValue)] &&
        [current doubleValue] >= 0.0 && [current doubleValue] <= 100.0) {
        return [current doubleValue];
    }

    // Last-resort fallback for old gas-gauge implementations.
    NSNumber *rawCurrent = [properties objectForKey:@"AppleRawCurrentCapacity"];
    NSNumber *rawMaximum = [properties objectForKey:@"AppleRawMaxCapacity"];
    if ([rawCurrent respondsToSelector:@selector(doubleValue)] &&
        [rawMaximum respondsToSelector:@selector(doubleValue)] &&
        [rawMaximum doubleValue] > 0.0) {
        return 100.0 * [rawCurrent doubleValue] / [rawMaximum doubleValue];
    }
    return -1.0;
}

static kern_return_t PFSetChargingEnabledOnService(io_service_t service,
                                                    BOOL enabled) {
    NSDictionary *updates = @{ @"IsCharging": @(enabled) };
    return IORegistryEntrySetCFProperties(service,
                                          (__bridge CFTypeRef)updates);
}

static kern_return_t PFSetChargingEnabled(BOOL enabled) {
    io_service_t service = PFCopyPowerSourceService();
    if (service == IO_OBJECT_NULL) {
        return KERN_FAILURE;
    }
    kern_return_t result = PFSetChargingEnabledOnService(service, enabled);
    IOObjectRelease(service);
    return result;
}

static NSDictionary *PFStatusDictionary(io_service_t service,
                                        NSDictionary *properties) {
    NSDictionary *policy = PFChargePolicy();
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    io_name_t className = {0};
    IOObjectGetClass(service, className);
    [status setObject:[NSString stringWithUTF8String:className]
               forKey:@"ServiceClass"];
    [status setObject:[policy objectForKey:@"enabled"] forKey:@"LimitEnabled"];
    [status setObject:[policy objectForKey:@"startPercent"] forKey:@"StartBelowOrAt"];
    [status setObject:[policy objectForKey:@"stopPercent"] forKey:@"StopAboveOrAt"];
    [status setObject:@(PFExternalPowerConnected(properties))
               forKey:@"PowerConnected"];
    double chargePercent = PFChargePercent(properties);
    if (chargePercent >= 0.0) {
        [status setObject:@(chargePercent) forKey:@"ChargePercent"];
    }

    NSArray *keys = @[
        @"CurrentCapacity", @"MaxCapacity", @"IsCharging", @"ExternalConnected",
        @"ExternalChargeCapable", @"InstantAmperage", @"Amperage",
        @"Voltage", @"Temperature", @"CycleCount", @"DesignCapacity",
        @"AppleRawCurrentCapacity", @"AppleRawMaxCapacity"
    ];
    for (NSString *key in keys) {
        id value = [properties objectForKey:key];
        if (value != nil) {
            [status setObject:value forKey:key];
        }
    }
    return status;
}

static NSDictionary *PFLogFields(NSDictionary *properties, double percent) {
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    [fields setObject:@(percent) forKey:@"percent"];
    [fields setObject:@(PFExternalPowerConnected(properties))
               forKey:@"powerConnected"];
    [fields setObject:@(PFBoolProperty(properties, @"IsCharging"))
               forKey:@"isCharging"];
    for (NSString *key in @[@"CurrentCapacity", @"MaxCapacity",
                            @"AppleRawCurrentCapacity", @"AppleRawMaxCapacity",
                            @"InstantAmperage", @"Voltage", @"Temperature"]) {
        id value = [properties objectForKey:key];
        if (value != nil) {
            [fields setObject:value forKey:key];
        }
    }
    return fields;
}

static void PFLogReadError(NSString *message) {
    static NSTimeInterval lastErrorTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (lastErrorTime == 0 || now - lastErrorTime >= kPFHeartbeatSeconds) {
        PFAppendLog(@"error", @{ @"message": message });
        lastErrorTime = now;
    }
}

static void PFPrintStatus(void) {
    io_service_t service = PFCopyPowerSourceService();
    if (service == IO_OBJECT_NULL) {
        fprintf(stderr, "PFChargeLimiter: IOPMPowerSource not found\n");
        return;
    }
    NSDictionary *properties = PFCopyPowerSourceProperties(service);
    if (properties == nil) {
        fprintf(stderr, "PFChargeLimiter: unable to read power source\n");
        IOObjectRelease(service);
        return;
    }
    NSDictionary *status = PFStatusDictionary(service, properties);
    NSData *data = [NSJSONSerialization dataWithJSONObject:status
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    fwrite([data bytes], 1, [data length], stdout);
    fputc('\n', stdout);
    IOObjectRelease(service);
}

static void PFEvaluatePolicy(void) {
    NSDictionary *policy = PFChargePolicy();
    io_service_t service = PFCopyPowerSourceService();
    if (service == IO_OBJECT_NULL) {
        NSLog(@"PFChargeLimiter: waiting for IOPMPowerSource");
        PFLogReadError(@"IOPMPowerSource not found");
        return;
    }

    NSDictionary *properties = PFCopyPowerSourceProperties(service);
    double percent = PFChargePercent(properties);
    if (percent < 0.0) {
        NSLog(@"PFChargeLimiter: unable to calculate charge percentage");
        PFLogReadError(@"unable to calculate charge percentage");
        IOObjectRelease(service);
        return;
    }

    BOOL connected = PFExternalPowerConnected(properties);
    BOOL charging = PFBoolProperty(properties, @"IsCharging");
    BOOL limitEnabled = [[policy objectForKey:@"enabled"] boolValue];
    NSInteger startPercent = [[policy objectForKey:@"startPercent"] integerValue];
    NSInteger stopPercent = [[policy objectForKey:@"stopPercent"] integerValue];
    BOOL desiredCharging = charging;
    BOOL shouldWrite = NO;
    static BOOL hasPreviousState = NO;
    static BOOL previousConnected = NO;
    static BOOL previousCharging = NO;
    static NSTimeInterval lastHeartbeatTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    if (!hasPreviousState || connected != previousConnected ||
        charging != previousCharging) {
        PFAppendLog(@"state", PFLogFields(properties, percent));
        hasPreviousState = YES;
        previousConnected = connected;
        previousCharging = charging;
        lastHeartbeatTime = now;
    } else if (now - lastHeartbeatTime >= kPFHeartbeatSeconds) {
        PFAppendLog(@"heartbeat", PFLogFields(properties, percent));
        lastHeartbeatTime = now;
    }

    if (!limitEnabled && connected && !charging) {
        desiredCharging = YES;
        shouldWrite = YES;
    } else if (limitEnabled && connected && percent <= (double)startPercent && !charging) {
        desiredCharging = YES;
        shouldWrite = YES;
    } else if (limitEnabled && connected && percent >= (double)stopPercent && charging) {
        desiredCharging = NO;
        shouldWrite = YES;
    }

    if (shouldWrite) {
        kern_return_t result = PFSetChargingEnabledOnService(service,
                                                             desiredCharging);
        NSMutableDictionary *fields = [PFLogFields(properties, percent)
                                        mutableCopy];
        [fields setObject:(desiredCharging ? @"enable" : @"inhibit")
                   forKey:@"action"];
        [fields setObject:@(result) forKey:@"result"];
        PFAppendLog(@"action", fields);
        NSLog(@"PFChargeLimiter: %@ charging at %.1f%% (result=0x%x)",
              desiredCharging ? @"enabled" : @"inhibited",
              percent,
              result);
    }
    IOObjectRelease(service);
}

static int PFRunDaemon(void) {
    signal(SIGTERM, PFHandleSignal);
    signal(SIGINT, PFHandleSignal);
    signal(SIGHUP, PFHandleSignal);

    NSDictionary *policy = PFChargePolicy();
    NSInteger startPercent = [[policy objectForKey:@"startPercent"] integerValue];
    NSInteger stopPercent = [[policy objectForKey:@"stopPercent"] integerValue];
    NSLog(@"PFChargeLimiter: started with %ld%%/%ld%% thresholds",
          (long)startPercent,
          (long)stopPercent);
    PFAppendLog(@"start", @{
        @"enabled": [policy objectForKey:@"enabled"],
        @"startPercent": @(startPercent),
        @"stopPercent": @(stopPercent),
        @"pollSeconds": @(kPFPollSeconds)
    });
    while (!gShouldExit) {
        @autoreleasepool {
            PFEvaluatePolicy();
        }
        unsigned int remaining = kPFPollSeconds;
        while (!gShouldExit && remaining > 0) {
            remaining = sleep(remaining);
        }
    }

    // Restore charging when launchd delivers a catchable termination signal.
    // The package prerm also performs an explicit restore because iOS 8 may
    // terminate a launch daemon without allowing this cleanup path to run.
    kern_return_t result = PFSetChargingEnabled(YES);
    PFAppendLog(@"stop", @{ @"chargingRestoreResult": @(result) });
    NSLog(@"PFChargeLimiter: stopped; charging restored (result=0x%x)", result);
    return 0;
}

static void PFPrintUsage(const char *program) {
    fprintf(stderr,
            "Usage: %s daemon|status|log|once|enable|disable\n",
            program);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        const char *command = argc > 1 ? argv[1] : "daemon";
        if (strcmp(command, "daemon") == 0) {
            return PFRunDaemon();
        }
        if (strcmp(command, "status") == 0) {
            PFPrintStatus();
            return 0;
        }
        if (strcmp(command, "log") == 0) {
            PFPrintLog();
            return 0;
        }
        if (strcmp(command, "once") == 0) {
            PFEvaluatePolicy();
            PFPrintStatus();
            return 0;
        }
        if (strcmp(command, "enable") == 0 ||
            strcmp(command, "disable") == 0) {
            BOOL enabled = strcmp(command, "enable") == 0;
            kern_return_t result = PFSetChargingEnabled(enabled);
            if (result != KERN_SUCCESS) {
                fprintf(stderr,
                        "PFChargeLimiter: unable to %s charging (0x%x)\n",
                        enabled ? "enable" : "disable",
                        result);
                return 1;
            }
            PFAppendLog(@"command", @{
                @"action": enabled ? @"enable" : @"disable",
                @"result": @(result)
            });
            PFPrintStatus();
            return 0;
        }
        PFPrintUsage(argv[0]);
        return 2;
    }
}
