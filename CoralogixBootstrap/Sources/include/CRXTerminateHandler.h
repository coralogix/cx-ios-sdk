//
//  CRXTerminateHandler.h
//  CoralogixBootstrap
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Records what an uncaught C++ exception was, so its crash report says more than `SIGABRT`.
///
/// PLCrashReporter records an uncaught C++ exception as a bare `SIGABRT`: the exception's type
/// and `what()` are gone by the time the signal arrives. This terminate handler runs first, adds
/// them to the crash context as a `cxx` section, and hands over to the handler it replaced, so
/// the process ends exactly as it would have. The type is kept mangled and demangled on the next
/// launch; nothing is formatted while the process is going down.
///
/// Installed once from `+load`, whatever `CoralogixDisableEarlyCrashHandler` says. Uncaught
/// Objective-C exceptions pass through it too and are left to PLCrashReporter, which already
/// records them.
@interface CRXTerminateHandler : NSObject

/// Installs the handler. Only the first call does anything: a second would make the handler
/// hand over to itself. Returns whether this call installed it.
+ (BOOL)install;

/// Whether it was installed, with a handler to hand over to. It need not be the current handler:
/// one installed later (XCTest's, say) runs first and hands over to it.
@property (class, nonatomic, readonly) BOOL isInstalled;

/// Whether the handler this one hands over to is itself. Never true; for tests.
@property (class, nonatomic, readonly) BOOL handsOverToItself;

/// A mangled C++ type name as source would spell it (`St13runtime_error` → `std::runtime_error`),
/// or `nil` when it is not a mangled name.
+ (nullable NSString *)demangle:(NSString *)mangledName;

/// Throws a `std::runtime_error` with `what`, and records it while it is the current exception,
/// as the handler would at terminate. Returns whether a `cxx` section was written. For tests.
+ (BOOL)recordRuntimeErrorForTesting:(NSString *)what NS_SWIFT_NAME(recordRuntimeErrorForTesting(_:));

/// Throws an `NSException`, and records it while it is the current exception, as the handler
/// would at terminate. Returns whether a `cxx` section was written: never. For tests.
+ (BOOL)recordObjCExceptionForTesting;

@end

NS_ASSUME_NONNULL_END
