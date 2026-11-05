//
//  CRXCrashBootstrap.m
//  CoralogixBootstrap
//

#import "CRXCrashBootstrap.h"
#import "CRXCrashContext.h"
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

+ (NSString *)claimLaunchSession {
    if (atomic_flag_test_and_set(&_crx_launchSessionClaimed)) return nil;
    return _crx_launchSessionId;
}

+ (void)resetLaunchSessionClaimForTesting {
    atomic_flag_clear(&_crx_launchSessionClaimed);
}

@end
