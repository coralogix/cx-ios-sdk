//
//  CRXCrashBootstrap.h
//  CoralogixBootstrap
//

#import <Foundation/Foundation.h>

@class PLCrashReporter;

NS_ASSUME_NONNULL_BEGIN

/// Enables PLCrashReporter at image load, before `main()`.
///
/// The SDK's own initialization runs whenever the host app calls it — in practice after
/// `FirebaseApp.configure()`, and in React Native / Flutter apps seconds after it, because
/// Firebase is configured natively while the SDK is initialized from JS / Dart. That ordering
/// silently loses crashes: Crashlytics owns the Mach exception ports, and while handling a
/// fault it restores the BSD signal handlers that existed when *it* installed its own. Handlers
/// registered after Crashlytics are not in that set, so ours is replaced by `SIG_DFL` and the
/// process dies before PLCrashReporter ever writes a report.
///
/// Installing from `+load` puts our `sigaction` in place before any code the host app runs, so
/// Crashlytics captures it as pre-existing and reinstalls it at crash time — the interoperability
/// path Crashlytics itself provides. No host-app change is required.
///
/// This is Objective-C because `+load` has no Swift equivalent, and it is a separate target
/// because SPM targets are single-language.
///
/// A host app that needs to opt out can set `CoralogixDisableEarlyCrashHandler` to `YES` in its
/// Info.plist; see `disabledByHostApp`. The key covers PLCrashReporter's signal handlers only:
/// the C++ terminate handler (`CRXTerminateHandler`) is installed from `+load` either way, and
/// records nothing until a reporter of ours is enabled.
@interface CRXCrashBootstrap : NSObject

/// The reporter enabled during `+load`, or `nil` if enabling failed (see `enableError`).
@property (class, nonatomic, readonly, nullable) PLCrashReporter *reporter;

/// Why enabling failed, if it did. Stored rather than logged: `Log` lives in a Swift module
/// that must not be pulled into a pre-`main()` path. The Swift side reports it at init.
@property (class, nonatomic, readonly, nullable) NSError *enableError;

/// `YES` when the host app set `CoralogixDisableEarlyCrashHandler` to `YES` in its Info.plist,
/// which skips the load-time install.
///
/// This is an escape hatch, not a configuration knob: it does not turn crash reporting off, it
/// reverts to the pre-`+load` behaviour where `initializeCrashInstrumentation` enables
/// PLCrashReporter itself. Crashes are still captured, but only from SDK init onwards — so a
/// crash reporter the host configures earlier can displace our handler again, which is the
/// failure this target exists to prevent.
@property (class, nonatomic, readonly) BOOL disabledByHostApp;

/// Returns the session id minted at image load, exactly once per process; `nil` afterwards, or
/// when `+load` never ran. The first session the SDK starts adopts it, so a crash report written
/// from load onwards already names that session. Minted even when the host app opted out, since
/// it costs nothing and crash context is still written once the fallback reporter is enabled.
+ (nullable NSString *)claimLaunchSession;

/// Where the SDK keeps its own copy of each crash report, one file per crash
/// (`<report uuid>.plcrash`). PLCrashReporter has a single pending-report slot, so a crash the
/// next launch could not deliver would be overwritten by the one after it; the copies are not.
@property (class, nonatomic, readonly, nullable) NSURL *crashCopiesDirectory;

/// Moves `reporter`'s pending report into `directory` and empties PLCrashReporter's slot.
/// The slot is emptied only once the copy is written, so a copy that fails — the file system is
/// still locked by data protection during prewarm, say — leaves the report for a later attempt.
/// Returns whether a report was moved.
+ (BOOL)movePendingReportOf:(PLCrashReporter *)reporter toDirectory:(NSURL *)directory;

/// Makes the launch session claimable again. Tests only: the first test to build the SDK would
/// otherwise consume it for the whole test process.
+ (void)resetLaunchSessionClaimForTesting;

@end

NS_ASSUME_NONNULL_END
