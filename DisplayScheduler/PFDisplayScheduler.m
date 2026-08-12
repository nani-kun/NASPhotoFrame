#import <Foundation/Foundation.h>
#import <IOKit/pwr_mgt/IOPMKeys.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <SpringBoardServices/SpringBoardServices.h>

#include <stdio.h>
#include <string.h>
#include <math.h>
#include <spawn.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

FOUNDATION_EXPORT void SBSLockDevice(void);
FOUNDATION_EXPORT float BKSDisplayBrightnessGetCurrent(void);
FOUNDATION_EXPORT void BKSDisplayBrightnessSet(float brightness, NSInteger unknown);
FOUNDATION_EXPORT void BKSDisplayBrightnessSetWithImplicitTransaction(float brightness);
extern char **environ;

static NSString * const kPFBundleIdentifier = @"com.wangxiaoxiang.nasphotoframe";
static NSString * const kPFLogPath = @"/var/log/PFDisplayScheduler.log";
static NSString * const kPFPolicyPath = @"/var/mobile/Library/Preferences/com.wangxiaoxiang.nasphotoframe.policy.plist";
static NSString * const kPFPowerEventIdentifier = @"com.wangxiaoxiang.pfdisplayscheduler";
static NSString * const kPFTestPowerEventIdentifier = @"com.wangxiaoxiang.pfdisplayscheduler.test";
static volatile sig_atomic_t gShouldExit = 0;

static NSDictionary *PFPolicy(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:kPFPolicyPath];
    NSNumber *savedBrightness = [saved objectForKey:@"brightnessPercent"];
    NSInteger currentBrightness = MAX(5, MIN(100,
        (NSInteger)lroundf(BKSDisplayBrightnessGetCurrent() * 100.0f)));
    return @{
        @"wakeScheduleEnabled": [saved objectForKey:@"wakeScheduleEnabled"] ?: @YES,
        @"sleepScheduleEnabled": [saved objectForKey:@"sleepScheduleEnabled"] ?: @YES,
        @"wakeHour": [saved objectForKey:@"wakeHour"] ?: @7,
        @"wakeMinute": [saved objectForKey:@"wakeMinute"] ?: @0,
        @"sleepHour": [saved objectForKey:@"sleepHour"] ?: @22,
        @"sleepMinute": [saved objectForKey:@"sleepMinute"] ?: @0,
        @"chargeLimitEnabled": [saved objectForKey:@"chargeLimitEnabled"] ?: @YES,
        @"chargeStartPercent": [saved objectForKey:@"chargeStartPercent"] ?: @50,
        @"chargeStopPercent": [saved objectForKey:@"chargeStopPercent"] ?: @70,
        @"brightnessPercent": savedBrightness ?: @(currentBrightness)
    };
}

static int PFWritePolicyFromBase64(const char *value) {
    NSString *encoded = [NSString stringWithUTF8String:value];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    id input = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![input isKindOfClass:[NSDictionary class]]) {
        fprintf(stderr, "PFDisplayScheduler: invalid policy JSON\n");
        return 2;
    }

    NSInteger wakeHour = [[input objectForKey:@"wakeHour"] integerValue];
    NSInteger wakeMinute = [[input objectForKey:@"wakeMinute"] integerValue];
    NSInteger sleepHour = [[input objectForKey:@"sleepHour"] integerValue];
    NSInteger sleepMinute = [[input objectForKey:@"sleepMinute"] integerValue];
    NSInteger chargeStart = [[input objectForKey:@"chargeStartPercent"] integerValue];
    NSInteger chargeStop = [[input objectForKey:@"chargeStopPercent"] integerValue];
    NSInteger brightness = [[input objectForKey:@"brightnessPercent"] integerValue];
    if (wakeHour < 0 || wakeHour > 23 || wakeMinute < 0 || wakeMinute > 59 ||
        sleepHour < 0 || sleepHour > 23 || sleepMinute < 0 || sleepMinute > 59 ||
        chargeStart < 20 || chargeStart > 90 || chargeStop < 30 ||
        chargeStop > 95 || chargeStart >= chargeStop ||
        brightness < 5 || brightness > 100) {
        fprintf(stderr, "PFDisplayScheduler: policy values out of range\n");
        return 2;
    }
    NSDictionary *policy = @{
        @"wakeScheduleEnabled": @([[input objectForKey:@"wakeScheduleEnabled"] boolValue]),
        @"sleepScheduleEnabled": @([[input objectForKey:@"sleepScheduleEnabled"] boolValue]),
        @"wakeHour": @(wakeHour), @"wakeMinute": @(wakeMinute),
        @"sleepHour": @(sleepHour), @"sleepMinute": @(sleepMinute),
        @"chargeLimitEnabled": @([[input objectForKey:@"chargeLimitEnabled"] boolValue]),
        @"chargeStartPercent": @(chargeStart),
        @"chargeStopPercent": @(chargeStop),
        @"brightnessPercent": @(brightness)
    };
    if (![policy writeToFile:kPFPolicyPath atomically:YES]) {
        fprintf(stderr, "PFDisplayScheduler: unable to save policy\n");
        return 1;
    }
    chmod([kPFPolicyPath fileSystemRepresentation], 0644);
    chown([kPFPolicyPath fileSystemRepresentation], 501, 501);
    BKSDisplayBrightnessSetWithImplicitTransaction((float)brightness / 100.0f);
    return 0;
}

static int PFPrintPolicy(void) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:PFPolicy()
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    fwrite([data bytes], 1, [data length], stdout);
    fputc('\n', stdout);
    return 0;
}

static void PFHandleSignal(int signalNumber) {
    (void)signalNumber;
    gShouldExit = 1;
}

static void PFAppendLog(NSString *action, NSDictionary *fields) {
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    [record setObject:@([[NSDate date] timeIntervalSince1970]) forKey:@"timestamp"];
    [record setObject:action forKey:@"action"];
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

static NSDictionary *PFScreenStatus(void) {
    BOOL locked = NO;
    BOOL passcodeEnabled = NO;
    SBGetScreenLockStatus(SBSSpringBoardServerPort(), &locked, &passcodeEnabled);
    NSString *frontmost = SBSCopyFrontmostApplicationDisplayIdentifier();
    return @{
        @"locked": @(locked),
        @"passcodeEnabled": @(passcodeEnabled),
        @"frontmost": frontmost ?: @"",
        @"brightnessPercent": @(lroundf(BKSDisplayBrightnessGetCurrent() * 100.0f))
    };
}

static void PFCancelWakeEventsWithIdentifier(NSString *identifier) {
    CFArrayRef copiedEvents = IOPMCopyScheduledPowerEvents();
    if (copiedEvents == NULL) {
        return;
    }
    NSArray *events = CFBridgingRelease(copiedEvents);
    for (NSDictionary *event in events) {
        NSString *scheduledBy = [event objectForKey:@kIOPMPowerEventAppNameKey];
        NSString *eventType = [event objectForKey:@kIOPMPowerEventTypeKey];
        NSDate *date = [event objectForKey:@kIOPMPowerEventTimeKey];
        if ([scheduledBy isEqualToString:identifier] &&
            [eventType isEqualToString:@kIOPMAutoWake] &&
            [date isKindOfClass:[NSDate class]]) {
            IOPMCancelScheduledPowerEvent((__bridge CFDateRef)date,
                                          (__bridge CFStringRef)identifier,
                                          CFSTR(kIOPMAutoWake));
        }
    }
}

static int PFScheduleWakeAtDate(NSDate *date, NSString *identifier,
                                NSString *logAction) {
    PFCancelWakeEventsWithIdentifier(identifier);
    IOReturn result = IOPMSchedulePowerEvent((__bridge CFDateRef)date,
                                             (__bridge CFStringRef)identifier,
                                             CFSTR(kIOPMAutoWake));
    PFAppendLog(logAction, @{
        @"wakeTimestamp": @([date timeIntervalSince1970]),
        @"result": @(result)
    });
    return result == kIOReturnSuccess ? 0 : 1;
}

static int PFScheduleNextWake(void) {
    NSDictionary *policy = PFPolicy();
    if (![[policy objectForKey:@"wakeScheduleEnabled"] boolValue]) {
        PFCancelWakeEventsWithIdentifier(kPFPowerEventIdentifier);
        return 0;
    }
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSUInteger units = NSCalendarUnitYear | NSCalendarUnitMonth |
                       NSCalendarUnitDay;
    NSDateComponents *components = [calendar components:units fromDate:now];
    components.hour = [[policy objectForKey:@"wakeHour"] integerValue];
    components.minute = [[policy objectForKey:@"wakeMinute"] integerValue];
    components.second = 0;
    NSDate *nextWake = [calendar dateFromComponents:components];
    if ([nextWake compare:now] != NSOrderedDescending) {
        NSDateComponents *oneDay = [[NSDateComponents alloc] init];
        oneDay.day = 1;
        nextWake = [calendar dateByAddingComponents:oneDay
                                              toDate:nextWake
                                             options:0];
    }
    // Wake the hardware 30 seconds early so Wi-Fi and SpringBoard are ready
    // when the configured opening time arrives.
    nextWake = [nextWake dateByAddingTimeInterval:-30.0];
    return PFScheduleWakeAtDate(nextWake, kPFPowerEventIdentifier,
                                @"scheduleNextWake");
}

static int PFScheduleTestWake(void) {
    NSDate *testDate = [NSDate dateWithTimeIntervalSinceNow:60.0];
    return PFScheduleWakeAtDate(testDate, kPFTestPowerEventIdentifier,
                                @"scheduleTestWake");
}

static int PFPrintPowerEvents(void) {
    CFArrayRef copiedEvents = IOPMCopyScheduledPowerEvents();
    NSArray *events = copiedEvents == NULL ? @[] : CFBridgingRelease(copiedEvents);
    for (NSDictionary *event in events) {
        NSString *scheduledBy = [event objectForKey:@kIOPMPowerEventAppNameKey];
        if (![scheduledBy hasPrefix:kPFPowerEventIdentifier]) {
            continue;
        }
        NSDate *date = [event objectForKey:@kIOPMPowerEventTimeKey];
        NSString *eventType = [event objectForKey:@kIOPMPowerEventTypeKey];
        printf("%s\t%.0f\t%s\n",
               [scheduledBy UTF8String],
               [date timeIntervalSince1970],
               [eventType UTF8String]);
    }
    return 0;
}

static int PFSleep(void) {
    int scheduleResult = PFScheduleNextWake();
    SBSLockDevice();
    usleep(500000);
    NSDictionary *status = PFScreenStatus();
    PFAppendLog(@"sleep", status);
    BOOL locked = [[status objectForKey:@"locked"] boolValue];
    return (scheduleResult == 0 && locked) ? 0 : 1;
}

static int PFWake(void) {
    SBSUndimScreen();
    NSInteger brightness = [[PFPolicy() objectForKey:@"brightnessPercent"] integerValue];
    BKSDisplayBrightnessSetWithImplicitTransaction((float)brightness / 100.0f);
    pid_t child = 0;
    char *arguments[] = {
        "/usr/bin/uiopen",
        "nasphotoframe://open",
        NULL
    };
    int spawnResult = posix_spawn(&child, arguments[0], NULL, NULL,
                                  arguments, environ);
    int childStatus = -1;
    if (spawnResult == 0) {
        waitpid(child, &childStatus, 0);
    }
    usleep(1000000);

    NSMutableDictionary *fields = [PFScreenStatus() mutableCopy];
    [fields setObject:@(spawnResult) forKey:@"uiopenSpawnResult"];
    [fields setObject:@(childStatus) forKey:@"uiopenStatus"];
    PFAppendLog(@"wake", fields);

    BOOL unlocked = ![[fields objectForKey:@"locked"] boolValue];
    BOOL appIsFrontmost = [[fields objectForKey:@"frontmost"]
                           isEqualToString:kPFBundleIdentifier];
    BOOL uiopenSucceeded = (spawnResult == 0 && WIFEXITED(childStatus) &&
                            WEXITSTATUS(childStatus) == 0);
    int scheduleResult = PFScheduleNextWake();
    return (uiopenSucceeded && unlocked && appIsFrontmost &&
            scheduleResult == 0) ? 0 : 1;
}

static int PFStatus(void) {
    NSDictionary *status = PFScreenStatus();
    NSData *data = [NSJSONSerialization dataWithJSONObject:status
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    fwrite([data bytes], 1, [data length], stdout);
    fputc('\n', stdout);
    return 0;
}

static int PFRunScheduledAction(void) {
    time_t now = time(NULL);
    struct tm localTime;
    localtime_r(&now, &localTime);

    // A single launchd job owns both calendar intervals.  Keeping the decision
    // here avoids an iOS 8 launchd issue observed on device where two jobs that
    // share one executable can dispatch the other job's arguments.
    NSDictionary *policy = PFPolicy();
    int nowMinutes = localTime.tm_hour * 60 + localTime.tm_min;
    int wakeMinutes = [[policy objectForKey:@"wakeHour"] intValue] * 60 +
                      [[policy objectForKey:@"wakeMinute"] intValue];
    int sleepMinutes = [[policy objectForKey:@"sleepHour"] intValue] * 60 +
                       [[policy objectForKey:@"sleepMinute"] intValue];
    BOOL shouldBeNight = sleepMinutes > wakeMinutes
        ? (nowMinutes >= sleepMinutes || nowMinutes < wakeMinutes)
        : (nowMinutes >= sleepMinutes && nowMinutes < wakeMinutes);
    if (shouldBeNight) {
        if (![[policy objectForKey:@"sleepScheduleEnabled"] boolValue]) return 0;
        return PFSleep();
    }
    if (![[policy objectForKey:@"wakeScheduleEnabled"] boolValue]) return 0;
    return PFWake();
}

static int PFRunDaemon(void) {
    signal(SIGTERM, PFHandleSignal);
    signal(SIGINT, PFHandleSignal);
    signal(SIGHUP, PFHandleSignal);

    int lastAppliedNightState = -1;
    PFScheduleNextWake();
    PFAppendLog(@"daemonStart", nil);

    while (!gShouldExit) {
        @autoreleasepool {
            time_t now = time(NULL);
            struct tm localTime;
            localtime_r(&now, &localTime);
            NSDictionary *policy = PFPolicy();
            int nowMinutes = localTime.tm_hour * 60 + localTime.tm_min;
            int wakeMinutes = [[policy objectForKey:@"wakeHour"] intValue] * 60 +
                              [[policy objectForKey:@"wakeMinute"] intValue];
            int sleepMinutes = [[policy objectForKey:@"sleepHour"] intValue] * 60 +
                               [[policy objectForKey:@"sleepMinute"] intValue];
            BOOL shouldBeNight = sleepMinutes > wakeMinutes
                ? (nowMinutes >= sleepMinutes || nowMinutes < wakeMinutes)
                : (nowMinutes >= sleepMinutes && nowMinutes < wakeMinutes);
            if (lastAppliedNightState != (int)shouldBeNight) {
                BOOL enabled = [[policy objectForKey:(shouldBeNight
                    ? @"sleepScheduleEnabled" : @"wakeScheduleEnabled")] boolValue];
                int result = enabled ? (shouldBeNight ? PFSleep() : PFWake()) : 0;
                if (result == 0) {
                    lastAppliedNightState = (int)shouldBeNight;
                }
            }
        }

        unsigned int remaining = 5;
        while (!gShouldExit && remaining > 0) {
            remaining = sleep(remaining);
        }
    }

    PFAppendLog(@"daemonStop", nil);
    return 0;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc != 2 && argc != 3) {
            fprintf(stderr, "Usage: %s daemon|scheduled|sleep|wake|status|schedule-wake|test-wake|power-events|policy|set-policy <base64-json>\n", argv[0]);
            return 2;
        }
        if (argc == 2 && strcmp(argv[1], "daemon") == 0) {
            return PFRunDaemon();
        }
        if (strcmp(argv[1], "scheduled") == 0) {
            return PFRunScheduledAction();
        }
        if (strcmp(argv[1], "sleep") == 0) {
            return PFSleep();
        }
        if (strcmp(argv[1], "wake") == 0) {
            return PFWake();
        }
        if (strcmp(argv[1], "status") == 0) {
            return PFStatus();
        }
        if (strcmp(argv[1], "schedule-wake") == 0) {
            return PFScheduleNextWake();
        }
        if (strcmp(argv[1], "test-wake") == 0) {
            return PFScheduleTestWake();
        }
        if (strcmp(argv[1], "power-events") == 0) {
            return PFPrintPowerEvents();
        }
        if (strcmp(argv[1], "policy") == 0) {
            return PFPrintPolicy();
        }
        if (argc == 3 && strcmp(argv[1], "set-policy") == 0) {
            return PFWritePolicyFromBase64(argv[2]);
        }
        fprintf(stderr, "Usage: %s daemon|scheduled|sleep|wake|status|schedule-wake|test-wake|power-events|policy|set-policy <base64-json>\n", argv[0]);
        return 2;
    }
}
