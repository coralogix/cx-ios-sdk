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
/// This runs before `main()` in every consuming app, so it only stamps values into statics — no
/// SDK state, configuration or I/O.
@interface CRXLaunchRecorder : NSObject

/// Whether the app has become active at least once in this process.
@property (class, nonatomic, readonly) BOOL hasRecordedFirstActivation;

/// `CFAbsoluteTimeGetCurrent()` at the first activation. Meaningful only when
/// `hasRecordedFirstActivation` is `YES`.
@property (class, nonatomic, readonly) CFAbsoluteTime firstDidBecomeActiveTime;

/// `YES` when the app entered the background before its first activation — the user left during
/// the launch, so process birth → first activation includes time spent away.
@property (class, nonatomic, readonly) BOOL launchWasInterrupted;

/// `YES` when the process was not started by the user: at `didFinishLaunching` its task role was
/// one known to mean a system start (`TASK_BACKGROUND_APPLICATION`, `TASK_DARWINBG_APPLICATION`,
/// `TASK_NONUI_APPLICATION` — a silent push, background fetch, location event). Reading the kernel
/// task role works the same for app-delegate and scene-based apps, unlike `applicationState` at
/// launch. Any other role, or a role that could not be read, gives `NO`, so a misread never
/// suppresses a real cold start.
@property (class, nonatomic, readonly) BOOL launchStartedInBackground;

/// The raw `task_role_t` read at `didFinishLaunching`, or `nil` before then or if it could not be
/// read. Diagnostic: it explains why a launch was or was not classified as a background start.
@property (class, nonatomic, readonly, nullable) NSNumber *launchTaskRole;

/// Whether `role` is one known to mean the system started the process. Every other role —
/// including ones not classified here — returns `NO`.
+ (BOOL)isSystemStartTaskRole:(NSInteger)role;

/// Returns `YES` exactly once per process. A process has one launch, but the SDK can be
/// initialized more than once in it (shutdown and re-init, a Flutter hot restart); without a
/// process-wide claim every init would report that one launch again.
+ (BOOL)claimColdStartReport;

@end

NS_ASSUME_NONNULL_END
