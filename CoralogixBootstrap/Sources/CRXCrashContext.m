//
//  CRXCrashContext.m
//  CoralogixBootstrap
//

#import "CRXCrashContext.h"
#import <os/lock.h>

#if __has_include(<CrashReporter/CrashReporter.h>)
#import <CrashReporter/CrashReporter.h>
#elif __has_include("CrashReporter.h")
#import "CrashReporter.h"
#else
@import CrashReporter;
#endif

NSString *const CRXCrashContextKeyVersion = @"v";
NSString *const CRXCrashContextKeySession = @"session";
NSString *const CRXCrashContextKeySessionId = @"session_id";
NSString *const CRXCrashContextKeySessionCreationTime = @"session_creation_time";
NSString *const CRXCrashContextKeySessionSampledIn = @"is_session_sampled_in";
NSString *const CRXCrashContextKeyCxx = @"cxx";
NSString *const CRXCrashContextKeyCxxType = @"type";
NSString *const CRXCrashContextKeyCxxWhat = @"what";

const NSInteger CRXCrashContextVersion = 1;

/// Guards both statics and every `setCustomData:` call: two concurrent writes into PLCR's writer
/// would free the same buffer twice.
static os_unfair_lock _crx_contextLock = OS_UNFAIR_LOCK_INIT;
static PLCrashReporter *_crx_activeReporter;
static NSMutableDictionary<NSString *, id> *_crx_sections;

@implementation CRXCrashContext

/// Must be called with the lock held. Returns whether the envelope reached PLCR.
static BOOL crx_writeLocked(void) {
    if (_crx_activeReporter == nil) return NO;

    NSData *data = nil;
    if (_crx_sections.count > 0) {
        NSMutableDictionary *envelope = [_crx_sections mutableCopy];
        envelope[CRXCrashContextKeyVersion] = @(CRXCrashContextVersion);
        if (![NSJSONSerialization isValidJSONObject:envelope]) return NO;
        data = [NSJSONSerialization dataWithJSONObject:envelope options:NSJSONWritingSortedKeys error:NULL];
        if (data == nil) return NO;
    }
    // nil clears the field rather than writing an empty one.
    _crx_activeReporter.customData = data;
    return YES;
}

+ (PLCrashReporter *)activeReporter {
    os_unfair_lock_lock(&_crx_contextLock);
    PLCrashReporter *reporter = _crx_activeReporter;
    os_unfair_lock_unlock(&_crx_contextLock);
    return reporter;
}

+ (void)setActiveReporter:(PLCrashReporter *)reporter {
    os_unfair_lock_lock(&_crx_contextLock);
    _crx_activeReporter = reporter;
    crx_writeLocked();
    os_unfair_lock_unlock(&_crx_contextLock);
}

+ (BOOL)setSection:(NSString *)name value:(NSDictionary<NSString *, id> *)value {
    os_unfair_lock_lock(&_crx_contextLock);
    if (_crx_sections == nil) {
        _crx_sections = [NSMutableDictionary dictionary];
    }
    _crx_sections[name] = [value copy];
    BOOL written = crx_writeLocked();
    os_unfair_lock_unlock(&_crx_contextLock);
    return written;
}

+ (NSDictionary<NSString *, id> *)sections {
    os_unfair_lock_lock(&_crx_contextLock);
    NSDictionary *sections = [_crx_sections copy] ?: @{};
    os_unfair_lock_unlock(&_crx_contextLock);
    return sections;
}

+ (NSSet<NSString *> *)allKeys {
    return [NSSet setWithArray:@[CRXCrashContextKeyVersion,
                                 CRXCrashContextKeySession,
                                 CRXCrashContextKeySessionId,
                                 CRXCrashContextKeySessionCreationTime,
                                 CRXCrashContextKeySessionSampledIn,
                                 CRXCrashContextKeyCxx,
                                 CRXCrashContextKeyCxxType,
                                 CRXCrashContextKeyCxxWhat]];
}

@end
