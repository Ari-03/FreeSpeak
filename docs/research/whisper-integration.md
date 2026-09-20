# Whisper Large v3 integration

Checked September 19, 2026.

FreeSpeak uses the `WhisperKit` product from Argmax's official `argmax-oss-swift` package, pinned to release `1.1.0`, commit `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`. The repository previously used the name WhisperKit. See the [release](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.1.0) and [package manifest](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Package.swift).

## Model choice

The download selects the exact `openai_whisper-large-v3` folder from `argmaxinc/whisperkit-coreml`. The published files total 3,090,319,899 bytes, about 3.09 GB before tokenizer files and Core ML caches. This is the full Large v3 conversion. The service does not silently select a smaller or Turbo model based on the device. See the [model folder](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3).

Argmax's `download(variant:)` performs suffix matching on model folder names. Passing the complete folder name followed internally by the path separator excludes similarly named quantized and Turbo folders. The service also verifies the returned path. See the [download implementation](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Sources/WhisperKit/Core/WhisperKit.swift).

The tokenizer comes from OpenAI's `whisper-large-v3` repository at revision `06f233fe06e710322aca913c1bc4249a0d71fce1`. Only `tokenizer.json` and `tokenizer_config.json` are downloaded. HTTP errors and invalid JSON fail the installation. See [OpenAI's tokenizer files](https://huggingface.co/openai/whisper-large-v3/tree/06f233fe06e710322aca913c1bc4249a0d71fce1).

## Download, runtime, and removal

`WhisperModelService` owns the download task and an app-specific Application Support directory excluded from backup. The ready marker is written only after the complete model and tokenizer successfully load. An interrupted download does not become ready. Cancel stops the task, retry reuses the library's download cache, and delete removes this model's app-managed files.

During transcription, FreeSpeak loads the downloaded folder with automatic model downloads disabled. It validates the local tokenizer first. WhisperKit itself has a tokenizer download fallback if its own local tokenizer load fails, so this integration does not claim to disable every possible upstream metadata request. It never uploads audio. See [tokenizer loading](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Sources/WhisperKit/Utilities/ModelUtilities.swift).

Audio is processed incrementally in 30-second chunks with one buffered chunk and one decoding worker. Core ML weights are unloaded before returning text so S1 cleanup does not run alongside a retained Whisper runtime. These choices limit avoidable memory overlap but do not establish that full Large v3 fits every iPhone. See [audio loading options](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Sources/WhisperKit/Core/Audio/AudioProcessor.swift) and [decoding options](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/Sources/WhisperKit/Core/Configurations.swift).

## Validation limits

The official `WhisperKit` target compiled from release `1.1.0`. `WhisperModelService.swift` passed Swift 6 type checking with default main actor isolation against that compiled macOS module. Swift formatting and strict lint passed; the integrated iOS build is a separate check.

No model weights were downloaded during development. Download progress, cancellation, tokenizer initialization, Core ML preparation, recognition quality, airplane-mode operation, and peak memory need physical-device testing. The initial full-model load can take minutes and an iOS memory termination cannot be caught as a Swift error. The app should keep that limit visible before the user downloads 3.1 GB.

The package is pinned. Argmax's model download API reads the model repository's current default branch, so model weights are not revision-pinned by this integration. A release build should additionally pin or verify a file manifest once the chosen weights pass device testing.
