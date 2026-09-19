import Foundation

// These controllable services are compiled only by run-app-store-tests.sh.
// AppStore and its persistent model types come from the production source files.

@MainActor final class AudioRecorder {
  var onInterruption: (() -> Void)?
  var duration: TimeInterval = 0
  var shouldFailToStart = false
  var startDelay: Duration = .zero
  var stopCalls = 0
  func start() async throws {
    try await Task.sleep(for: startDelay)
    if shouldFailToStart { throw CocoaError(.fileWriteNoPermission) }
  }
  func stop() async throws -> URL? {
    stopCalls += 1
    try await Task.sleep(for: .milliseconds(30))
    return nil
  }
  func discard() {}
}
@MainActor final class LocalModelService {
  var isReady = true
  var isDownloading = false
  func transcribe(url: URL) async throws -> String {
    try await AppleSpeechService.transcribe(url: url, locale: .current)
  }
  func unload() {}
}
@MainActor final class WhisperModelService {
  var isReady = true
  var isDownloading = false
  func transcribe(url: URL, locale: String) async throws -> String {
    try await AppleSpeechService.transcribe(url: url, locale: .current)
  }
}
@MainActor final class CohereModelService {
  var isReady = true
  var isDownloading = false
  func transcribe(url: URL, locale: String) async throws -> String {
    try await AppleSpeechService.transcribe(url: url, locale: .current)
  }
  func unload() {}
}
@MainActor enum AppleSpeechService {
  static var calls = 0
  static func transcribe(url: URL, locale: Locale) async throws -> String {
    calls += 1
    try await Task.sleep(for: .milliseconds(30))
    return "original speech"
  }
}
@MainActor enum CloudSpeechService {
  static func transcribe(
    url: URL, provider: SpeechProvider, key: String, locale: String, vocabulary: [VocabularyEntry]
  ) async throws -> String {
    try await AppleSpeechService.transcribe(url: url, locale: .current)
  }
  static func clean(
    text: String, provider: CleanupProvider, key: String, model: String, mode: DictationMode,
    vocabulary: [VocabularyEntry]
  ) async throws -> String {
    try await Task.sleep(for: .seconds(60))
    return "cleaned"
  }
}
actor CleanupModelService {
  private var output: String?
  func setOutput(_ output: String) { self.output = output }
  enum Style: String { case semiFormal = "semi-formal" }
  enum Structure: String { case prose }
  enum Context: String { case general }
  func clean(_ raw: String, style: Style, structure: Structure, context: Context) throws -> String {
    output ?? raw
  }
}
enum KeychainStore {
  static func read(_ provider: String) -> String { provider == "openAI" ? "test-key" : "" }
}
@MainActor struct KeyboardInbox {
  static var shouldFail = false
  static var clearCount = 0
  func publish(id: UUID, text: String, createdAt: Date) throws {
    if Self.shouldFail { throw CocoaError(.fileWriteNoPermission) }
  }
  func clear() throws { Self.clearCount += 1 }
}
