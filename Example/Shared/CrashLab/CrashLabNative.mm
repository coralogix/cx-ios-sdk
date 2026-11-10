//
//  CrashLabNative.mm
//  DemoApp
//

#import "CrashLabNative.h"
#include <csetjmp>
#include <csignal>
#include <stdexcept>

static sigjmp_buf crashLabRecoveryPoint;

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

@end
