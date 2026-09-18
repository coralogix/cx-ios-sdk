//
//  CRXCrashBootstrap.m
//  CoralogixCrashBootstrap
//

#import "CRXCrashBootstrap.h"

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
/// That ordering is the synchronization — no lock is needed.
static PLCrashReporter *_crx_reporter;
static NSError *_crx_enableError;
static BOOL _crx_disabledByHostApp;

@implementation CRXCrashBootstrap

+ (void)load {
    @autoreleasepool {
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

@end
