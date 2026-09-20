import FluidAudio
import Foundation
import Observation

/// Owns the Parakeet download and runtime in the containing app.
@MainActor
@Observable
final class LocalModelService {
  private(set) var isDownloading = false
  private(set) var isReady = false
  private(set) var isTranscribing = false
  private(set) var status = "Not downloaded"

  @ObservationIgnored private var downloadTask: Task<AsrModels, Error>?
  @ObservationIgnored private var manager: AsrManager?

  // The corrected encoder avoids the original v3 quantization corruption.
  private let precision = ParakeetEncoderPrecision.int8V2
  private let directory: URL
  private let readyMarker: URL

  init() {
    directory = AsrModels.defaultCacheDirectory(for: .v3)
    readyMarker = directory.appendingPathComponent("freespeak-int8-v2-ready")
    isReady =
      FileManager.default.fileExists(atPath: readyMarker.path)
      && AsrModels.modelsExist(at: directory, version: .v3, encoderPrecision: precision)
    if isReady { status = "Ready on this iPhone" }
  }

  /// Downloads only this variant, then validates it by loading the models.
  func download() async throws {
    guard !isDownloading, !isTranscribing else { throw LocalModelError.busy }
    if isReady { return }
    isDownloading = true
    status = "Downloading and preparing Parakeet, about 632 MB…"

    let directory = directory
    let precision = precision
    let task = Task {
      try await AsrModels.downloadAndLoad(
        to: directory,
        version: .v3,
        encoderPrecision: precision
      )
    }
    downloadTask = task
    defer {
      downloadTask = nil
      isDownloading = false
    }

    do {
      let models = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      try Task.checkCancellation()
      guard !task.isCancelled else { throw CancellationError() }
      // Existence alone is insufficient: an interrupted bundle can be incomplete.
      try Data("0.15.7-int8-v2".utf8).write(to: readyMarker, options: .atomic)
      var modelDirectory = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? modelDirectory.setResourceValues(values)
      manager = AsrManager(models: models)
      isReady = true
      status = "Ready on this iPhone"
    } catch {
      isReady = false
      if Task.isCancelled || task.isCancelled || error is CancellationError {
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
    guard !isDownloading, !isTranscribing else { throw LocalModelError.busy }
    manager = nil
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    isReady = false
    status = "Not downloaded"
  }

  func transcribe(url: URL) async throws -> String {
    guard !isDownloading, !isTranscribing else { throw LocalModelError.busy }
    guard isReady else { throw LocalModelError.notDownloaded }
    isTranscribing = true
    status = "Transcribing on this iPhone…"
    defer { isTranscribing = false }

    do {
      if manager == nil {
        let models = try await AsrModels.load(
          from: directory,
          version: .v3,
          encoderPrecision: precision
        )
        manager = AsrManager(models: models)
      }
      try Task.checkCancellation()
      guard let manager else { throw LocalModelError.notDownloaded }
      var decoderState = try TdtDecoderState()
      let result = try await manager.transcribe(url, decoderState: &decoderState)
      try Task.checkCancellation()
      let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw LocalModelError.noSpeech }
      status = "Ready on this iPhone"
      return text
    } catch {
      status =
        error is CancellationError
        ? "Ready on this iPhone" : "Transcription failed: \(error.localizedDescription)"
      throw error
    }
  }

  /// Release model memory before loading a separate cleanup model.
  func unload() {
    guard !isTranscribing, !isDownloading else { return }
    manager = nil
  }
}

private enum LocalModelError: LocalizedError {
  case busy
  case notDownloaded
  case noSpeech

  var errorDescription: String? {
    switch self {
    case .busy: "Parakeet is busy. Wait for the current operation to finish."
    case .notDownloaded: "Download Parakeet in Models before using it."
    case .noSpeech: "No speech was found. Try recording again."
    }
  }
}
