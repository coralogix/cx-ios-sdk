//
//  CRXLaunchRecorder.m
//  CoralogixBootstrap
//

#import "CRXLaunchRecorder.h"
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <stdatomic.h>

/// Written on the main thread when the notifications fire; read from whatever thread the SDK is
/// initialized on.
static _Atomic(CFAbsoluteTime) _crx_firstDidBecomeActiveTime = 0;
static _Atomic(bool) _crx_launchWasInterrupted = false;
static _Atomic(bool) _crx_launchStartedInBackground = false;
static _Atomic(bool) _crx_launchTaskRoleRead = false;
static _Atomic(int) _crx_launchTaskRole = 0;

static atomic_flag _crx_coldStartClaimed = ATOMIC_FLAG_INIT;

/// Set in `+load` and cleared by their first delivery, all on the main thread.
static id _crx_activeObserver;
static id _crx_backgroundObserver;
static id _crx_launchObserver;

static void crx_removeObserver(id __strong *observer) {
    if (*observer == nil) return;
    [[NSNotificationCenter defaultCenter] removeObserver:*observer];
    *observer = nil;
}

/// Reads the task role into the statics and returns whether it marks a launch the user did not
/// start.
static bool crx_recordTaskRole(void) {
    task_category_policy_data_t policy;
    mach_msg_type_number_t count = TASK_CATEGORY_POLICY_COUNT;
    boolean_t getDefault = FALSE;
    kern_return_t result = task_policy_get(mach_task_self(), TASK_CATEGORY_POLICY,
                                           (task_policy_t)&policy, &count, &getDefault);
    if (result != KERN_SUCCESS || getDefault) return false;

    atomic_store(&_crx_launchTaskRole, policy.role);
    atomic_store(&_crx_launchTaskRoleRead, true);
    return [CRXLaunchRecorder isSystemStartTaskRole:policy.role];
}

@implementation CRXLaunchRecorder

+ (void)load {
    // No autorelease pool exists before main(); the observer tokens are autoreleased.
    @autoreleasepool {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        _crx_launchObserver = [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                  object:nil
                                                   queue:nil
                                              usingBlock:^(NSNotification *note) {
            atomic_store(&_crx_launchStartedInBackground, crx_recordTaskRole());
            crx_removeObserver(&_crx_launchObserver);
        }];

        _crx_backgroundObserver = [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
            atomic_store(&_crx_launchWasInterrupted, true);
            crx_removeObserver(&_crx_backgroundObserver);
        }];

        _crx_activeObserver = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                                  object:nil
                                                   queue:nil
                                              usingBlock:^(NSNotification *note) {
            atomic_store(&_crx_firstDidBecomeActiveTime, CFAbsoluteTimeGetCurrent());
            // Backgrounding after the first activation is an ordinary warm cycle, not an
            // interrupted launch.
            crx_removeObserver(&_crx_backgroundObserver);
            crx_removeObserver(&_crx_activeObserver);
        }];
    }
}

+ (BOOL)hasRecordedFirstActivation {
    return atomic_load(&_crx_firstDidBecomeActiveTime) > 0;
}

+ (CFAbsoluteTime)firstDidBecomeActiveTime {
    return atomic_load(&_crx_firstDidBecomeActiveTime);
}

+ (BOOL)launchWasInterrupted {
    return atomic_load(&_crx_launchWasInterrupted);
}

+ (BOOL)launchStartedInBackground {
    return atomic_load(&_crx_launchStartedInBackground);
}

+ (BOOL)isSystemStartTaskRole:(NSInteger)role {
    // Fails open: only roles known to mean "not started by the user" count, so a role nobody has
    // classified — or one a future iOS gives a user launch — keeps the cold start and falls back to
    // the 60 s cap rather than silently dropping it.
    switch (role) {
        case TASK_BACKGROUND_APPLICATION:
        case TASK_DARWINBG_APPLICATION:
        case TASK_NONUI_APPLICATION:
            return YES;
        default:
            return NO;
    }
}

+ (nullable NSNumber *)launchTaskRole {
    if (!atomic_load(&_crx_launchTaskRoleRead)) return nil;
    return @(atomic_load(&_crx_launchTaskRole));
}

+ (BOOL)claimColdStartReport {
    return !atomic_flag_test_and_set(&_crx_coldStartClaimed);
}

@end
