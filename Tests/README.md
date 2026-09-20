# Cloud service contract tests

Run `bash Tests/run-cloud-tests.sh` on macOS with the Xcode command-line tools installed.

The harness compiles the actual app models and cloud service using Swift 6, then injects a URLSession whose URLProtocol intercepts every request. It needs no API keys and makes no network calls. No Xcode test target or package dependency is required.

Checks cover provider endpoints, authorization, multipart audio and vocabulary, xAI's required file ordering, upload limits, invalid credentials, response parsing, safe HTTP and network failures, cleanup refusal and truncation, verbatim bypass, and cancellation.

## Recording lifecycle and persistence

Run `bash Tests/run-app-store-tests.sh` to compile the production AppStore and model types with controllable service doubles. Every store uses a temporary storage directory; the harness does not read your app data, microphone, models, or API keys.

Checks cover duplicate retries, transcription cancellation, captured provider settings, preserving ASR text when cleanup is cancelled, disabling or deleting history during transcription, unreadable-state recovery, deleting recovery copies, and blocking transcription during model downloads. Microphone interruption behavior still needs a physical device check.

## Audio responsiveness

Run `bash Tests/run-audio-tests.sh`. This compiles the production audio-operation bridge and blocks a fake synchronous driver call on its serial queue. It checks that a main-actor heartbeat still runs, timeout and cancellation return promptly, late recordings are discarded, and the queue can subsequently accept work. It does not claim successful microphone capture on a physical device.

For the actual simulator UI, open Dictate with a configured provider and run:

```sh
bash Tests/check-microphone-ui.sh /path/to/pinned-agent-device-wrapper
```

The wrapper should forward arguments to the agent-device command and target arguments provided by T3's Device panel. The check taps Start dictating and verifies tab navigation still works. It leaves the app on Modes; cancel recording afterward if your microphone starts successfully.

The September 19 freeze reproduced inside `AVAudioRecorder.record(forDuration:)` while the simulator's AudioQueue waited for CoreAudio. Ordinary `record()` and a default play-and-record session also froze. Moving all audio operations to a serial worker and bounding the caller's wait fixed UI responsiveness, with timeout and late-result cleanup. Hardware audio can still fail independently; the app reports that failure without blocking its interface.
