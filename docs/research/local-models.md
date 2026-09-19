# Local Parakeet and Whisper on iPhone

Research date: September 19, 2026. Product target: iOS 27, iPhone 17 and newer. This note distinguishes published integration support from performance that still needs a physical-device test.

## Recommendation

Use FluidAudio with Parakeet TDT 0.6B v3 as the first downloadable speech engine. Use WhisperKit with compressed Large v3 Turbo as the second engine for broader language coverage. Keep full Whisper Large v3 as an explicit advanced download after measuring it on the supported iPhones. These are engineering recommendations based on the available Swift runtimes and artifacts, not a claim that either model wins every accuracy benchmark.

For English-only dictation, evaluate Parakeet v2 alongside v3. FluidAudio recommends v2 for English recall; v3 covers 25 European languages. The multilingual v3 model does not include Bengali, Hindi, Chinese or Japanese. NVIDIA publishes the complete language list and licenses its weights under CC BY 4.0. FluidAudio's Japanese Parakeet is a separate model. [FluidAudio getting started](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md), [NVIDIA v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).

## Concrete runtime choices

| Choice | Native integration | Verified constraints |
| --- | --- | --- |
| Parakeet TDT v3 | `FluidAudio` Swift package, Core ML | Package supports iOS 17+, Swift tools 6.0; v3 is 600M parameters and needs mono 16 kHz audio. |
| Whisper Large v3 Turbo compressed | `WhisperKit` product from `argmaxinc/argmax-oss-swift` | Package declares iOS 16+, Swift tools 5.10; upstream recommends `large-v3-v20240930_626MB` across iOS and macOS. |
| Full Whisper Large v3 | Same WhisperKit product, separate model folder | Download exists, but its uncompressed folder is 3.09 GB. Device suitability must be measured. |

Sources: [FluidAudio package manifest](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Package.swift), [Argmax package manifest](https://github.com/argmaxinc/argmax-oss-swift/blob/main/Package.swift), [Argmax model recommendations](https://github.com/argmaxinc/argmax-oss-swift#model-selection), [full Large v3 files](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3).

The old `argmaxinc/WhisperKit` repository URL redirects to `argmaxinc/argmax-oss-swift`. Import only the `WhisperKit` library product; the umbrella also includes unrelated speech synthesis and speaker tools. The open source SDK uses MIT. Argmax Pro is a separate commercial SDK with separate optimized artifacts, so its benchmark numbers should not become promises for the open source implementation. [Argmax repository](https://github.com/argmaxinc/argmax-oss-swift), [Argmax model management](https://app.argmaxinc.com/docs/guides/managing-models).

## Download sizes and model identity

The Parakeet repository contains several alternative encoders and old conversion artifacts. Its total repository size of 3.59 GB is not the download required for one runnable variant. The SDK selects a preprocessor, one encoder, decoder, joint model and vocabulary. [Parakeet files](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/main), [SDK file selection](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ModelNames.swift).

The following totals were calculated from the publisher's file metadata, summing required component files rather than the whole repository. They exclude Core ML compilation caches, transient downloads and application data.

| Parakeet v3 variant | Selected files, plus vocabulary | Calculated bytes | Approximate decimal size |
| --- | --- | --- | --- |
| Default `.int8` | `Encoder`, `Preprocessor`, `Decoder`, `JointDecisionv3` | 483,105,645 | 483 MB |
| Corrected `.int8V2` | `Encoder_v2`, `Preprocessor`, `Decoder`, `JointDecisionv3` | 632,169,729 | 632 MB |
| `.int4` | `EncoderInt4`, `Preprocessor`, `Decoder`, `JointDecisionv3` | 335,745,501 | 336 MB |

Source data: [Hugging Face recursive file metadata](https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/main?recursive=true). SDK release 0.15.7 exposes all three variants. Its source says `.int8V2` corrects context-dependent token corruption in the original encoder. FreeSpeak therefore selects `.int8V2` even though `.int8` remains the upstream default. This is a correctness choice, not a measured iPhone speed claim. [Encoder selection and correction](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ModelNames.swift#L318).

The Whisper folder named `openai_whisper-large-v3-v20240930_626MB` is compressed **Large v3 Turbo**, not full Large v3. The current file listing rounds its folder size to 627 MB. Label both models accurately in the app. The publisher marks its Core ML weights MIT. [Compressed Turbo files](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB), [Argmax model selection table](https://github.com/argmaxinc/argmax-oss-swift#model-selection).

## Integration details that affect the app

FluidAudio 0.15.7 has actual Swift APIs for model download, validation, deletion by directory, and transcription. `AsrModels.downloadAndLoad` accepts a destination, model version, encoder precision and progress handler. The source defaults to CPU plus Neural Engine. It avoids GPU dispatch for the Parakeet path. This does not itself grant iOS background execution; the app still needs an appropriate active audio session and lifecycle design. [Model loading implementation](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift).

Use the source API at the pinned release, because the getting-started guide contains stale `configure` and `source:` examples. At 0.15.7, `AsrManager` is an actor. Initialize it with `AsrManager(models:)` or call `loadModels`, create `TdtDecoderState`, then call `transcribe(url, decoderState: &state)`. Its file URL path performs audio conversion internally and can use disk-backed audio for long recordings. [Pinned manager source](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrManager.swift), [decoder state](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/Decoder/TdtDecoderState.swift).

For WhisperKit, initialization can select an exact model name and transcription accepts a local audio path. Its current implementation also exposes incremental file loading to bound audio-buffer memory. That reduces audio loading cost, not the weight memory of the model. [WhisperKit examples](https://github.com/argmaxinc/argmax-oss-swift#whisperkit).

TDT v3 is a batch model. FluidAudio can stitch overlapping windows for near-real-time text, but that differs from a cache-aware streaming model. Parakeet EOU 120M is a separate English streaming option. Newer Parakeet Unified supports English batch and streaming, but FluidAudio documents an INT8 loading failure on A16 and says other A-series chips are unverified. Its advice is FP16 on iOS. For FreeSpeak, keep Unified as a later physical-device experiment rather than assuming the newest architecture is the best default. [FluidAudio model catalog](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md).

## Memory, startup and validation

Neither model file size nor a Mac process RSS measurement is an iPhone peak-memory guarantee. We did not find a controlled, current iPhone 17 measurement covering this exact pinned FluidAudio version, corrected v3 encoder and subsequent cleanup model. Measure physical footprint, latency and thermal behavior on device before presenting a memory requirement or speed promise.

There is concrete evidence of startup cost. FluidAudio publishes v3 encoder cold-load compilation around 3.36 seconds on iPhone 16 Pro Max and 4.40 seconds on iPhone 13. Those are publisher measurements on earlier hardware, not FreeSpeak results. Prepare the model during installation, distinguish downloading from preparing, and preserve a readiness marker only after successful loading. [FluidAudio compilation benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md#asr-model-compilation).

Recommended acceptance checks for the iPhone 17 target:

- Download, cancel, retry, kill the app mid-download, restart and delete the model. Never declare a partial directory ready.
- Transcribe in airplane mode after installation, including silence, accents, names, numbers and clips longer than one model window.
- Measure peak physical footprint while speech and cleanup models load sequentially; unload the speech model before cleanup where necessary.
- Measure cold start, warm start, time from stopping recording to final text, and a 30-minute dictation session under thermal pressure.
- Compare the same personal vocabulary corpus across Apple SpeechAnalyzer, Parakeet v2/v3, Whisper Turbo and full Large v3 before choosing defaults by language.

These are proposed validation steps, not completed benchmarks. FreeSpeak's initial integration pins [FluidAudio release 0.15.7](https://github.com/FluidInference/FluidAudio/releases/tag/v0.15.7). Preserve NVIDIA model attribution separately from FluidAudio's Apache 2.0 code attribution. [FluidAudio license](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/LICENSE), [NVIDIA model license declaration](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).
