import Foundation
import Observation
@preconcurrency import WhisperKit

/// Downloads the full Whisper Large v3 conversion and keeps inference on this device.
@MainActor
@Observable
final class WhisperModelService {
  private(set) var isReady = false
  private(set) var isDownloading = false
  private(set) var isTranscribing = false
  private(set) var status = "Not downloaded"

  @ObservationIgnored private var downloadTask: Task<Void, Error>?
  private let directory: URL
  private let modelFolder: URL
  private let tokenizerFolder: URL
  private let readyMarker: URL
  private let variant = "openai_whisper-large-v3"

  init() {
    directory = URL.applicationSupportDirectory.appendingPathComponent(
      "WhisperLargeV3", isDirectory: true)
    modelFolder = directory.appendingPathComponent(
      "models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3", isDirectory: true)
    tokenizerFolder = directory.appendingPathComponent("tokenizer", isDirectory: true)
    readyMarker = directory.appendingPathComponent("freespeak-whisper-1.1.0-ready")
    isReady = FileManager.default.fileExists(atPath: readyMarker.path) && filesExist()
    if isReady { status = "Ready on this iPhone" }
  }

  /// The ready marker is written only after model and tokenizer loading succeed.
  func download() async throws {
    guard !isDownloading, !isTranscribing else { throw ModelError.busy }
    if isReady { return }
    isDownloading = true
    status = "Downloading Whisper Large v3, about 3.1 GB…"
    let task = Task {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var excludedDirectory = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try excludedDirectory.setResourceValues(values)

      let downloadedFolder = try await WhisperKit.download(
        variant: variant,
        downloadBase: directory,
        from: "argmaxinc/whisperkit-coreml",
        progressCallback: { [weak self] progress in
          let percent = Int(progress.fractionCompleted * 100)
          Task { @MainActor [weak self] in
            guard let self, self.isDownloading, self.downloadTask?.isCancelled != true else {
              return
            }
            self.status = "Downloading Whisper Large v3: \(percent)%"
          }
        }
      )
      try Task.checkCancellation()
      guard downloadedFolder.standardizedFileURL.path == modelFolder.standardizedFileURL.path else {
        throw ModelError.unexpectedModel
      }
      status = "Downloading Whisper's tokenizer…"
      try await downloadTokenizer()
      try Task.checkCancellation()
      status = "Preparing Whisper Large v3. The first load can take a few minutes…"
      let engine = try await loadEngine()
      await engine.unloadModels()
      try Task.checkCancellation()
    }
    downloadTask = task
    defer {
      downloadTask = nil
      isDownloading = false
    }
    do {
      try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      try Task.checkCancellation()
      guard !task.isCancelled else { throw CancellationError() }
      try Data(variant.utf8).write(to: readyMarker, options: .atomic)
      isReady = true
      status = "Ready on this iPhone"
    } catch {
      isReady = false
      if task.isCancelled || Task.isCancelled || error is CancellationError {
        status = "Download cancelled. Tap Download to retry."
        throw CancellationError()
      }
      status = "Download failed: \(error.localizedDescription)"
      throw error
    }
  }

  func cancelDownload() {
    downloadTask?.cancel()
    if isDownloading { status = "Cancelling download…" }
  }

  func delete() throws {
    guard !isDownloading, !isTranscribing else { throw ModelError.busy }
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    isReady = false
    status = "Not downloaded"
  }

  func transcribe(url: URL, locale: String) async throws -> String {
    guard !isDownloading, !isTranscribing else { throw ModelError.busy }
    guard isReady, filesExist() else {
      isReady = false
      throw ModelError.notDownloaded
    }
    isTranscribing = true
    status = "Loading Whisper Large v3…"
    defer { isTranscribing = false }
    do {
      let engine = try await loadEngine()
      do {
        try Task.checkCancellation()
        status = "Transcribing with Whisper on this iPhone…"
        let language = Locale(identifier: locale).language.languageCode?.identifier
        let options = DecodingOptions(
          verbose: false,
          task: .transcribe,
          language: language,
          detectLanguage: language == nil,
          skipSpecialTokens: true,
          concurrentWorkerCount: 1
        )
        let results = try await engine.transcribe(
          audioPath: url.path,
          audioInputOptions: AudioInputOptions(
            audioLoadingMode: .incremental(chunkDurationSeconds: 30, maxBufferedChunks: 1)),
          decodeOptions: options
        )
        // Release Core ML weights before the caller loads its cleanup model.
        await engine.unloadModels()
        try Task.checkCancellation()
        let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ModelError.noSpeech }
        status = "Ready on this iPhone"
        return text
      } catch {
        await engine.unloadModels()
        throw error
      }
    } catch {
      status =
        error is CancellationError
        ? "Ready on this iPhone" : "Transcription failed: \(error.localizedDescription)"
      throw error
    }
  }

  private func loadEngine() async throws -> WhisperKit {
    // Validate the local tokenizer before WhisperKit's loader can attempt a missing-tokenizer fetch.
    _ = try await AutoTokenizerWrapper.from(modelFolder: tokenizerFolder)
    return try await WhisperKit(
      WhisperKitConfig(
        model: variant,
        modelFolder: modelFolder.path,
        tokenizerFolder: tokenizerFolder,
        verbose: false,
        prewarm: false,
        load: true,
        download: false
      )
    )
  }

  private func downloadTokenizer() async throws {
    try FileManager.default.createDirectory(at: tokenizerFolder, withIntermediateDirectories: true)
    // Tokenizer assets are pinned to OpenAI's model revision independently of Argmax's conversion.
    let revision = "06f233fe06e710322aca913c1bc4249a0d71fce1"
    for name in ["tokenizer.json", "tokenizer_config.json"] {
      let url = URL(
        string: "https://huggingface.co/openai/whisper-large-v3/resolve/\(revision)/\(name)")!
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        throw ModelError.tokenizerDownload
      }
      _ = try JSONSerialization.jsonObject(with: data)
      try Task.checkCancellation()
      try data.write(to: tokenizerFolder.appendingPathComponent(name), options: .atomic)
    }
  }

  private func filesExist() -> Bool {
    let paths = [
      modelFolder.appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin"),
      modelFolder.appendingPathComponent("TextDecoder.mlmodelc/weights/weight.bin"),
      modelFolder.appendingPathComponent("MelSpectrogram.mlmodelc"),
      tokenizerFolder.appendingPathComponent("tokenizer.json"),
      tokenizerFolder.appendingPathComponent("tokenizer_config.json"),
    ]
    return paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
  }

  private enum ModelError: LocalizedError {
    case busy
    case notDownloaded
    case unexpectedModel
    case tokenizerDownload
    case noSpeech

    var errorDescription: String? {
      switch self {
      case .busy: "Whisper is busy. Wait for the current operation to finish."
      case .notDownloaded: "Download Whisper Large v3 in Models before using it."
      case .unexpectedModel: "Whisper downloaded an unexpected model. Delete it and try again."
      case .tokenizerDownload: "Whisper's tokenizer download failed. Try downloading again."
      case .noSpeech: "No speech was found. Try recording again."
      }
    }
  }
}
