//
//  CRXLaunchRecorder.h
//  CoralogixBootstrap
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Records the process's first `UIApplicationDidBecomeActiveNotification`, observed from `+load`.
///
/// Cold start is measured from process birth to the first activation. React Native and Flutter
/// apps initialize the SDK from JS / Dart, after that activation has already happened, so a
/// detector that only starts observing at init would finish on the *next* activation and report a
/// re-activation latency as a cold start. Observing from `+load` means the first activation is
/// always seen, however late the SDK is initialized.
///
/// This runs before `main()` in every consuming app, so it only stamps a timestamp — no SDK
/// state, configuration or I/O.
@interface CRXLaunchRecorder : NSObject

/// `CFAbsoluteTimeGetCurrent()` at the first activation, or `0` if the app has not been active yet.
@property (class, nonatomic, readonly) CFAbsoluteTime firstDidBecomeActiveTime;

/// Returns `YES` exactly once per process. A process has one launch, but the SDK can be
/// initialized more than once in it (shutdown and re-init, a Flutter hot restart); without a
/// process-wide claim every init would report that one launch again.
+ (BOOL)claimColdStartReport;

@end

NS_ASSUME_NONNULL_END
