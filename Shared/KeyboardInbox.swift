import Foundation

/// A single completed transcript shared by the app and its read-only keyboard.
struct KeyboardTranscript: Codable, Equatable, Identifiable {
  let id: UUID
  let text: String
  let createdAt: Date
}

struct KeyboardInbox {
  static let appGroup = "group.ari.FreeSpeak"
  private let containerURL: URL?

  init(
    containerURL: URL? = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroup)
  ) {
    self.containerURL = containerURL
  }

  func publish(id: UUID, text: String, createdAt: Date) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let url = try inboxURL()
    let record = KeyboardTranscript(id: id, text: text, createdAt: createdAt)
    #if os(iOS)
      let options: Data.WritingOptions = [.atomic, .completeFileProtection]
    #else
      let options: Data.WritingOptions = [.atomic]
    #endif
    try JSONEncoder().encode(record).write(to: url, options: options)
  }

  func latest() throws -> KeyboardTranscript? {
    let url = try inboxURL()
    do {
      return try JSONDecoder().decode(KeyboardTranscript.self, from: Data(contentsOf: url))
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    }
  }

  func clear() throws {
    do { try FileManager.default.removeItem(at: inboxURL()) } catch CocoaError.fileNoSuchFile {}
  }

  private func inboxURL() throws -> URL {
    guard let containerURL else { throw InboxError.unavailable }
    return containerURL.appendingPathComponent("keyboard-transcript.json")
  }

  enum InboxError: LocalizedError {
    case unavailable
    var errorDescription: String? {
      "The shared keyboard container is unavailable. Check the App Group configuration."
    }
  }
}
