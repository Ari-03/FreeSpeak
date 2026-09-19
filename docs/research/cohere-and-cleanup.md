# Cohere Transcribe and S1-mini on iPhone

Checked 2026-09-19 against model publishers and runtime maintainers. The product target is iOS 27 on iPhone 17 and newer. No physical iPhone benchmark was run for this research.

## Decision

Both requested models exist. S1-mini has a small official GGUF build and a credible iOS runtime path through llama.cpp. Cohere has native Swift implementations and downloadable conversions, so it deserves an implementation experiment. Keep Cohere marked experimental until measured on supported iPhones. Laptop throughput does not establish phone latency, memory safety, or background behavior.

Recommended experiment: compare Cohere through FluidAudio Core ML against speech-swift MLX, then run S1-mini after transcription. Load the engines sequentially when memory is constrained. Preserve the raw transcript so cleanup is reversible. These are engineering recommendations, not published performance claims.

## Cohere model and downloads

The original repository is [CohereLabs/cohere-transcribe-03-2026](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026). It is a 2B parameter Conformer encoder plus Transformer decoder, licensed Apache 2.0. It accepts speech, returns text, supports 14 languages, and uses 16 kHz mono preprocessing. It needs a selected language, has no built-in language detection, word timestamps, or speaker diarization, and benefits from voice activity detection to suppress transcription of noise. Cohere recommends Transformers for offline Python inference. These are properties of the model, not proof of iPhone deployment.

The original [file listing](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026/tree/main) shows a 4.13 GB `model.safetensors` file. Access currently requires accepting Hugging Face gating conditions. A model catalog should distinguish the original checkpoint from a phone-compatible conversion and should not imply the original file can simply be loaded by Core ML.

### Native Swift options

| Runtime and model | Verified artifact | What still needs validation |
| --- | --- | --- |
| FluidAudio Core ML | INT8 encoder plus FP16 decoder; approximately 1.8 GB and 291 MB respectively | iPhone latency, peak memory, cold loading, exact model revision |
| speech-swift MLX | INT5 bundle, 1.62 GiB; FP16 and INT8 also available | iPhone and background execution, sustained memory and thermal behavior |

FluidAudio calls its [Cohere integration beta](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/Cohere.md). It exposes `CoherePipeline`, takes 16 kHz mono Float32 audio, and limits a call to 35 seconds. Its documentation gives iOS 18+ for the INT8 variant. Published measurements are on Macs: the M2 LibriSpeech run reached 1.72 times real time overall, with a substantial initial ANE compilation cost. This is a reason to measure cold and warm sessions separately before choosing a default engine.

The conversion publisher hosts [FluidInference/cohere-transcribe-03-2026-coreml](https://huggingface.co/FluidInference/cohere-transcribe-03-2026-coreml). The model card reports a 1.8 GB INT8 encoder, a 291 MB FP16 decoder, and Apache 2.0 licensing. The [actual files](https://huggingface.co/FluidInference/cohere-transcribe-03-2026-coreml/tree/main/q8) sit under `q8/`, with source and compiled packages plus two decoder variants. Do not download the entire 4.99 GB repository when only one deployment variant is needed. The card and runtime docs disagree about the minimum iOS version and use different API names. Resolve this against a pinned runtime commit and compiled model metadata before integration. The legacy `cohere-transcribe-q8-cache-external-coreml` link in runtime docs did not open during this check.

The [speech-swift implementation](https://github.com/soniqo/speech-swift/blob/main/docs/models/cohere-transcribe-asr.md) provides `CohereTranscribeASR`. Its architecture description is explicit: a 48-layer, 1,280-dimensional Conformer and an eight-layer, 1,024-dimensional text decoder. It implements the mel frontend, tokenizer, weight mapping, and FP16/INT5/INT8 loading in Swift.

The maintainer's [Cohere guide](https://soniqo.audio/guides/cohere-transcribe) reports the following on an M5 Pro with 48 GB memory, using 80 English FLEURS recordings. These numbers are a comparison within that experiment, not iPhone promises.

| Precision | Download bundle | Physical footprint | Word error rate | Overall throughput |
| --- | --- | --- | --- | --- |
| FP16 | 3.85 GiB | 6,724 MiB | 6.178% | 23.59 times real time |
| INT5 | 1.62 GiB | 2,582 MiB | 6.288% | 69.64 times real time |
| INT8 | 2.25 GiB | 3,292 MiB | 6.178% | 65.74 times real time |

The guide identifies physical footprint as more useful than RSS for MLX memory-mapped weights. It also explicitly calls this a non-streaming engine. Its Swift implementation handles overlapping chunks for longer recordings.

The exact default conversion is [aufklarer/Cohere-Transcribe-2B-MLX-5bit](https://huggingface.co/aufklarer/Cohere-Transcribe-2B-MLX-5bit). Its card supplies the `CohereTranscribeModel.load` and `transcribe` calls and attributes the Apache 2.0 source model. This is a maintainer conversion, not a checkpoint published by Cohere. Pin its revision and validate transcript quality before shipping it.

## S1-mini cleanup

The original model is [superwhisper/s1-mini](https://huggingface.co/superwhisper/s1-mini), a 596M unique-parameter Qwen3-0.6B fine-tune for normalizing English dictation. It is English only, is not a general instruction-following assistant, and recommends inputs of approximately 1,000 tokens or less. Its valid controls are four styles, two structures, and two destination contexts. A custom mode that needs translation, summarization, or arbitrary instructions needs another cleanup engine. Raw transcription should remain available without cleanup.

Use the official [superwhisper/s1-mini-GGUF file](https://huggingface.co/superwhisper/s1-mini-GGUF/tree/main) `s1-mini-q4_k_m.gguf`. The listing reports 484 MB, approximately 462 MiB. The FP16 GGUF is 1.51 GB. File size is not peak runtime memory; the sources reviewed do not publish an iPhone memory requirement.

The [GGUF integration instructions](https://huggingface.co/superwhisper/s1-mini-GGUF) require the exact documented system prompt and a control line preceding the transcript. Supported style values are `casual`, `semi-casual`, `semi-formal`, and `formal`; structure is `prose` or `lists`; context is `general` or `email`. Use greedy decoding with temperature zero and disable thinking through the chat template. The publisher warns that replacing this with a reasoning-budget setting degrades output. Empty output can be correct for filler-only audio. Keep the controls typed and finite in the app; do not turn a vocabulary list into invented control fields.

The llama.cpp maintainers publish [XCFramework integration instructions](https://github.com/ggml-org/llama.cpp/blob/master/docs/xcframework.md) for iOS and a [SwiftUI example](https://github.com/ggml-org/llama.cpp/blob/master/examples/llama.swiftui/README.md). This establishes a native embedding route. Our app still needs a tested wrapper, cancellation, context limits, memory measurements, and the correct Qwen3 template behavior.

The [S1-mini license](https://huggingface.co/superwhisper/s1-mini/blob/main/LICENSE) contains Apache 2.0 terms plus an added requirement to keep the name `S1-mini` by `Superwhisper` with that capitalization when used or integrated. Preserve license and NOTICE files in distribution, retain model attribution in the catalog, and do not relabel it as our own cleanup model.

## Acceptance work before promising offline support

1. Pin runtime commits and model revisions; record actual selected file sizes and checksums.
2. Measure first load, warm stop-to-text latency, peak physical memory, and thermal state on the lowest supported iPhone and a recent Pro device.
3. Run 5-second, 30-second, and multi-minute dictations, including silence, names, numbers, corrections, and supported non-English languages.
4. Check Cohere quality against the original checkpoint using identical audio and preprocessing. Check S1-mini preserves names and meaning.
5. Measure the ASR-to-cleanup transition with both engines loaded, then with sequential unloading. Choose from data.
6. Test interruptions and the intended background session separately. A model that runs in the foreground is not evidence that the keyboard workflow will work.

These checks define what remains unknown. The research supports building adapters and a download catalog now, while displaying an honest readiness state until the device tests pass.

## Implemented S1 adapter

`FreeSpeak/Services/CleanupModelService.swift` implements a verified model download and real llama.cpp generation. It pins model revision `34add00a48a2e5d24e5a4ee5405a99620a3a240c`, checks 484,219,808 bytes and the publisher's SHA-256, then installs the weights outside the app bundle. The app includes the model's LICENSE and NOTICE.

`Packages/FreeSpeakLlama` pins the official b9000 XCFramework and its SHA-256. Its artifact includes iOS device and simulator slices. The adapter encodes user text separately from ChatML control tokens, uses the required empty thinking block, samples greedily, rejects transcripts above 1,000 tokens, checks cancellation between decode batches, and releases model memory after each cleanup. Desktop and iOS 26 SDK type-checks pass; the available SDK can verify compilation but cannot establish iOS 27 device behavior.

A desktop smoke run downloaded and verified the real checkpoint, then produced these results through the app's actual service:

| Input | Output |
| --- | --- |
| so um send the report by uh friday no wait make that thursday | So send the report by Thursday. |
| my name is aritra and i am building freespeak | My name is Aritra, and I am building Freespeak. |
| um uh | Empty string |

The second result shows why vocabulary handling remains necessary: the model does not know the desired `FreeSpeak` casing. These are smoke checks, not an accuracy benchmark. No phone latency claim follows from this run.
