//
//  CRXCrashContext.h
//  CoralogixBootstrap
//

#import <Foundation/Foundation.h>

@class PLCrashReporter;

NS_ASSUME_NONNULL_BEGIN

/// Wire keys of the crash context. Defined here because `+load` cannot reach Swift;
/// `Keys.swift` mirrors them and a test keeps the two sets equal. The session keys are the
/// Android SDK's, so a crash carries its session the same way on both platforms.
FOUNDATION_EXPORT NSString *const CRXCrashContextKeyVersion;            // "v"
FOUNDATION_EXPORT NSString *const CRXCrashContextKeySession;            // "session"
FOUNDATION_EXPORT NSString *const CRXCrashContextKeySessionId;          // "session_id"
FOUNDATION_EXPORT NSString *const CRXCrashContextKeySessionCreationTime; // "session_creation_time", epoch ms
FOUNDATION_EXPORT NSString *const CRXCrashContextKeySessionSampledIn;   // "is_session_sampled_in"
FOUNDATION_EXPORT NSString *const CRXCrashContextKeyCxx;                // "cxx"
FOUNDATION_EXPORT NSString *const CRXCrashContextKeyCxxType;            // "type"
FOUNDATION_EXPORT NSString *const CRXCrashContextKeyCxxWhat;            // "what"

/// The envelope version this build writes. A reader treats any other version as no context.
FOUNDATION_EXPORT const NSInteger CRXCrashContextVersion;

/// The single owner of PLCrashReporter's custom data: a small versioned JSON dictionary, one
/// section per concern, that every crash report written from now on carries.
///
/// PLCrashReporter keeps custom data in one process-wide writer whichever instance sets it, and
/// `enable` resets that writer. So the data is written only through the reporter this SDK
/// enabled itself, and written again whenever that reporter is set. A reporter the host app
/// enabled (App Center, say) is never written to: its data is not ours to replace.
///
/// A write frees and reallocates the buffer the crash-time writer reads, with nothing PLCR offers
/// to synchronise the two. Callers keep writes rare: session changes, never per event.
@interface CRXCrashContext : NSObject

/// The reporter this SDK enabled, or `nil` when it enabled none. Set from `+load` on success and
/// by the init-time fallback after its own `enable` succeeded. Setting it writes the sections
/// held so far.
@property (class, nonatomic, nullable) PLCrashReporter *activeReporter;

/// Replaces one section (`nil` removes it) and writes the whole envelope. Returns whether it was
/// written: `NO` while no reporter of ours is active, in which case the section is kept and
/// written once one is.
+ (BOOL)setSection:(NSString *)name value:(nullable NSDictionary<NSString *, id> *)value;

/// The sections held now, as they would be encoded. For tests and diagnostics.
@property (class, nonatomic, readonly) NSDictionary<NSString *, id> *sections;

/// The envelope as the terminate handler would write it for an uncaught C++ exception of
/// `type` (mangled) with `what`: the envelope last written plus a `cxx` section. For tests.
+ (nullable NSData *)envelopeWithCxxType:(NSString *)type what:(nullable NSString *)what;

/// Every key the envelope can carry, for the parity test with `Keys.swift`.
@property (class, nonatomic, readonly) NSSet<NSString *> *allKeys;

@end

NS_ASSUME_NONNULL_END
