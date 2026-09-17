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

/// Written once from `+load` on the main thread, before any other code of ours can run, and
/// read-only afterwards. That ordering is the synchronization — no lock is needed.
static PLCrashReporter *_crx_reporter;
static NSError *_crx_enableError;

@implementation CRXCrashBootstrap

+ (void)load {
    @autoreleasepool {
        // Matches the configuration `initializeCrashInstrumentation` used before this target
        // existed, so enabling earlier changes ordering only, never report content.
        PLCrashReporterConfig *config =
            [[PLCrashReporterConfig alloc] initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD
                                              symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll];

        PLCrashReporter *reporter = [[PLCrashReporter alloc] initWithConfiguration:config];
        if (reporter == nil) {
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

@end
