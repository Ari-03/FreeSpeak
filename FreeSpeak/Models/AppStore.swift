import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class AppStore {
  var saved = SavedState() { didSet { persist() } }
  var phase: Phase = .idle
  var errorMessage: String?
  var notice: String?
  var latestTranscript: Transcript?
  let recorder = AudioRecorder()
  let localModels = LocalModelService()
  let whisper = WhisperModelService()
  let cohere = CohereModelService()
  let cleanupModel = CleanupModelService()
  private var work: Task<Void, Never>?
  private var pendingAudio: URL?
  private var pendingDuration: TimeInterval = 0
  private var historyGeneration = 0
  private var preserveUnreadableState = false
  private let stateURL: URL

  enum Phase: Equatable {
    case idle, preparing, recording, transcribing, cleaning
    var isBusy: Bool { self != .idle && self != .recording }
    var label: String {
      switch self {
      case .idle: "Ready when you are"
      case .preparing: "Starting microphone…"
      case .recording: "Listening to you"
      case .transcribing: "Turning speech into text…"
      case .cleaning: "Tidying your words…"
      }
    }
  }

  init(
    directory: URL = URL.applicationSupportDirectory.appendingPathComponent(
      "FreeSpeak", isDirectory: true)
  ) {
    stateURL = directory.appendingPathComponent("state.json")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: stateURL.path) {
        saved = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateURL))
      }
    } catch {
      preserveUnreadableState = FileManager.default.fileExists(atPath: stateURL.path)
      errorMessage = "Your saved data could not be loaded. \(error.localizedDescription)"
    }
    recorder.onInterruption = { [weak self] in
      guard self?.phase == .recording else { return }
      self?.finishRecording()
    }
  }

  var selectedMode: DictationMode {
    saved.modes.first { $0.id == saved.selectedModeID } ?? saved.modes.first
      ?? DictationMode.defaults[0]
  }
  var hasPendingAudio: Bool { pendingAudio != nil }

  func startRecording() {
    guard phase == .idle else { return }
    errorMessage = nil
    notice = nil
    phase = .preparing
    let settings = saved.settings
    work = Task {
      defer { work = nil }
      do {
        try validateProvider(settings)
        try await recorder.start()
        if Task.isCancelled {
          recorder.discard()
          phase = .idle
          return
        }
        clearPendingAudio()
        latestTranscript = nil
        phase = .recording
      } catch { fail(error) }
    }
  }

  func finishRecording() {
    guard phase == .recording else { return }
    phase = .transcribing
    work = Task {
      do {
        guard let url = try await recorder.stop() else {
          throw AppError.message(
            "The recording ended before audio could be saved. Please try again.")
        }
        if Task.isCancelled {
          try? FileManager.default.removeItem(at: url)
          throw CancellationError()
        }
        pendingAudio = url
        pendingDuration = recorder.duration
        phase = .idle
        work = nil
        processPendingAudio()
      } catch {
        work = nil
        fail(error)
      }
    }
  }

  func importAudio(_ source: URL) {
    guard phase == .idle else { return }
    let access = source.startAccessingSecurityScopedResource()
    defer { if access { source.stopAccessingSecurityScopedResource() } }
    do {
      try validateProvider(saved.settings)
      let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 25_000_000 else {
        throw AppError.message("Choose an audio file smaller than 25 MB.")
      }
      let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString
      ).appendingPathExtension(source.pathExtension)
      try FileManager.default.copyItem(at: source, to: destination)
      clearPendingAudio()
      pendingAudio = destination
      pendingDuration = 0
      latestTranscript = nil
      processPendingAudio()
    } catch { fail(error) }
  }

  func processPendingAudio() {
    guard phase == .idle, let url = pendingAudio else { return }
    let settings = saved.settings
    let mode = selectedMode
    let vocabulary = saved.vocabulary
    let duration = pendingDuration
    let recordingHistoryGeneration = historyGeneration
    phase = .transcribing
    errorMessage = nil
    notice = nil
    work = Task {
      defer { work = nil }
      do {
        try Task.checkCancellation()
        try validateProvider(settings)
        let raw: String
        switch settings.speechProvider {
        case .apple:
          raw = try await AppleSpeechService.transcribe(
            url: url, locale: Locale(identifier: settings.localeIdentifier))
        case .parakeet:
          defer { localModels.unload() }
          raw = try await localModels.transcribe(url: url)
        case .whisper:
          raw = try await whisper.transcribe(url: url, locale: settings.localeIdentifier)
        case .cohere:
          defer { cohere.unload() }
          raw = try await cohere.transcribe(url: url, locale: settings.localeIdentifier)
        case .openAI, .grok:
          raw = try await CloudSpeechService.transcribe(
            url: url, provider: settings.speechProvider,
            key: KeychainStore.read(settings.speechProvider.rawValue),
            locale: settings.localeIdentifier, vocabulary: vocabulary)
        }
        try Task.checkCancellation()
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw AppError.message(
            "No speech was detected. Try a clearer recording or a different model.")
        }
        var text = raw
        if settings.cleanupProvider != .none && !mode.instructions.isEmpty {
          phase = .cleaning
          do {
            if settings.cleanupProvider == .s1Mini {
              guard settings.localeIdentifier.hasPrefix("en") else {
                throw AppError.message(
                  "S1-mini supports English. Choose another cleanup model for this language.")
              }
              text = try await cleanupModel.clean(
                raw, style: .init(rawValue: mode.localStyle) ?? .semiFormal,
                structure: .init(rawValue: mode.localStructure) ?? .prose,
                context: .init(rawValue: mode.localContext) ?? .general)
            } else {
              text = try await CloudSpeechService.clean(
                text: raw, provider: settings.cleanupProvider,
                key: KeychainStore.read(settings.cleanupProvider.rawValue),
                model: settings.cleanupProvider == .openAI
                  ? settings.openAICleanupModel : settings.grokCleanupModel, mode: mode,
                vocabulary: vocabulary)
            }
          } catch {
            notice =
              "Cleanup wasn't available. Your original transcript is safe. \(error.localizedDescription)"
          }
          // Cancelling optional cleanup must not discard completed speech recognition.
          if Task.isCancelled {
            text = raw
            notice = "Cleanup cancelled. Your original transcript is ready."
          }
        } else {
          try Task.checkCancellation()
        }
        let transcript = Transcript(
          text: text, original: raw, modeName: mode.name,
          providerName: settings.speechProvider.name, duration: duration)
        latestTranscript = transcript
        do {
          if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try KeyboardInbox().clear()
          } else {
            try KeyboardInbox().publish(
              id: transcript.id, text: transcript.text, createdAt: transcript.date)
          }
        } catch {
          let keyboardNotice =
            "Your transcript is ready. Keyboard sharing is unavailable until the app is signed with its App Group."
          notice = [notice, keyboardNotice].compactMap { $0 }.joined(separator: " ")
        }
        if settings.saveHistory && saved.settings.saveHistory
          && recordingHistoryGeneration == historyGeneration
        {
          saved.transcripts.insert(transcript, at: 0)
        }
        clearPendingAudio()
        phase = .idle
      } catch { fail(error) }
    }
  }

  func cancel() {
    work?.cancel()
    if phase == .recording { recorder.discard() }
    // Async work owns the transition to idle, so a new recording cannot race its cleanup.
    if phase == .recording { phase = .idle }
  }

  func deleteHistory() {
    historyGeneration += 1
    preserveUnreadableState = false
    saved.transcripts.removeAll()
    latestTranscript = nil
    try? KeyboardInbox().clear()
    do {
      let files = try FileManager.default.contentsOfDirectory(
        at: stateURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
      for file in files
      where file.lastPathComponent.hasPrefix("state-recovery-") && file.pathExtension == "json" {
        try FileManager.default.removeItem(at: file)
      }
    } catch {
      errorMessage =
        "Some recovered history files could not be removed. \(error.localizedDescription)"
    }
  }

  private func validateProvider(_ settings: AppSettings) throws {
    guard !localModels.isDownloading, !whisper.isDownloading, !cohere.isDownloading else {
      throw AppError.message(
        "Wait for the speech model download to finish before starting a transcription.")
    }
    let provider = settings.speechProvider
    if !provider.isLocal && KeychainStore.read(provider.rawValue).isEmpty {
      throw AppError.message("Add your \(provider.name) API key in Settings first.")
    }
    if provider == .parakeet && !localModels.isReady {
      throw AppError.message("Download Parakeet in Models first.")
    }
    if provider == .whisper && !whisper.isReady {
      throw AppError.message("Download Whisper in Models first.")
    }
    if provider == .cohere && !cohere.isReady {
      throw AppError.message("Download Cohere Transcribe in Models first.")
    }
  }

  private func clearPendingAudio() {
    if let pendingAudio { try? FileManager.default.removeItem(at: pendingAudio) }
    pendingAudio = nil
    pendingDuration = 0
  }

  private func fail(_ error: Error) {
    phase = .idle
    if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled {
      errorMessage = error.localizedDescription
    }
  }

  private func persist() {
    do {
      // Preserve the original bytes if a newer schema or damaged file could not be decoded.
      if preserveUnreadableState {
        let recoveryURL = stateURL.deletingLastPathComponent()
          .appendingPathComponent("state-recovery-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: stateURL, to: recoveryURL)
        preserveUnreadableState = false
      }
      let data = try JSONEncoder().encode(saved)
      try data.write(to: stateURL, options: [.atomic, .completeFileProtection])
    } catch { errorMessage = "Changes could not be saved. \(error.localizedDescription)" }
  }
}

enum AppError: LocalizedError {
  case message(String)
  var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}
