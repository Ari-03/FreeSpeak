# FreeSpeak roadmap

The current implementation records in the app and lets its keyboard insert a completed transcript. The next milestone is a reliable daily dictation workflow on iPhone 17 or newer. Device measurements should drive model defaults and cross-app promises.

## 1. Establish the device baseline

Run the signed app and keyboard on iPhone 17 first, then a Pro model. Validate every installed engine with the same short recordings before adding features. Record exact phone, OS, runtime, and model versions.

Measure download size, cold preparation time, warm stop-to-text latency, peak physical memory, battery use, and thermal state. Separate transcription from cleanup. Include transitions between Parakeet, Whisper, Cohere, and S1-mini so retained model memory cannot hide behind single-engine benchmarks.

Use a small evaluation set containing quiet speech, street noise, silence, uncommon names, numbers, negation, false starts, and supported non-English speech. Score changes of meaning alongside transcription errors. Verify that cleanup failure preserves the original.

Exit condition: a published device matrix with working combinations, measured limits, and a recommended default. Keep Cohere experimental until it meets that bar. Validate its overlapping-window transcription against longer recordings, including cancellation latency and words at chunk boundaries.

## 2. Prove a supported background session

Build an isolated recording-session experiment using public APIs, a Live Activity, and explicit stop and timeout controls. Start recording in the foreground, switch to another app, then test repeated utterances through a lightweight keyboard command channel. App Group storage carries commands and results; it does not wake a suspended app by itself.

Separately test `AudioRecordingIntent` through Shortcuts and the Action Button. Compare warm app, cold app, force-quit, locked phone, disabled Live Activities, and denied microphone permission. Spokenly's documented workflow makes this worth investigating, but does not establish FreeSpeak's implementation or its behavior in each state.

Keep readiness, active microphone capture, transcription, and stopped states distinct. A session that keeps the microphone active must show that fact and release it when stopped or expired. Do not use silent playback or communication APIs to keep a dictation app alive.

Exit condition: a device-tested path with an honest activation step and recoverable interruption behavior. Add background audio capability only as part of that working recording feature. See [iOS platform research](research/ios-keyboard.md) and [competitor workflows](research/product-experience.md).

## 3. Finish cross-app delivery

Expand the current single-result inbox into session state with utterance IDs, command IDs, freshness, and explicit completion states. Add mode selection in the keyboard without opening the app. Preserve completed text when the destination field disappears or the extension restarts.

The current insertion receipt is written before calling the text proxy, preventing routine repeats at the cost of a possible interrupted insertion. Test this boundary and provide an explicit recovery action. Do not promise exactly-once insertion because storage and the destination app cannot participate in one transaction.

Exit condition: recorded fault tests for stale sessions, reconnects, duplicate commands, extension termination, and destination changes, with text recoverable in the app.

## 4. Make storage and models predictable

Pin model artifact revisions and checksums in addition to runtime versions. S1-mini already checks its pinned artifact; FluidAudio and Whisper conversions need equivalent reproducibility. Add storage estimates, useful download progress, partial-download cleanup, and failed-download recovery.

Implement deliberate audio retention and recovery across relaunch. Define how disabling history affects pending audio, the latest result, and the keyboard inbox. Add schema migration before changing persisted mode or settings structures again. Verify delete-all behavior across both app and shared storage.

Exit condition: installation, upgrade, cancellation, low-storage failure, and deletion preserve the user's expected data and do not label incomplete models ready.

## 5. Refine modes and vocabulary

Keep recognition hints separate from explicit word replacements. Add replacements with word boundaries, overlap handling, and a preview before saving broad rules. Expose each local model's actual vocabulary capability instead of silently ignoring a shared vocabulary list.

Keep S1-mini's finite style, structure, and context controls separate from arbitrary cloud instructions. Add a mode preview using a saved transcript. Improve language selection with supported-language checks and make mixed-language preservation part of evaluation.

Exit condition: names and formatting improve on the evaluation set without changing facts or silently translating speech.

## 6. Prepare a distributable app

Validate Dynamic Type, VoiceOver, Reduce Motion, keyboard layouts, and one-handed controls on devices. Complete app icon and onboarding, model license attribution, privacy disclosures, signing, and release tests. Review keyboard and background behavior against current Apple requirements before submission.

Account sync, automatic app-specific modes, swipe typing, prediction, meeting capture, and usage statistics can follow the reliable dictation workflow. They should not delay discovering whether the main cross-app interaction works.
