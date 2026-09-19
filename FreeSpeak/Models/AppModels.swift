import Foundation

enum SpeechProvider: String, Codable, CaseIterable, Identifiable {
  case apple, parakeet, whisper, cohere, openAI, grok

  var id: String { rawValue }
  var name: String {
    switch self {
    case .apple: "Apple Speech"
    case .parakeet: "Parakeet v3"
    case .whisper: "Whisper Large v3"
    case .cohere: "Cohere Transcribe"
    case .openAI: "OpenAI"
    case .grok: "Grok"
    }
  }
  var isLocal: Bool { self != .openAI && self != .grok }
  var subtitle: String {
    switch self {
    case .apple: "On-device · Speech Analyzer"
    case .parakeet: "On-device · NVIDIA Parakeet TDT"
    case .whisper: "On-device · OpenAI Whisper"
    case .cohere: "On-device · Experimental"
    case .openAI: "Cloud · GPT-4o Transcribe"
    case .grok: "Cloud · xAI speech to text"
    }
  }
}

enum CleanupProvider: String, Codable, CaseIterable, Identifiable {
  case none, s1Mini, openAI, grok
  var id: String { rawValue }
  var name: String {
    switch self {
    case .none: "Original transcript"
    case .s1Mini: "S1-mini by Superwhisper"
    case .openAI: "OpenAI"
    case .grok: "Grok"
    }
  }
  var isCloud: Bool { self == .openAI || self == .grok }
}

struct DictationMode: Codable, Identifiable, Equatable {
  var id: UUID = UUID()
  var name: String
  var symbol: String
  var detail: String
  var instructions: String
  var localStyle = "semi-formal"
  var localStructure = "prose"
  var localContext = "general"

  static let defaults: [Self] = [
    .init(
      name: "Natural", symbol: "waveform", detail: "Your words, a little clearer.",
      instructions:
        "Remove filler words and false starts. Correct punctuation. Preserve the speaker's tone, meaning, and language. Do not add information."
    ),
    .init(
      name: "Message", symbol: "bubble.left", detail: "Ready to send.",
      instructions:
        "Format as a concise casual message. Remove filler words and correct punctuation. Preserve meaning and language. Do not add a greeting or sign-off unless spoken.",
      localStyle: "casual"),
    .init(
      name: "Notes", symbol: "list.bullet", detail: "Give your thoughts some structure.",
      instructions:
        "Organize the dictated text into clear notes with bullet points when useful. Preserve every fact and the original language. Never invent details.",
      localStructure: "lists"),
    .init(
      name: "Verbatim", symbol: "quote.opening", detail: "Exactly what you said.", instructions: ""),
  ]
}

struct VocabularyEntry: Codable, Identifiable {
  var id: UUID = UUID()
  var word: String
  var hint: String
}

struct Transcript: Codable, Identifiable {
  var id: UUID = UUID()
  var date: Date = .now
  var text: String
  var original: String
  var modeName: String
  var providerName: String
  var duration: TimeInterval
  var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
  var title: String { String(text.prefix(70)) }
}

struct AppSettings: Codable {
  var speechProvider: SpeechProvider = .apple
  var cleanupProvider: CleanupProvider = .none
  var localeIdentifier = "en-US"
  var saveHistory = true
  var openAICleanupModel = "gpt-4.1-mini"
  var grokCleanupModel = "grok-4.3"
}

struct SavedState: Codable {
  var settings = AppSettings()
  var modes = DictationMode.defaults
  var selectedModeID: UUID?
  var vocabulary: [VocabularyEntry] = []
  var transcripts: [Transcript] = []
}
