import AppIntents
import Foundation
import Observation

/// Holds an intent request even when the app's first view has not been created yet.
@MainActor @Observable
final class DictationLaunchRequest {
  static let shared = DictationLaunchRequest()
  var pending = false

  private init() {}
}

struct StartDictationIntent: AppIntent {
  static let title: LocalizedStringResource = "Start dictation"
  static let description = IntentDescription(
    "Open Steno and begin recording with your selected mode.")
  static let openAppWhenRun = true
  static let supportedModes: IntentModes = .foreground(.immediate)

  @MainActor
  func perform() async throws -> some IntentResult {
    DictationLaunchRequest.shared.pending = true
    return .result()
  }
}

struct FreeSpeakShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartDictationIntent(),
      phrases: [
        "Start dictation in \(.applicationName)",
        "Record with \(.applicationName)",
      ],
      shortTitle: "Start dictation",
      systemImageName: "waveform"
    )
  }
}
