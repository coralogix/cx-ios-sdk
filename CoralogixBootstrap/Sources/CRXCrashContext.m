//
//  CRXCrashContext.m
//  CoralogixBootstrap
//

#import "CRXCrashContext.h"
#import "CRXCrashContextTerminate.h"
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
/// The envelope last handed to PLCR, so the terminate handler can add its section to it without
/// encoding JSON while the process is going down.
static NSData *_crx_lastEnvelope;
/// Where the terminate-time envelope is built: preallocated, so terminate allocates only the one
/// `NSData` PLCR's API takes.
static uint8_t _crx_terminateBuffer[8192];

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
    _crx_lastEnvelope = data;
    return YES;
}

#pragma mark - Terminate time

/// Appends `s` as a JSON string, reading at most `maxInput` bytes of it. Invalid UTF-8 becomes
/// `?`, so the envelope stays valid JSON and the session it carries is never lost to a byte of
/// `what()`. Returns the new position, or 0 when `capacity` is reached.
static size_t crx_appendJSONString(uint8_t *out, size_t capacity, size_t pos, const char *s, size_t maxInput) {
    static const char hex[] = "0123456789abcdef";
#define CRX_PUT(byte) do { if (pos >= capacity) return 0; out[pos++] = (uint8_t)(byte); } while (0)
    CRX_PUT('"');
    const uint8_t *bytes = (const uint8_t *)(s ?: "");
    size_t i = 0;
    while (i < maxInput && bytes[i] != 0) {
        uint8_t c = bytes[i];
        if (c < 0x80) {
            if (c == '"' || c == '\\') {
                CRX_PUT('\\'); CRX_PUT(c);
            } else if (c < 0x20) {
                CRX_PUT('\\'); CRX_PUT('u'); CRX_PUT('0'); CRX_PUT('0');
                CRX_PUT(hex[c >> 4]); CRX_PUT(hex[c & 0xF]);
            } else {
                CRX_PUT(c);
            }
            i += 1;
            continue;
        }
        // The length of a well-formed sequence and the range its second byte must fall in.
        size_t length = 0;
        uint8_t low = 0x80, high = 0xBF;
        if (c >= 0xC2 && c <= 0xDF) { length = 2; }
        else if (c == 0xE0) { length = 3; low = 0xA0; }
        else if (c == 0xED) { length = 3; high = 0x9F; }
        else if (c >= 0xE1 && c <= 0xEF) { length = 3; }
        else if (c == 0xF0) { length = 4; low = 0x90; }
        else if (c >= 0xF1 && c <= 0xF3) { length = 4; }
        else if (c == 0xF4) { length = 4; high = 0x8F; }

        if (length > 0 && i + length > maxInput) break;  // cut at the bound, never mid-character
        BOOL valid = length > 0;
        for (size_t k = 1; valid && k < length; k++) {
            uint8_t next = bytes[i + k];
            valid = (k == 1) ? (next >= low && next <= high) : (next >= 0x80 && next <= 0xBF);
        }
        if (valid) {
            for (size_t k = 0; k < length; k++) CRX_PUT(bytes[i + k]);
            i += length;
        } else {
            CRX_PUT('?');
            i += 1;
        }
    }
    CRX_PUT('"');
#undef CRX_PUT
    return pos;
}

static size_t crx_appendBytes(uint8_t *out, size_t capacity, size_t pos, const void *bytes, size_t length) {
    if (pos + length > capacity) return 0;
    memcpy(out + pos, bytes, length);
    return pos + length;
}

size_t crx_envelopeWithCxxSection(const uint8_t *envelope, size_t envelopeLength,
                                  const char *type, const char *what,
                                  uint8_t *buffer, size_t capacity) {
    if (type == NULL || type[0] == 0) return 0;
    size_t pos = 0;
    // An object written by NSJSONSerialization: reopen it after its last member.
    if (envelopeLength >= 2 && envelope[0] == '{' && envelope[envelopeLength - 1] == '}') {
        pos = crx_appendBytes(buffer, capacity, 0, envelope, envelopeLength - 1);
        if (pos == 0) return 0;
        if (envelopeLength > 2 && !(pos = crx_appendBytes(buffer, capacity, pos, ",", 1))) return 0;
    } else {
        char opening[32];
        int written = snprintf(opening, sizeof opening, "{\"%s\":%ld,",
                               CRXCrashContextKeyVersion.UTF8String, (long)CRXCrashContextVersion);
        if (written <= 0 || (size_t)written >= sizeof opening) return 0;
        if (!(pos = crx_appendBytes(buffer, capacity, 0, opening, (size_t)written))) return 0;
    }
    const char *cxxKey = CRXCrashContextKeyCxx.UTF8String;
    const char *typeKey = CRXCrashContextKeyCxxType.UTF8String;
    const char *whatKey = CRXCrashContextKeyCxxWhat.UTF8String;
    if (!(pos = crx_appendJSONString(buffer, capacity, pos, cxxKey, SIZE_MAX))) return 0;
    if (!(pos = crx_appendBytes(buffer, capacity, pos, ":{", 2))) return 0;
    if (!(pos = crx_appendJSONString(buffer, capacity, pos, typeKey, SIZE_MAX))) return 0;
    if (!(pos = crx_appendBytes(buffer, capacity, pos, ":", 1))) return 0;
    if (!(pos = crx_appendJSONString(buffer, capacity, pos, type, CRXCrashContextCxxMaxBytes))) return 0;
    if (what != NULL) {
        if (!(pos = crx_appendBytes(buffer, capacity, pos, ",", 1))) return 0;
        if (!(pos = crx_appendJSONString(buffer, capacity, pos, whatKey, SIZE_MAX))) return 0;
        if (!(pos = crx_appendBytes(buffer, capacity, pos, ":", 1))) return 0;
        if (!(pos = crx_appendJSONString(buffer, capacity, pos, what, CRXCrashContextCxxMaxBytes))) return 0;
    }
    return crx_appendBytes(buffer, capacity, pos, "}}", 2);
}

BOOL crx_writeCxxSection(const char *type, const char *what) {
    // Never wait: the thread going down may be the one holding the lock.
    if (!os_unfair_lock_trylock(&_crx_contextLock)) return NO;
    BOOL written = NO;
    if (_crx_activeReporter != nil) {
        size_t length = crx_envelopeWithCxxSection(_crx_lastEnvelope.bytes, _crx_lastEnvelope.length, type, what,
                                                   _crx_terminateBuffer, sizeof _crx_terminateBuffer);
        if (length > 0) {
            _crx_activeReporter.customData = [NSData dataWithBytes:_crx_terminateBuffer length:length];
            written = YES;
        }
    }
    os_unfair_lock_unlock(&_crx_contextLock);
    return written;
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

+ (NSData *)envelopeWithCxxType:(NSString *)type what:(NSString *)what {
    os_unfair_lock_lock(&_crx_contextLock);
    NSData *base = _crx_lastEnvelope;
    os_unfair_lock_unlock(&_crx_contextLock);
    uint8_t buffer[sizeof _crx_terminateBuffer];
    size_t length = crx_envelopeWithCxxSection(base.bytes, base.length, type.UTF8String, what.UTF8String,
                                               buffer, sizeof buffer);
    return length > 0 ? [NSData dataWithBytes:buffer length:length] : nil;
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
