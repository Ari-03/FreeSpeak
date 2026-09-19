# Cohere integration in FreeSpeak

Checked September 19, 2026 against FluidAudio tag `v0.15.7`, commit `41540ea237350afe5117a082b5c28eda642d0612`. The adapter is experimental on iPhone. No large model download or physical-device inference was performed during implementation.

## Pinned APIs

This dependency version contains `CoherePipeline`, `CohereAsrConfig`, `Repo.cohereTranscribeCoreml`, and the required download manifest. It needs no dependency upgrade. `CoherePipeline.loadModels` accepts encoder, decoder, and vocabulary directories; `transcribe` takes 16 kHz mono Float32 samples and an explicit language. The default v2 decoder has a fixed attention mask. [Pinned pipeline source](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ASR/Cohere/CoherePipeline.swift)

`CohereModelService` downloads through `ModelHub.download(.cohereTranscribeCoreml, to:)`. The repository mapping selects `FluidInference/cohere-transcribe-03-2026-coreml/q8`, and the local folder is `cohere-transcribe/q8`. Required artifacts are the compiled encoder, compiled v2 decoder, and `vocab.json`. The downloader separately finds required auxiliary files at the repository root. This avoids the outdated model repository links in the prose guide. [Pinned model names](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ModelNames.swift), [pinned downloader](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/Shared/Download/ModelHub.swift)

The current model tree lists 1,881,964,672 bytes for encoder weights and 304,453,120 bytes for decoder weights. Small metadata and vocabulary files add to that, so the UI says approximately 2.2 GB. These are download sizes, not peak RAM requirements. The adapter uses only one compiled decoder, not all source and compiled variants. [Publisher artifact tree](https://huggingface.co/FluidInference/cohere-transcribe-03-2026-coreml/tree/main/q8)

## Runtime behavior

- Downloads have cancellation and expose preparation errors. A readiness marker is written only after Core ML loads both models and the vocabulary. Partial files do not make the model ready.
- The model directory is excluded from device backups. Delete removes only FreeSpeak's Cohere model directory.
- Inference loads downloaded files directly, without calling the downloader. Audio stays on the device for this stage.
- The service maps the locale's language code to Cohere's 14 supported languages and rejects unsupported choices explicitly.
- Input longer than five minutes is rejected before audio decoding, with a second sample-count check during decoding. Accepted recordings use `transcribeLong`, so audio beyond the first 35 seconds is processed.
- `AVAssetReader` decodes directly to 16 kHz mono Float32 buffers outside the main actor. It avoids retaining a separate full recording at the original sample rate. Storage for five minutes of samples is 19.2 MB, excluding allocator overhead and the model runtime. The sample cap allows 1,600 additional frames for decoder/resampler padding; the duration check still rejects files over five minutes.
- The pipeline is an actor. Cancellation discards the result when inference returns. The pinned long-form loop does not explicitly check cancellation between chunks, so stopping Core ML work immediately is not guaranteed.
- `unload()` releases stored models and the pipeline when idle so the app can load another local engine.

`transcribeLong` processes one 35-second window at a time with a 30-second hop. It copies at most 2.24 MB of Float32 samples for each window and reuses the loaded models. Token matching joins overlapping text; absent a sufficient match, it concatenates to avoid dropping an unmatched segment. This removes the artificial 35-second app limit. Chunk merging still needs accuracy checks on real speech, especially repeated phrases near boundaries. [Pinned pipeline source](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Sources/FluidAudio/ASR/Cohere/CoherePipeline.swift)

The upstream test suite covers overlap and hop configuration, empty token streams, successful overlap matches, the bounded match window, and concatenation when matches are absent or too short. Those tests establish merge behavior, not phone memory or end-to-end recognition quality. [Pinned long-form tests](https://github.com/FluidInference/FluidAudio/blob/v0.15.7/Tests/FluidAudioTests/ASR/Cohere/CohereLongFormTests.swift)

## Remaining validation

The service type-checks for an iOS device against the compiled FluidAudio dependency. A macOS smoke harness using the service's extracted conversion method accepted 36-second and exactly 300-second stereo 48 kHz WAV files, converted them to mono 16 kHz, and rejected 301 seconds before decoding. Exactly 300 seconds produced a few padding samples beyond 4.8 million, which motivated the bounded padding allowance. This checks audio conversion, not Cohere inference or physical iPhone behavior.

The runtime tag is pinned, but FluidAudio's public download API uses the model repository's current branch. It exposes no revision parameter in this version. Production distribution should pin the artifact revision and checksums before claiming reproducible model downloads.

Successful loading establishes that Core ML accepts the models; it does not establish acceptable phone latency, thermal behavior, or memory use. Validate on the lowest supported physical iPhone with short clips, 35-second and five-minute clips, repeated phrases across chunk boundaries, silence, interruption, cancellation, and every advertised language. Measure download, first compilation, warm inference, and transition to local cleanup separately. Do not copy Mac throughput numbers into the iPhone model picker.
