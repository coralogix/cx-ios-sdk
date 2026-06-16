//
//  SessionReplayOptions+InitLogSnapshot.swift
//  SessionReplay
//
//  CX-44984: single source of truth for the session-replay init-log payload.
//

import Foundation
import CoralogixInternal

extension SessionReplayOptions {
    /// Builds the `internal_event_data` payload for the session-replay init log.
    ///
    /// Keys mirror the Android (CX-44992) snapshot so the backend ingests one cross-platform
    /// schema. The `flutterViewBitmapProvider` closure is reduced to a presence flag — never
    /// serialised. `captureTimeInterval` is excluded: it is deprecated and not user-tunable.
    ///
    /// iOS divergence (follow-up to align Android): iOS has no `maskAllTexts` boolean or
    /// `maskInputFieldsOfTypes` — text masking is expressed solely via `maskText`, emitted here
    /// as `textsToMask`. iOS-only fields (`recordingType`, `maskOnlyCreditCards`, `maskFaces`,
    /// `creditCardPredicate`) are included and should be added to the Android payload.
    func toSessionReplayInitLogSnapshot() -> [String: Any] {
        return [
            Keys.srRecordingType.rawValue: recordingType == .video ? Keys.video.rawValue : Keys.image.rawValue,
            Keys.srCaptureScale.rawValue: Double(captureScale),
            Keys.srCaptureCompressQuality.rawValue: Double(captureCompressionQuality),
            Keys.srSessionRecordingSampleRate.rawValue: sessionRecordingSampleRate,
            Keys.srAutoStartSessionRecording.rawValue: autoStartSessionRecording,
            Keys.srTextsToMask.rawValue: maskText ?? [],
            Keys.srMaskAllImages.rawValue: maskAllImages,
            Keys.srMaskOnlyCreditCards.rawValue: maskOnlyCreditCards,
            Keys.srMaskFaces.rawValue: maskFaces,
            Keys.srCreditCardPredicate.rawValue: creditCardPredicate ?? [],
            Keys.srHasFlutterViewBitmapProvider.rawValue: flutterViewBitmapProvider != nil
        ]
    }
}
