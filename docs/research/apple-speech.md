# Apple Speech on iPhone

Checked September 19, 2026 against Apple's documentation and the installed iOS 26.5 SDK. The service uses APIs available since iOS 26.0.

## Implementation

`AppleSpeechService.transcribe(url:locale:)` accepts a recorded audio file and returns the final transcript. It runs `SpeechTranscriber` inside `SpeechAnalyzer`, checks device and language support, installs missing language assets, and finalizes analysis before returning. Apple's final results arrive in passage order. The service uses the `.transcription` preset and appends only final text, avoiding repeated partial results. See [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) and [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer).

`analyzeSequence(from:)` finishes reading the file before analysis necessarily finishes. The service uses its returned last sample time with `finalizeAndFinish(through:)` and consumes the results stream concurrently. Cancellation stops the analyzer and waits for the result consumer to exit. See [file analysis](https://developer.apple.com/documentation/speech/speechanalyzer/analyzesequence(from:)).

## Download and privacy behavior

Apple owns and updates the language models. They run on device and use system storage. The first transcription for a language can need a download, so the first run is not guaranteed to work offline. Once assets are installed, this implementation never sends the recording to an external service. See [Apple's SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/).

`AssetInventory.assetInstallationRequest(supporting:)` returns no request when assets are already installed. It automatically reserves any required locales and throws if the app has exhausted its locale reservations. This implementation preserves those reservations for future sessions and propagates installation errors. A future language manager should expose download progress and let the user release unused languages. See [asset installation requests](https://developer.apple.com/documentation/speech/assetinventory/assetinstallationrequest(supporting:)).

Apple says the speech authorization flow for `SFSpeechRecognizer` does not apply to `SpeechAnalyzer` transcriber modules because they do not send voice data to Apple servers. The recorder still needs microphone permission. See [speech recognition permission](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).

## Limits and validation

- The service explicitly rejects simulator execution. Device support is checked through `SpeechTranscriber.isAvailable`; language support is resolved with `supportedLocale(equivalentTo:)`. It does not guess support from an iPhone model name. See [availability](https://developer.apple.com/documentation/speech/speechtranscriber/isavailable).
- It has no `SFSpeechRecognizer` or cloud fallback. Unsupported devices and languages produce actionable errors.
- Empty audio or a recording without recognized speech returns a no-speech error.
- Device-path type checking passed with Swift 6, default main actor isolation, the iOS 26.5 SDK, and an iOS 26.0 deployment target. `swift-format` formatting and strict lint passed.
- Actual recognition, asset download, airplane-mode operation, and interruption behavior still need a supported physical iPhone. Compilation does not establish recognition quality or runtime reliability.

The SDK interface used for signature verification was `Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-ios.swiftinterface` in Xcode's iOS 26.5 SDK.
