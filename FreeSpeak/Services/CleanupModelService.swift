import CryptoKit
import Foundation
import llama

/// Runs the publisher's English-only normalizer locally. Each request releases its model memory.
actor CleanupModelService {
  enum Style: String, Sendable {
    case casual
    case semiCasual = "semi-casual"
    case semiFormal = "semi-formal"
    case formal
  }

  enum Structure: String, Sendable { case prose, lists }
  enum Context: String, Sendable { case general, email }

  enum CleanupError: LocalizedError {
    case notDownloaded, downloadFailed, invalidDownload, loadFailed, contextFailed
    case tooLong, tokenizationFailed, generationFailed, outputLimit, downloadInProgress

    var errorDescription: String? {
      switch self {
      case .notDownloaded: "Download S1-mini by Superwhisper in Models before using local cleanup."
      case .downloadFailed: "The S1-mini download failed. Check your connection and try again."
      case .invalidDownload: "The downloaded S1-mini file failed its integrity check. Please retry."
      case .loadFailed: "S1-mini could not load. Close other apps or download the model again."
      case .contextFailed: "There was not enough memory to start S1-mini."
      case .tooLong:
        "S1-mini handles up to 1,000 transcript tokens. Use shorter dictations or another cleanup model."
      case .tokenizationFailed:
        "S1-mini could not read this transcript. Your original transcript is preserved."
      case .generationFailed:
        "S1-mini could not finish cleanup. Your original transcript is preserved."
      case .outputLimit: "S1-mini reached its output limit. Your original transcript is preserved."
      case .downloadInProgress: "S1-mini is already downloading."
      }
    }
  }

  nonisolated static let modelByteCount: Int64 = 484_219_808
  nonisolated private static let revision = "34add00a48a2e5d24e5a4ee5405a99620a3a240c"
  nonisolated private static let filename = "s1-mini-q4_k_m.gguf"
  nonisolated private static let expectedSHA256 =
    "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634"
  private var downloading = false

  nonisolated static var modelURL: URL {
    URL.applicationSupportDirectory
      .appending(path: "FreeSpeak/Models/S1-mini", directoryHint: .isDirectory)
      .appending(path: filename)
  }

  nonisolated static var isDownloaded: Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
      let size = attributes[.size] as? NSNumber
    else { return false }
    return size.int64Value == modelByteCount
  }

  /// Stores a revision-pinned artifact only after verifying its full SHA-256 digest.
  func download() async throws {
    guard !downloading else { throw CleanupError.downloadInProgress }
    if Self.isDownloaded { return }
    downloading = true
    defer { downloading = false }

    let remote = URL(
      string:
        "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/\(Self.revision)/\(Self.filename)"
    )!
    let (temporaryURL, response) = try await URLSession.shared.download(from: remote)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw CleanupError.downloadFailed
    }
    try Task.checkCancellation()
    let file = try FileHandle(forReadingFrom: temporaryURL)
    defer { try? file.close() }
    var hash = SHA256()
    var byteCount: Int64 = 0
    while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
      try Task.checkCancellation()
      hash.update(data: data)
      byteCount += Int64(data.count)
    }
    let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
    guard digest == Self.expectedSHA256, byteCount == Self.modelByteCount else {
      throw CleanupError.invalidDownload
    }
    let directory = Self.modelURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: Self.modelURL.path) {
      try FileManager.default.removeItem(at: Self.modelURL)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: Self.modelURL)
    var directoryURL = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directoryURL.setResourceValues(values)
  }

  func remove() throws {
    guard !downloading else { throw CleanupError.downloadInProgress }
    if FileManager.default.fileExists(atPath: Self.modelURL.path) {
      try FileManager.default.removeItem(at: Self.modelURL)
    }
  }

  /// Uses the exact S1 template, including the empty thinking block and greedy decoding.
  func clean(
    _ transcript: String,
    style: Style = .semiFormal,
    structure: Structure = .prose,
    context: Context = .general
  ) throws -> String {
    try Task.checkCancellation()
    if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
    guard Self.isDownloaded else { throw CleanupError.notDownloaded }
    llama_backend_init()
    var parameters = llama_model_default_params()
    #if targetEnvironment(simulator)
      parameters.n_gpu_layers = 0
    #endif
    guard let model = llama_model_load_from_file(Self.modelURL.path, parameters) else {
      throw CleanupError.loadFailed
    }
    defer { llama_model_free(model) }
    guard let vocabulary = llama_model_get_vocab(model) else { throw CleanupError.loadFailed }
    guard try tokenize(transcript, vocabulary: vocabulary, parseSpecial: false).count <= 1_000
    else {
      throw CleanupError.tooLong
    }

    // Encode the user's text separately so literal ChatML markers cannot become control tokens.
    let prefix = """
      <|im_start|>system
      You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text.<|im_end|>
      <|im_start|>user
      [Styling: \(style.rawValue)] [Structure: \(structure.rawValue)] [Context: \(context.rawValue)]

      """
    let suffix = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    var tokens = try tokenize(prefix, vocabulary: vocabulary, parseSpecial: true)
    tokens += try tokenize(transcript, vocabulary: vocabulary, parseSpecial: false)
    tokens += try tokenize(suffix, vocabulary: vocabulary, parseSpecial: true)

    var contextParameters = llama_context_default_params()
    contextParameters.n_ctx = 2_304
    contextParameters.n_batch = 256
    contextParameters.n_threads = Int32(
      max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
    contextParameters.n_threads_batch = contextParameters.n_threads
    guard let inference = llama_init_from_model(model, contextParameters) else {
      throw CleanupError.contextFailed
    }
    defer { llama_free(inference) }
    guard let sampler = llama_sampler_init_greedy() else { throw CleanupError.contextFailed }
    defer { llama_sampler_free(sampler) }

    for start in stride(from: 0, to: tokens.count, by: 256) {
      try Task.checkCancellation()
      var chunk = Array(tokens[start..<min(start + 256, tokens.count)])
      let status = chunk.withUnsafeMutableBufferPointer { buffer in
        llama_decode(inference, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
      }
      guard status == 0 else { throw CleanupError.generationFailed }
    }

    var bytes: [UInt8] = []
    let outputBudget = min(1_100, Int(llama_n_ctx(inference)) - tokens.count)
    for _ in 0..<outputBudget {
      try Task.checkCancellation()
      var token = llama_sampler_sample(sampler, inference, -1)
      if llama_vocab_is_eog(vocabulary, token) {
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)
      }
      bytes += try piece(token, vocabulary: vocabulary)
      let status = withUnsafeMutablePointer(to: &token) { pointer in
        llama_decode(inference, llama_batch_get_one(pointer, 1))
      }
      guard status == 0 else { throw CleanupError.generationFailed }
    }
    throw CleanupError.outputLimit
  }

  private func tokenize(_ text: String, vocabulary: OpaquePointer, parseSpecial: Bool) throws
    -> [llama_token]
  {
    guard text.utf8.count < Int(Int32.max) else { throw CleanupError.tooLong }
    var tokens = [llama_token](repeating: 0, count: text.utf8.count + 16)
    let count = llama_tokenize(
      vocabulary, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), false, parseSpecial)
    guard count >= 0 else { throw CleanupError.tokenizationFailed }
    return Array(tokens.prefix(Int(count)))
  }

  private func piece(_ token: llama_token, vocabulary: OpaquePointer) throws -> [UInt8] {
    var buffer = [CChar](repeating: 0, count: 128)
    var count = llama_token_to_piece(vocabulary, token, &buffer, Int32(buffer.count), 0, false)
    if count < 0 {
      buffer = [CChar](repeating: 0, count: Int(-count))
      count = llama_token_to_piece(vocabulary, token, &buffer, Int32(buffer.count), 0, false)
    }
    guard count >= 0 else { throw CleanupError.generationFailed }
    return buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
  }
}
