//
//  CRXLaunchRecorder.m
//  CoralogixBootstrap
//

#import "CRXLaunchRecorder.h"
#import <UIKit/UIKit.h>
#import <stdatomic.h>

/// Written on the main thread when the notification fires; read from whatever thread the SDK is
/// initialized on.
static _Atomic(CFAbsoluteTime) _crx_firstDidBecomeActiveTime = 0;

static atomic_flag _crx_coldStartClaimed = ATOMIC_FLAG_INIT;

/// Set in `+load` and cleared by the first delivery, both on the main thread.
static id _crx_observer;

@implementation CRXLaunchRecorder

+ (void)load {
    // No autorelease pool exists before main(); the observer token is autoreleased.
    @autoreleasepool {
        _crx_observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
                        atomic_store(&_crx_firstDidBecomeActiveTime, CFAbsoluteTimeGetCurrent());
                        [[NSNotificationCenter defaultCenter] removeObserver:_crx_observer];
                        _crx_observer = nil;
                    }];
    }
}

+ (BOOL)claimColdStartReport {
    return !atomic_flag_test_and_set(&_crx_coldStartClaimed);
}

+ (CFAbsoluteTime)firstDidBecomeActiveTime {
    return atomic_load(&_crx_firstDidBecomeActiveTime);
}

@end
