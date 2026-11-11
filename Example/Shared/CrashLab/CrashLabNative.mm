//
//  CrashLabNative.mm
//  DemoApp
//

#import "CrashLabNative.h"
#include <atomic>
#include <csetjmp>
#include <pthread.h>
#include <csignal>
#include <stdexcept>

static sigjmp_buf crashLabRecoveryPoint;

static std::atomic<int> crashLabFaultersReady{0};

// Spins rather than blocking on a semaphore: a woken waiter is scheduled late enough that the
// first fault is often fully handled before the second one happens.
static void *crashLabFaultWithTheOther(void *) {
    crashLabFaultersReady.fetch_add(1);
    while (crashLabFaultersReady.load() < 2) {}
    volatile int *invalid = (volatile int *)0x8;
    *invalid = 1;
    return nullptr;
}

static void crashLabRecover(int signal) {
    siglongjmp(crashLabRecoveryPoint, 1);
}

@implementation CrashLabNative

+ (void)throwCppException {
    throw std::runtime_error("crash lab C++ exception");
}

+ (void)illegalInstruction {
#if defined(__arm64__) || defined(__aarch64__)
    __asm__ volatile(".inst 0x00000000");  // udf #0
#else
    __asm__ volatile("ud2");
#endif
}

+ (void)breakpoint {
    __builtin_trap();
}

+ (void)faultAndRecover {
    struct sigaction recover = {};
    recover.sa_handler = crashLabRecover;
    sigemptyset(&recover.sa_mask);
    struct sigaction previousSegv, previousBus;
    sigaction(SIGSEGV, &recover, &previousSegv);
    sigaction(SIGBUS, &recover, &previousBus);
    if (sigsetjmp(crashLabRecoveryPoint, 1) == 0) {
        volatile int *invalid = (volatile int *)0x8;
        *invalid = 1;
    }
    sigaction(SIGSEGV, &previousSegv, NULL);
    sigaction(SIGBUS, &previousBus, NULL);
}

+ (void)faultOnTwoThreadsAtOnce {
    for (int i = 0; i < 2; i++) {
        pthread_t thread;
        pthread_create(&thread, nullptr, crashLabFaultWithTheOther, nullptr);
    }
}

@end
