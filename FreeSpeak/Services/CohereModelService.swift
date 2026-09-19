import AVFoundation
import FluidAudio
import Foundation
import Observation

/// Experimental iPhone adapter for FluidAudio's INT8 Cohere encoder and v2 decoder.
@MainActor
@Observable
final class CohereModelService {
  private(set) var isReady = false
  private(set) var isDownloading = false
  private(set) var isTranscribing = false
  private(set) var status = "Not downloaded · Experimental"

  @ObservationIgnored private var downloadTask: Task<CoherePipeline.LoadedModels, Error>?
  @ObservationIgnored private var models: CoherePipeline.LoadedModels?
  @ObservationIgnored private var pipeline: CoherePipeline?

  private let baseDirectory: URL
  private let directory: URL
  private let readyMarker: URL
  nonisolated private static let maximumDuration: Double = 300
  // The duration check enforces five minutes. Decoder/resampler padding can
  // produce a few extra frames, which must be preserved instead of truncated.
  nonisolated private static let maximumSamples = 300 * CohereAsrConfig.sampleRate + 1_600

  init() {
    baseDirectory = URL.applicationSupportDirectory.appendingPathComponent(
      "FreeSpeak/CohereModels", isDirectory: true)
    directory = baseDirectory.appendingPathComponent(
      Repo.cohereTranscribeCoreml.folderName, isDirectory: true)
    readyMarker = directory.appendingPathComponent("freespeak-cohere-v2-ready")
    isReady =
      FileManager.default.fileExists(atPath: readyMarker.path)
      && ModelNames.CohereTranscribe.requiredModels.allSatisfy {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
      }
    if isReady { status = "Downloaded · Experimental on iPhone" }
  }

  /// The download completes only after Core ML can load both models and vocabulary.
  func download() async throws {
    guard !isDownloading, !isTranscribing else { throw CohereServiceError.busy }
    if isReady { return }
    isDownloading = true
    status = "Downloading Cohere, about 2.2 GB. First preparation may take several minutes…"
    let baseDirectory = baseDirectory
    let directory = directory
    let task = Task {
      try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
      var cacheDirectory = baseDirectory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try cacheDirectory.setResourceValues(values)
      try await ModelHub.download(.cohereTranscribeCoreml, to: baseDirectory)
      try Task.checkCancellation()
      return try await CoherePipeline.loadModels(
        encoderDir: directory, decoderDir: directory, vocabDir: directory,
        decoderVariant: .v2)
    }
    downloadTask = task
    defer {
      downloadTask = nil
      isDownloading = false
    }

    do {
      let loaded = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      try Task.checkCancellation()
      guard !task.isCancelled else { throw CancellationError() }
      try Data("FluidAudio-0.15.7-cohere-q8-v2".utf8).write(to: readyMarker, options: .atomic)
      models = loaded
      isReady = true
      status = "Downloaded · Experimental on iPhone"
    } catch {
      isReady = false
      if Task.isCancelled || task.isCancelled || error is CancellationError {
        status = "Download cancelled. Tap Download to resume."
        throw CancellationError()
      }
      status = "Cohere preparation failed: \(error.localizedDescription)"
      throw error
    }
  }

  func cancelDownload() {
    downloadTask?.cancel()
    if isDownloading { status = "Cancelling Cohere download…" }
  }

  func delete() throws {
    guard !isDownloading, !isTranscribing else { throw CohereServiceError.busy }
    models = nil
    pipeline = nil
    if FileManager.default.fileExists(atPath: baseDirectory.path) {
      try FileManager.default.removeItem(at: baseDirectory)
    }
    isReady = false
    status = "Not downloaded · Experimental"
  }

  /// Covers the whole recording through the runtime's overlapping 35-second windows.
  func transcribe(url: URL, locale: String) async throws -> String {
    guard !isDownloading, !isTranscribing else { throw CohereServiceError.busy }
    guard isReady else { throw CohereServiceError.notDownloaded }
    let code = Locale(identifier: locale).language.languageCode?.identifier ?? locale.lowercased()
    guard let language = CohereAsrConfig.Language(rawValue: code) else {
      throw CohereServiceError.unsupportedLanguage(locale)
    }
    isTranscribing = true
    status = "Preparing Cohere. First use may take several minutes…"
    defer { isTranscribing = false }

    do {
      // Decode directly into bounded 16 kHz storage rather than retaining a
      // potentially much larger native-rate recording before resampling it.
      let conversion = Task.detached {
        try await Self.readSamples(from: url)
      }
      let samples = try await withTaskCancellationHandler {
        try await conversion.value
      } onCancel: {
        conversion.cancel()
      }
      try Task.checkCancellation()
      if models == nil {
        models = try await CoherePipeline.loadModels(
          encoderDir: directory, decoderDir: directory, vocabDir: directory,
          decoderVariant: .v2)
      }
      try Task.checkCancellation()
      guard let models else { throw CohereServiceError.notDownloaded }
      if pipeline == nil { pipeline = CoherePipeline() }
      guard let pipeline else { throw CohereServiceError.notDownloaded }
      status = "Transcribing with Cohere on this iPhone…"
      let result = try await pipeline.transcribeLong(
        audio: samples, models: models, language: language)
      try Task.checkCancellation()
      let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw CohereServiceError.noSpeech }
      status = "Downloaded · Experimental on iPhone"
      return text
    } catch {
      status =
        error is CancellationError
        ? "Downloaded · Experimental on iPhone"
        : "Cohere transcription failed: \(error.localizedDescription)"
      throw error
    }
  }

  /// Release the large ASR weights before another local engine needs memory.
  func unload() {
    guard !isDownloading, !isTranscribing else { return }
    models = nil
    pipeline = nil
  }

  /// AVAssetReader performs sample-rate conversion while decoding bounded buffers.
  nonisolated private static func readSamples(from url: URL) async throws -> [Float] {
    try Task.checkCancellation()
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0 else { throw CohereServiceError.noSpeech }
    guard duration <= maximumDuration else { throw CohereServiceError.tooLong }
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw CohereServiceError.noSpeech
    }
    try Task.checkCancellation()
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: CohereAsrConfig.sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw CohereServiceError.audioConversion }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? CohereServiceError.audioConversion
    }
    defer { reader.cancelReading() }
    var samples: [Float] = []
    samples.reserveCapacity(min(maximumSamples, Int(duration * Double(CohereAsrConfig.sampleRate))))
    while let buffer = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      guard let block = CMSampleBufferGetDataBuffer(buffer) else {
        throw CohereServiceError.audioConversion
      }
      let byteCount = CMBlockBufferGetDataLength(block)
      guard byteCount.isMultiple(of: MemoryLayout<Float>.size) else {
        throw CohereServiceError.audioConversion
      }
      let count = byteCount / MemoryLayout<Float>.size
      guard count <= maximumSamples - samples.count else { throw CohereServiceError.tooLong }
      var chunk = [Float](repeating: 0, count: count)
      let status = chunk.withUnsafeMutableBytes { bytes in
        guard let destination = bytes.baseAddress else { return noErr }
        return CMBlockBufferCopyDataBytes(
          block, atOffset: 0, dataLength: byteCount, destination: destination)
      }
      guard status == noErr else { throw CohereServiceError.audioConversion }
      samples.append(contentsOf: chunk)
    }
    try Task.checkCancellation()
    guard reader.status == .completed else {
      throw reader.error ?? CohereServiceError.audioConversion
    }
    guard !samples.isEmpty else { throw CohereServiceError.noSpeech }
    return samples
  }
}

private enum CohereServiceError: LocalizedError {
  case busy
  case notDownloaded
  case unsupportedLanguage(String)
  case tooLong
  case noSpeech
  case audioConversion

  var errorDescription: String? {
    switch self {
    case .busy:
      "Cohere is busy. Wait for the current operation to finish."
    case .notDownloaded:
      "Download Cohere Transcribe in Models before using it."
    case .unsupportedLanguage(let locale):
      "Cohere does not support \(locale). Choose English, French, German, Spanish, Italian, Portuguese, Dutch, Polish, Greek, Arabic, Japanese, Chinese, Korean, or Vietnamese in Settings."
    case .tooLong:
      "Cohere's experimental iPhone integration accepts up to five minutes. Record a shorter clip or choose another speech model. Your audio has not been truncated."
    case .noSpeech:
      "Cohere found no speech. Try recording again."
    case .audioConversion:
      "Cohere could not decode this audio file. Try importing another audio format."
    }
  }
}
