//
//  CRXCrashContextTerminate.h
//  CoralogixBootstrap
//
//  The terminate handler's way into `CRXCrashContext`. Private to this target.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How many bytes of the exception's type and of `what()` the envelope keeps: well above the
/// 102 UTF-16 units a crash message is cut to, so the cut is made where every message is cut.
enum { CRXCrashContextCxxMaxBytes = 256 };

#ifdef __cplusplus
extern "C" {
#endif

/// Writes `envelope` (an encoded JSON object, or empty for none) with a `cxx` section added into
/// `buffer`. Returns the length written, or 0 when it does not fit or `type` is empty.
/// Allocates nothing.
size_t crx_envelopeWithCxxSection(const uint8_t *_Nullable envelope, size_t envelopeLength,
                                  const char *type, const char *_Nullable what,
                                  uint8_t *buffer, size_t capacity);

/// Set by the test hooks, which record an exception the process survives: the envelope is then
/// left writable afterwards.
extern BOOL crx_terminateWriteIsTest;

/// Adds the `cxx` section to the envelope last written and hands it to PLCR, then keeps the
/// envelope as it is for the rest of the process. Never blocks:
/// returns `NO` when the lock is held elsewhere, no reporter of ours is active, or it does not fit.
BOOL crx_writeCxxSection(const char *type, const char *_Nullable what);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
