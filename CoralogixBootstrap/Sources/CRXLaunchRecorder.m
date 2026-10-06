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

/// `YES` only when the role was read and is something other than a user launch.
static bool crx_taskRoleIsBackground(void) {
    task_category_policy_data_t policy;
    mach_msg_type_number_t count = TASK_CATEGORY_POLICY_COUNT;
    boolean_t getDefault = FALSE;
    kern_return_t result = task_policy_get(mach_task_self(), TASK_CATEGORY_POLICY,
                                           (task_policy_t)&policy, &count, &getDefault);
    if (result != KERN_SUCCESS || getDefault) return false;
    return policy.role != TASK_FOREGROUND_APPLICATION;
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
            atomic_store(&_crx_launchStartedInBackground, crx_taskRoleIsBackground());
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

+ (BOOL)claimColdStartReport {
    return !atomic_flag_test_and_set(&_crx_coldStartClaimed);
}

@end
