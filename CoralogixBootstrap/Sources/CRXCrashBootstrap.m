//
//  CRXCrashBootstrap.m
//  CoralogixBootstrap
//

#import "CRXCrashBootstrap.h"
#import "CRXCrashContext.h"
#import "CRXTerminateHandler.h"
#import <stdatomic.h>

#if __has_include(<CrashReporter/CrashReporter.h>)
#import <CrashReporter/CrashReporter.h>
#elif __has_include("CrashReporter.h")
#import "CrashReporter.h"
#else
@import CrashReporter;
#endif

/// Info.plist key a host app can set to `YES` to skip the load-time install. Read from the
/// main bundle, which dyld has already loaded by the time `+load` runs.
static NSString *const kCRXDisableEarlyCrashHandlerKey = @"CoralogixDisableEarlyCrashHandler";

/// Written once from `+load`, before any other code of ours can run, and read-only afterwards.
/// That ordering is the synchronization — no lock is needed. The reporter crash context is
/// written through is `CRXCrashContext.activeReporter`, which the init-time fallback can set
/// later and so is lock-guarded there.
static PLCrashReporter *_crx_reporter;
static NSError *_crx_enableError;
static BOOL _crx_disabledByHostApp;
/// Minted once in `+load` and never written again; claimed at most once (see `claimLaunchSession`).
static NSString *_crx_launchSessionId;
static atomic_flag _crx_launchSessionClaimed = ATOMIC_FLAG_INIT;

@implementation CRXCrashBootstrap

+ (void)load {
    @autoreleasepool {
        // Before the opt-out: the key covers PLCrashReporter's signal handlers only. The handler
        // writes nothing until a reporter of ours is active.
        [CRXTerminateHandler install];

        // Only an id: on iOS 15+ prewarming runs +load long before the app is opened, so a
        // creation time taken here would date the session from before the user launched it.
        _crx_launchSessionId = [[NSUUID UUID].UUIDString lowercaseString];
        [CRXCrashContext setSection:CRXCrashContextKeySession
                              value:@{CRXCrashContextKeySessionId: _crx_launchSessionId}];

        // Accepts both a boolean and a string value: Info.plist entries are routinely written
        // either way, and NSNumber and NSString both answer boolValue.
        id disabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:kCRXDisableEarlyCrashHandlerKey];
        if ([disabled respondsToSelector:@selector(boolValue)] && [disabled boolValue]) {
            _crx_disabledByHostApp = YES;
            return;
        }

        // Matches the configuration `initializeCrashInstrumentation` used before this target
        // existed, so enabling earlier changes ordering only, never report content.
        PLCrashReporterConfig *config =
            [[PLCrashReporterConfig alloc] initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD
                                              symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll];

        PLCrashReporter *reporter = [[PLCrashReporter alloc] initWithConfiguration:config];
        if (reporter == nil) {
            // Recorded rather than returned silently: without it the Swift side cannot tell an
            // allocation failure apart from +load never having run, and both look like "no
            // reporter" at init.
            _crx_enableError = [NSError errorWithDomain:@"com.coralogix.crashbootstrap"
                                                   code:1
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                              @"PLCrashReporter could not be created"}];
            return;
        }

        // Before enabling: a crash this launch has would otherwise overwrite the slot first. Only
        // copied: the slot is emptied by recovery, once the options say crashes are reported, so a
        // host app reading the same slot keeps its report otherwise.
        NSURL *copies = CRXCrashBootstrap.crashCopiesDirectory;
        if (copies != nil) {
            [CRXCrashBootstrap copyPendingReportOf:reporter toDirectory:copies];
        }

        NSError *error = nil;
        if ([reporter enableCrashReporterAndReturnError:&error]) {
            _crx_reporter = reporter;
            CRXCrashContext.activeReporter = reporter;
        } else {
            _crx_enableError = error;
        }
    }
}

+ (PLCrashReporter *)reporter {
    return _crx_reporter;
}

+ (NSError *)enableError {
    return _crx_enableError;
}

+ (BOOL)disabledByHostApp {
    return _crx_disabledByHostApp;
}

+ (NSURL *)crashCopiesDirectory {
#if TARGET_OS_TV
    // tvOS gives apps no persistent storage beyond caches.
    NSSearchPathDirectory base = NSCachesDirectory;
#else
    NSSearchPathDirectory base = NSApplicationSupportDirectory;
#endif
    NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:base
                                                            inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@"CoralogixRum" isDirectory:YES]
            URLByAppendingPathComponent:@"crashes" isDirectory:YES];
}

/// The report's own UUID, so the copy keeps the name the crash is known by on every launch. A
/// report that cannot be parsed still gets a unique name: recovery reads it, finds it unreadable
/// and deletes it.
static NSString *crx_reportFileName(NSData *data) {
    PLCrashReport *report = [[PLCrashReport alloc] initWithData:data error:NULL];
    NSString *uuid = nil;
    if (report.uuidRef != NULL) {
        uuid = CFBridgingRelease(CFUUIDCreateString(NULL, report.uuidRef));
    }
    return [(uuid ?: [NSUUID UUID].UUIDString) stringByAppendingPathExtension:@"plcrash"];
}

+ (BOOL)copyPendingReportOf:(PLCrashReporter *)reporter toDirectory:(NSURL *)directory {
    if (![reporter hasPendingCrashReport]) return NO;
    NSData *data = [reporter loadPendingCrashReportDataAndReturnError:NULL];
    if (data == nil) return NO;
    return crx_writeCopy(data, directory);
}

/// Writes `data` as its own copy in `directory`; an existing copy of the same report is replaced.
static BOOL crx_writeCopy(NSData *data, NSURL *directory) {
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
        return NO;
    }
    NSURL *file = [directory URLByAppendingPathComponent:crx_reportFileName(data)];
    return [data writeToURL:file options:NSDataWritingAtomic error:NULL];
}

+ (BOOL)movePendingReportOf:(PLCrashReporter *)reporter toDirectory:(NSURL *)directory {
    if (![CRXCrashBootstrap copyPendingReportOf:reporter toDirectory:directory]) return NO;
    [reporter purgePendingCrashReport];
    return YES;
}

+ (NSString *)claimLaunchSession {
    if (atomic_flag_test_and_set(&_crx_launchSessionClaimed)) return nil;
    return _crx_launchSessionId;
}

+ (void)resetLaunchSessionClaimForTesting {
    atomic_flag_clear(&_crx_launchSessionClaimed);
}

@end
