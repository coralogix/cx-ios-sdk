//
//  CrashLabNative.h
//  DemoApp
//
//  Crash Lab triggers that need C, C++ or Objective-C: Swift has no inline assembly, no C++
//  exceptions and no setjmp.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CrashLabNative : NSObject

/// Throws an uncaught `std::runtime_error("crash lab C++ exception")`.
+ (void)throwCppException;

/// Executes an undefined instruction: a real SIGILL.
+ (void)illegalInstruction;

/// `__builtin_trap()`: a real SIGTRAP.
+ (void)breakpoint;

/// Installs its own SIGSEGV handler, faults, recovers in that handler and restores the handler
/// it found. The process lives on and nothing is reported.
+ (void)faultAndRecover;

/// Starts two threads that wait for each other and then both write through a null pointer, so
/// each faults while the other is faulting. Returns at once; the process dies shortly after.
+ (void)faultOnTwoThreadsAtOnce;

@end

NS_ASSUME_NONNULL_END
