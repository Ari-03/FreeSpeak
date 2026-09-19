# Steno

A native iPhone dictation app with local speech models, your own cloud API keys, optional text cleanup, and a keyboard for inserting completed transcripts.

This is an initial implementation. The model adapters and keyboard target are in the repository; physical iPhone performance and the intended background dictation experience still need validation. Start device testing on iPhone 17 or newer.

## Build and run

1. Open `FreeSpeak.xcodeproj` in Xcode and select the `FreeSpeak` scheme.
2. Let Swift Package Manager resolve FluidAudio 0.15.7, WhisperKit 1.1.0, and the pinned llama.cpp XCFramework. The first build downloads dependencies, not speech model weights.
3. Configure signing for both `FreeSpeak` and `FreeSpeakKeyboard`, as described below.
4. Select a physical iPhone and run. Allow microphone access when recording. In Models, download the local models you want, or add a cloud key in Settings.

The project deployment target is **iOS 27.0**. The development machine currently has the iOS 26.5 SDK. To compile against that installed SDK without changing the committed target, use a build-time override:

```sh
xcodebuild -project FreeSpeak.xcodeproj -scheme FreeSpeak \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -packageAuthorizationProvider netrc \
  IPHONEOS_DEPLOYMENT_TARGET=26.5 CODE_SIGNING_ALLOWED=NO build
```

This command is a compilation check, not a signed device install or evidence of iOS 27 runtime behavior. Apple Speech requires a supported physical device and reports that limitation in Simulator. For a device running iOS 26.5, apply the same deployment override to a signed device build; otherwise use a matching iOS 27 SDK and device.

### Signing and the keyboard

Steno is the working product name. Xcode target names and storage identifiers retain FreeSpeak to preserve existing installations and saved data. The app uses bundle IDs `ari.FreeSpeak` and `ari.FreeSpeak.Keyboard`, with shared App Group `group.ari.FreeSpeak`.

- Choose your development team for both targets. Enable App Groups for both and register the same group with that team.
- If those identifiers are unavailable, change both bundle IDs, the group in both entitlement files, and `KeyboardInbox.appGroup` in `Shared/KeyboardInbox.swift` together. The extension bundle ID must retain the app bundle ID as its prefix.
- Install and open Steno. In iPhone Settings, go to General → Keyboard → Keyboards → Add New Keyboard and select Steno.

Record in the main app, return to a text field, switch to Steno with the globe key, and tap **Insert**. The keyboard provides basic letters, numbers, symbols, deletion, and keyboard switching. It reads the most recent shared transcript and keeps insertion receipts in its own container. It requests no Full Access and contains no model runtime or API key.

The **Start dictation** App Shortcut opens Steno and starts recording once its scene is active. Add it in Shortcuts or assign it to the Action Button. It does not start a background microphone session.

This baseline requires a manual app switch. The keyboard does not record, activate the host app, or provide a persistent background dictation session. Insertion is user initiated; it does not send a message. A receipt prevents normal duplicate insertion, but iOS provides no transaction across the receipt and destination field. Copy and Share in the main app remain recovery paths. Secure fields and apps that disable custom keyboards need those alternatives. See the [platform research](docs/research/ios-keyboard.md).

## Implemented scope

The app records audio, imports files up to 25 MB, transcribes with the selected provider, and optionally cleans the result. Natural, Message, Notes, and Verbatim modes can be edited; custom modes can be added. Settings include language, vocabulary hints, provider keys, cleanup model IDs, and local transcript history. Results retain the original transcription when cleanup fails.

| Engine | Stage and runtime | Current limits |
| --- | --- | --- |
| Apple Speech Analyzer | Local transcription through Apple's Speech framework | Supported device and language required; Apple manages language assets. Unavailable in Simulator. |
| NVIDIA Parakeet TDT v3 | Local transcription through FluidAudio, corrected INT8 v2 encoder | Approximately 632 MB download; validate phone accuracy and memory. |
| Whisper Large v3 | Local transcription through WhisperKit | Full model, approximately 3.1 GB. Incremental audio loading; first load can take minutes. |
| Cohere Transcribe | Local transcription through FluidAudio Core ML | Experimental on iPhone, approximately 2.2 GB; explicit language from its 14 supported languages; up to five minutes through overlapping windows. |
| OpenAI | Cloud transcription, `gpt-4o-transcribe` | User API key and network required; 25 MB app upload limit. |
| Grok from xAI | Cloud transcription, `grok-voice-transcribe-2.0` | User API key and network required; distinct from Groq; 25 MB app upload limit. |
| S1-mini by Superwhisper | Local cleanup through llama.cpp | Approximately 484 MB; English only; at most 1,000 transcript tokens; fixed style, structure, and context controls. Arbitrary mode instructions are for cloud cleanup. |
| OpenAI or Grok | Cloud cleanup | Uses the selected text model and mode instructions; defaults are `gpt-4.1-mini` and `grok-4.3`. Availability depends on the user's account. |

Recording currently stops at five minutes. Microphone startup and shutdown run away from the UI thread and report a timeout after eight seconds if the audio driver stalls. Selecting Verbatim or leaving a mode's instructions empty skips cleanup. Vocabulary feeds supported cloud transcription and cleanup requests; local recognition vocabulary and deterministic replacement rules are not implemented.

Download size is not runtime memory usage. Local adapters require device measurements before any speed or compatibility promise. Model sources, licensing, and runtime details are in [local models](docs/research/local-models.md), [Whisper integration](docs/research/whisper-integration.md), [Cohere integration](docs/research/cohere-integration.md), and [Cohere and S1-mini](docs/research/cohere-and-cleanup.md).

## Keys and data

Add your OpenAI or xAI key in Settings. No API keys are embedded in the app or required to build it. Keys live in this device's Keychain; requests go directly to the chosen provider and usage is billed to that account.

Cloud transcription sends audio and vocabulary terms. Cloud cleanup sends transcript text, mode instructions, and vocabulary. Local transcription followed by cloud cleanup therefore sends text off-device. Select local engines for both stages, or turn cleanup off, to keep inference on the phone after model downloads.

History is stored locally. Turning history off affects future entries; it does not delete existing ones. The latest completed result is also shared with the keyboard. Delete all transcripts clears history, the current result, and the shared keyboard result. Temporary audio is removed after successful processing. A failed recording remains available for retry during the app session; durable recording recovery and retention controls remain on the [roadmap](docs/roadmap.md).

## Checks and device validation

Validated on this development machine with Xcode 26.6 and the iOS 26.5 SDK, using a deployment override while keeping the project target at iOS 27:

- Device and arm64 Simulator builds pass, including the embedded keyboard.
- The app launches on the iPhone 17 Pro Simulator; dictation, model, and settings screens were inspected, and custom mode creation was exercised.
- Twelve cloud contract tests and the recording lifecycle/persistence harness pass. No paid API requests were made.
- S1-mini's verified weights completed real desktop inference with the pinned llama.cpp runtime. This does not establish its iPhone latency.
- Strict Swift formatting lint and project plist validation pass.

Run the isolated cloud contract tests without keys or network calls:

```sh
bash Tests/run-cloud-tests.sh
bash Tests/run-app-store-tests.sh
bash Tests/run-audio-tests.sh
```

See [Tests/README.md](Tests/README.md) for coverage. For Swift formatting and linting:

```sh
xcrun swift-format lint --strict --recursive FreeSpeak FreeSpeakKeyboard Shared
```

Before treating a device build as ready for daily use, check:

- Record, import, cancel, retry, copy, share, delete history, and insert through the signed keyboard.
- Download, cancel, resume, delete, and run each local model in airplane mode after setup.
- Measure cold and warm latency, peak memory, battery, and thermal state on iPhone 17 and a Pro model.
- Exercise silence, names, numbers, supported languages, Cohere's duration limit, and S1-mini's token limit.
- Try permission denial, phone calls, Siri, Bluetooth changes, lock/unlock, low storage, and extension recreation.
- Check Dynamic Type, VoiceOver, Reduce Motion, landscape, and the keyboard without Full Access.

Build success and request contract tests do not establish microphone, Core ML, or keyboard behavior on a physical phone. The prioritized next work is in [docs/roadmap.md](docs/roadmap.md).
