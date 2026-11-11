//
//  CRXConcurrentCrashGuard.h
//  CoralogixBootstrap
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Lets one crash report be written when two threads crash at the same moment.
///
/// PLCrashReporter's signal handler resets every crash signal to its default action as it starts,
/// before it stops the other threads. A second thread that faults in that window gets the default
/// action, which kills the process while the first is still writing, and no report is left. Two
/// threads entering that handler together fare no better: both write the one report file.
///
/// The guard sits in front of PLCrashReporter's handler for the same signals. The first thread to
/// reach it stops every other thread and only then hands over, so the reset can no longer catch a
/// second fault. A thread that reaches it while another is being handled waits instead; the
/// process ends when the first report is written.
@interface CRXConcurrentCrashGuard : NSObject

/// Puts the guard in front of the handlers currently installed for PLCrashReporter's signals.
/// Call it right after a reporter of ours is enabled, so that what it hands over to is
/// PLCrashReporter's handler. Installs once per process; returns `NO` on any later call.
+ (BOOL)install;

/// Whether the guard is what the system calls for each of PLCrashReporter's signals.
+ (BOOL)isHandlingEverySignal;

/// Whether any signal would be handed back to the guard itself — a loop instead of a report.
+ (BOOL)handsOverToItself;

@end

NS_ASSUME_NONNULL_END
