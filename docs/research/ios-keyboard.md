# iPhone dictation and keyboard feasibility

Researched 2026-09-19 against Apple documentation and an Apple DTS response. Recommendations below are engineering proposals, not claims that the workflow has passed App Review or device testing.

## What we can promise

Build recording and inference in the main app, with a small keyboard extension that inserts completed text. An explicitly started recording can continue while the user works in another app. A completely cold microphone start from an arbitrary keyboard is not a supported baseline. The closest practical experience is a visible, time-limited dictation session started in the main app, followed by keyboard interactions during that session. Repeated segmentation and session survival require an early device prototype.

## Verified platform constraints

| Area | Finding | Design consequence |
| --- | --- | --- |
| Keyboard microphone | Custom keyboards cannot access the microphone. Full Access expands networking and shared-container access, not microphone privileges. | Capture audio in the main app. [Apple keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [current open-access documentation](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) |
| Full Access | Without Full Access, current documentation allows reading the containing app's shared containers but disallows writing and networking. Full Access requires an explicit Settings choice. | Distinguish reading an already prepared transcript from writing dictation commands. Do not tell users that Full Access enables the microphone. [Apple open-access documentation](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) |
| Background recording | An existing recording can continue after the app backgrounds when `UIBackgroundModes` includes `audio`. Microphone permission is required. Calls, alarms, and nonmixable sessions can interrupt recording. | Add recording lifecycle and interruption recovery. Prefer `playAndRecord` over `record` unless silencing other output is intentional. [Apple audio recording category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record) |
| Cold microphone activation | Apple DTS states that the general audio API prevents activating recording sessions in the background. CallKit, LiveCommunicationKit, and PushToTalk exceptions are for actual communication apps. | A dormant app must regain a supported foreground execution context before starting microphone capture. Do not misuse call APIs. This staff answer addresses a BLE-triggered intent, so test system-triggered intents independently. [Apple DTS, February 2026](https://developer.apple.com/forums/thread/816408) |
| Text insertion | The keyboard inserts or deletes through `textDocumentProxy`. Secure fields and phone-pad fields use the system keyboard. Apps can reject third-party keyboards entirely. | Keep an in-app copy/share fallback and avoid promising operation in every field. [Apple keyboard guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) |
| Memory | Keyboard extensions run in separate processes with device-dependent memory limits and can be terminated if they exceed those limits. | Keep model loading, inference, and audio buffers out of the keyboard. Do not encode a universal memory allowance. [Apple custom keyboard documentation](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard) |

The archived keyboard guide disagrees with current documentation about read-only shared-container access without Full Access. Use the current documentation for this detail and verify the behavior on the minimum supported OS.

## App Groups and delivery

Apple supports sharing data between a containing app and its extensions using App Groups. Shared `UserDefaults` suit preferences; a shared-container URL provides file storage. Shared access needs coordination. [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [extension data-sharing guidance](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)

Proposed implementation:

- The main app owns audio, model runtimes, network requests, and API credentials.
- App Group storage contains selected mode, session status, command IDs, and completed transcript records. Keep API keys in Keychain, outside this message channel.
- Use atomic files or a coordinated database for session commands and results. Treat notifications as hints to reread persisted state, not as guaranteed delivery or process wake-up mechanisms.
- Every utterance and command gets an ID. A result is inserted once, only when the user requests insertion into the current field. Preserve the result for retry if the extension disappears.
- The keyboard displays disconnected, recording, transcribing, ready, and interrupted states. A stale heartbeat means disconnected, not silently successful.

These are design recommendations. An App Group shares data; it does not itself grant a suspended app execution time.

## Live Activities, shortcuts, and switching apps

`AudioRecordingIntent` represents recording actions. Apple requires a Live Activity throughout audio recording initiated under this protocol; otherwise recording stops. This requirement does not document an exemption from microphone activation restrictions. [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent)

Live Activities support App Intent buttons and toggles. They can show recording duration and a Stop action without opening the app. `LiveActivityIntent` can start a Live Activity while the app is in the background. Starting that UI and gaining microphone access are separate operations. Handle disabled Live Activities and start failures. [Displaying Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

App Intents support foreground and background execution modes. Use a foreground start intent for a reliable first implementation and expose it through Shortcuts or a supported system control. Check deployment availability against the installed SDK; current docs deprecate `openAppWhenRun` in favor of `supportedModes`. [Intent modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes), [openAppWhenRun](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun)

No supported universal "return to whichever app invoked this keyboard" mechanism was established in this research. `NSExtensionContext.open` documents support for Today and iMessage extension points, not keyboard extensions. Do not infer keyboard support from the presence of the method or from generic SwiftUI `Link` behavior. [Opening a URL from an extension](https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:))

## App Review requirements that affect implementation

Apple's current rules require keyboard input, a next-keyboard control, and functionality without Full Access. Rule 4.4.1 also prohibits launching other apps besides Settings. Whether a containing-app activation path receives different treatment needs explicit validation; competitors' behavior is not documentation. Include basic typing even if dictation requires an active host session.

Rules 2.5.1, 2.5.4, and 2.5.14 require public APIs, background modes used for their intended purpose, and clear consent and recording indication. A continuously listening session must be honest about microphone use and offer an obvious stop action. Playing silent audio just to avoid suspension is not a sound architecture. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## First device experiment

Before investing in more model integrations, build a main-app recorder, one keyboard target, shared session state, and a Live Activity. Test:

1. Start recording in the app, switch to Notes, insert one completed transcript.
2. Segment several utterances while keeping the original audio session active. Measure idle battery use and clearly show that the microphone remains active.
3. Stop the session completely. Confirm that another keyboard request reports that activation is needed.
4. Exercise phone calls, Siri, Bluetooth route changes, lock/unlock, force quit, memory pressure, and disabled Full Access.
5. Try foreground and background App Intent entry paths separately. Record OS version and actual behavior; do not generalize from Simulator success.
6. Verify that retrying a command or recreating the keyboard never inserts duplicate text or loses the final transcript.

The conservative product baseline is one activation per visible session, with several dictations afterward. Session duration, background reactivation, keyboard-to-app launch, and fully automatic insertion remain prototype questions.

## Follow-up: Spokenly's background shortcut

Spokenly documents a system-triggered shortcut that starts recording without opening its app, finishes through its keyboard or a second shortcut invocation, and requires Live Activities. It lists iOS 17+ and Spokenly 1.6.4+ as requirements. This is first-party evidence of a shipping product's claimed behavior, but it does not disclose the implementation or establish behavior after force quit. [Spokenly background dictation](https://spokenly.app/docs/ios/background-dictation)

This narrows the earlier conclusion. Apple's DTS answer addresses a Bluetooth callback and general audio APIs, whereas Spokenly describes a person explicitly running a system Shortcut. These execution contexts may differ. Apple's `AudioRecordingIntent` documentation describes recording actions with a mandatory Live Activity, but does not explain every activation condition. It would be incorrect to conclude that all shortcut-based background recording is impossible, or that a keyboard can acquire microphone access directly.

Keep system-triggered background dictation as a separate, worthwhile prototype. Test an `AudioRecordingIntent` with a Live Activity through Shortcuts on a real iPhone, including cold launch, force quit, lock state, and permission denial. The first implementation's app-to-keyboard transcript handoff does not depend on this unresolved behavior.
