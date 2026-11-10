//
//  CRXTerminateHandler.mm
//  CoralogixBootstrap
//

#import "CRXTerminateHandler.h"
#import "CRXCrashContextTerminate.h"
#import <objc/runtime.h>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <cxxabi.h>
#include <exception>
#include <stdexcept>
#include <typeinfo>

static std::terminate_handler _crx_previousTerminate;
static std::atomic_flag _crx_terminateInstalled = ATOMIC_FLAG_INIT;
static std::atomic_flag _crx_terminating = ATOMIC_FLAG_INIT;

/// An Objective-C exception's type is named after its class; a C++ type's name is mangled and
/// never names a class.
static bool crx_isObjCException(const char *typeName) {
    return objc_lookUpClass(typeName) != Nil;
}

/// Records the current exception, when it is a C++ one. Must run while it is current.
static bool crx_recordCurrentException(void) {
    std::type_info *type = abi::__cxa_current_exception_type();
    if (type == nullptr) return false;  // std::terminate called with no exception in flight
    const char *typeName = type->name();
    if (typeName == nullptr || typeName[0] == 0 || crx_isObjCException(typeName)) return false;

    char what[CRXCrashContextCxxMaxBytes + 1] = {0};
    bool hasWhat = false;
    try {
        throw;
    } catch (const std::exception &exception) {
        const char *message = exception.what();
        if (message != nullptr) {
            strlcpy(what, message, sizeof what);
            hasWhat = true;
        }
    } catch (...) {
        // Not a std::exception: its type is all there is to say.
    }
    return crx_writeCxxSection(typeName, hasWhat ? what : nullptr);
}

static void crx_terminate(void) {
    // A second terminate, from a throwing what() or another thread, goes straight on.
    if (!_crx_terminating.test_and_set()) {
        crx_recordCurrentException();
    }
    if (_crx_previousTerminate != nullptr) {
        _crx_previousTerminate();
    }
    abort();
}

@implementation CRXTerminateHandler

+ (BOOL)install {
    if (_crx_terminateInstalled.test_and_set()) return NO;
    _crx_previousTerminate = std::set_terminate(crx_terminate);
    return YES;
}

+ (BOOL)isInstalled {
    return _crx_previousTerminate != nullptr;
}

+ (BOOL)handsOverToItself {
    return _crx_previousTerminate == crx_terminate;
}

+ (NSString *)demangle:(NSString *)mangledName {
    int status = 0;
    char *demangled = abi::__cxa_demangle(mangledName.UTF8String, nullptr, nullptr, &status);
    if (demangled == nullptr) return nil;
    NSString *name = status == 0 ? [NSString stringWithUTF8String:demangled] : nil;
    free(demangled);
    return name;
}

+ (BOOL)recordRuntimeErrorForTesting:(NSString *)what {
    crx_terminateWriteIsTest = YES;
    try {
        throw std::runtime_error(what.UTF8String);
    } catch (...) {
        return crx_recordCurrentException();
    }
}

+ (BOOL)recordObjCExceptionForTesting {
    crx_terminateWriteIsTest = YES;
    @try {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"test" userInfo:nil];
    } @catch (NSException *exception) {
        return crx_recordCurrentException();
    }
}

@end
