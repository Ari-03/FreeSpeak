# FreeSpeak product experience

Research checked September 19, 2026. Competitor behavior below comes from current first-party documentation. The FreeSpeak screen plan is a proposal, not a claim that its features are implemented.

## What the competitors establish

| Product | Verified iPhone behavior | Lesson for FreeSpeak |
| --- | --- | --- |
| Superwhisper | Its iOS guide describes a custom keyboard, Full Access setup, dictation insertion at the cursor, and device-specific modes and vocabulary. On iOS 26.4 and later, opening the main app from its keyboard does not automatically return to the previous app. | Explain the return step honestly. Keep frequent settings inside the keyboard. |
| Superwhisper | The current App Store description lists mode switching from the keyboard, searchable recording history, BYOK, custom presets, and a shortcut for dictating on demand. Older feedback requests for keyboard mode switching are therefore poor evidence of current limitations. | Visible mode selection and recoverable history are baseline features. |
| Spokenly | Its background shortcut starts recording without opening the app. With its keyboard selected, finishing in the keyboard inserts at the cursor. Running the shortcut twice instead copies the result for manual pasting. Its guide requires iOS 17+, app version 1.6.4+, and Live Activities. | Research a deliberate shortcut path alongside the normal keyboard path. Distinguish insert from copy. |
| Spokenly | A mode saves transcription model, optional AI instructions, AI provider, and output behavior. Its docs explicitly list an iOS mode picker; automatic app and website activation is labeled macOS. | Save the entire pipeline in a mode. Do not assume desktop context or app detection works on iPhone. |
| Wispr Flow | Its iOS guide describes transcript recovery, styles, dictionary, notes, keyboard controls, Live Activity status, Control Center, and shortcuts. | Put recovery and current recording status ahead of usage statistics. |

Sources: [Superwhisper iOS guide](https://superwhisper.com/docs/get-started/ios), [Superwhisper App Store listing](https://apps.apple.com/us/app/superwhisper-ai-dictation/id6471464415), [Spokenly background dictation](https://spokenly.app/docs/ios/background-dictation), [Spokenly modes](https://spokenly.app/docs/modes), [Wispr Flow navigation](https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android).

Superwhisper documents the same two-stage idea the user wants: transcribe audio with a voice model, then optionally process the text with a language model. Its Voice to Text mode omits the second stage. Some settings in that general guide concern desktop use, so it does not establish that every feature exists on iPhone. [Superwhisper modes](https://superwhisper.com/docs/modes/modes)

Vocabulary needs two distinct concepts. Recognition hints help a supported transcription model hear uncommon terms; replacements apply a spelling rule after transcription. Spokenly documents different hint support by provider and separate word-boundary-aware replacements. Wispr Flow also distinguishes vocabulary words from explicit corrections. FreeSpeak should show which behavior the selected model supports. [Spokenly dictionary](https://spokenly.app/docs/custom-dictionary), [Spokenly replacements](https://spokenly.app/docs/word-replacements), [Wispr Flow dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)

Wispr Flow's navigation guide says its iOS dictionary has search, while its more recently updated dictionary guide says iOS has no dictionary search. This conflict remains unresolved. FreeSpeak should offer search because a growing vocabulary needs it, independent of competitor parity.

## Product direction

FreeSpeak should make it easy to say a thought, preserve its meaning, and put readable text where the user needs it. It should feel useful before the user configures five models. The default experience needs one working transcription route, light cleanup, a visible record button, and a clear way to retrieve the result.

Use a native SwiftUI interface with system typography, restrained color, comfortable touch targets, and useful empty states. Recording color and motion should communicate microphone activity, not decorate an idle screen. Support Dynamic Type, VoiceOver, Reduce Motion, high contrast, and a seated one-handed layout from the first build.

## Screens and interactions

| Screen | Content and behavior |
| --- | --- |
| Dictate | Current mode chip, speech and cleanup model summary, large record control, live duration, status text, and recent transcripts. An empty state invites a first recording without fabricated history or usage counts. |
| Recording | A real input-level visualization, timer, Cancel, and Stop. Keep the selected mode visible. Lock pipeline configuration for this recording so changing defaults cannot alter an in-flight result. |
| Result | Editable final text, Copy and Share, and a Raw / Cleaned comparison. Display a cleanup failure with a usable raw transcript. A transcript remains recoverable if insertion fails. |
| Modes | Presets with a one-line behavior description. Tap to activate; edit from a separate control. The editor contains name, speech model, cleanup model or None, input language, output language if enabled, and custom instructions. |
| Models | Separate Speech and Cleanup sections. Each model shows Local or Cloud, real compatibility, download state, actual storage requirement when known, and supported languages. Installed models have Remove; downloadable models have progress and Cancel. Experimental integrations are visibly disabled until they work. |
| Vocabulary | Searchable terms with optional misheard spellings. Add from an edited result or enter manually. Explain whether a term is a recognition hint, replacement, or both. Avoid broad replacements such as mapping every occurrence of "cloud" to "Claude". |
| Settings | Provider keys, keyboard setup, shortcuts, language, retention, microphone permissions, and diagnostics. Securely stored keys show only a masked suffix, with Test connection and Remove. |
| Keyboard | Mode chip, clear session state, recording control, Stop / Insert, globe key, and enough editing controls to recover. Open a compact mode picker without leaving the current app. Explain when the main app must be opened. |

Four main tabs are enough: Dictate, Modes, Models, Settings. Link vocabulary and full history from Dictate and Settings. This keeps the app's frequent actions visible without a crowded tab bar.

## Initial modes

| Mode | Intended transformation |
| --- | --- |
| Clean | Remove fillers and false starts, add punctuation, preserve facts, tone, and language. |
| Verbatim | Return the transcription without an AI rewrite. |
| Message | Short conversational paragraphs, preserving the user's wording. |
| Email | Format the dictated content as an email. Do not invent recipients, commitments, or a signature. |
| Notes | Organize the spoken content into readable paragraphs or bullets without inventing tasks. |

Custom instructions belong in an expandable editor. Offer a test recording there so users can see the effect before using a mode in another app. Keep language preservation explicit: mixed-language speech must not silently become English.

The user's request names Grok. Keep xAI Grok distinct from Groq, which is a different provider. A provider/model choice must say whether it handles audio transcription, text cleanup, or both. Do not infer interchangeable APIs from similar names.

## Cross-app flow

Implement and validate two explicit paths. The normal path begins in the FreeSpeak keyboard and uses the host app for audio capture when necessary. The shortcut path starts a supported recording session from the Action Button, Shortcuts, or a system control; the keyboard can receive the result when it is active. Until proven on physical devices and the target iOS version, describe background start as under development.

A Live Activity should show whether FreeSpeak is ready, recording, or finishing, and offer a stop control where supported. Readiness and recording are different states. A session timeout must be visible, and ending readiness must release the microphone. Never describe a readiness timer as recorded audio duration.

If the destination field disappears, preserve the completed transcript and show Insert or Copy when the user returns. Each result needs an identifier and acknowledged delivery so a reconnect cannot insert the same text twice. Do not auto-send messages or simulate an Enter key.

This is a product proposal based on competitor workflows, not proof of an Apple API implementation. The separate iOS platform investigation must establish the supported mechanism, permissions, extension boundaries, and review constraints.

## First release and later work

The first working release should include host-app recording, one verified local speech route, OpenAI transcription with the user's key, optional cleanup, modes, vocabulary, local transcript recovery, and keyboard insertion. Each supported model must run end to end on a physical iPhone before it gets an enabled selection control.

Keep model integration behind a common interface, but add local runtimes one at a time after measuring cold load, latency, memory, thermal behavior, and transcription quality. The list requested by the user is the intended catalog. Model weights existing online do not establish that the model fits or runs acceptably on an iPhone. Cleanup failure must never erase successful transcription.

After the basic path is reliable, add tested background shortcuts, Live Activities, downloadable model management, more runtimes, and reprocessing a saved recording with another model. Defer full keyboard prediction, swipe typing, automatic app-specific modes, account sync, meeting capture, and usage streaks until they solve a demonstrated need.

Keep downloads and cloud processing explicit. A local speech model followed by cloud cleanup sends text off-device; the UI should show that route before recording. Local-only mode should reject every cloud stage instead of silently falling back. Preserve audio only under a clear retention setting, and provide delete-all controls for transcripts and retained recordings.

## Acceptance checks

- A first-time user records and copies one real transcript without adding a keyboard or choosing among unsupported models.
- A cloud request failure leaves the recording recoverable when retention permits it; cleanup failure leaves the raw transcript usable.
- The selected mode is visible before recording in both app and keyboard.
- Cancel never inserts text, and reconnecting a keyboard never inserts twice.
- Bluetooth disconnection, interruptions, permission denial, session expiry, no speech, and low storage have specific recovery messages.
- Larger text, VoiceOver, and Reduce Motion preserve access to every recording control.
- Measurements distinguish recording time, transcription time, cleanup time, and delivery time. Performance claims use device results rather than model marketing.
