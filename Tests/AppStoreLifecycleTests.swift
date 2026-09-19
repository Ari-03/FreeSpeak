import Foundation

@main struct LifecycleCheck {
  @MainActor static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "freespeak-store-check-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let audio = directory.appending(path: "test.m4a")
    try Data("fake audio".utf8).write(to: audio)
    func store(_ name: String) -> AppStore { AppStore(directory: directory.appending(path: name)) }
    func settled(_ store: AppStore, phase: AppStore.Phase = .idle) async throws {
      for _ in 0..<1000 {
        if store.phase == phase { return }
        try await Task.sleep(for: .milliseconds(2))
      }
      fatalError("Store did not reach expected phase \(phase)")
    }
    let retry = store("retry")
    retry.importAudio(audio)
    retry.processPendingAudio()
    try await settled(retry)
    precondition(AppleSpeechService.calls == 1, "duplicate Retry spawned overlapping work")
    precondition(retry.latestTranscript?.text == "original speech")

    let microphone = store("microphone")
    microphone.latestTranscript = retry.latestTranscript
    microphone.recorder.shouldFailToStart = true
    microphone.startRecording()
    try await settled(microphone)
    precondition(
      microphone.latestTranscript?.text == "original speech",
      "microphone failure lost unsaved previous text")

    let starting = store("starting")
    starting.recorder.startDelay = .seconds(60)
    starting.startRecording()
    starting.cancel()
    try await settled(starting)
    precondition(starting.errorMessage == nil, "cancelling startup surfaced an error")

    let stopping = store("stopping")
    stopping.startRecording()
    try await settled(stopping, phase: .recording)
    stopping.finishRecording()
    stopping.finishRecording()
    try await Task.sleep(for: .milliseconds(5))
    stopping.cancel()
    try await settled(stopping)
    precondition(
      stopping.recorder.stopCalls == 1, "duplicate finish started overlapping audio stops")
    precondition(stopping.errorMessage == nil, "cancelling shutdown surfaced an error")

    let cancelled = store("cancel")
    cancelled.importAudio(audio)
    cancelled.cancel()
    try await settled(cancelled)
    precondition(cancelled.hasPendingAudio)
    precondition(cancelled.latestTranscript == nil)
    cancelled.processPendingAudio()
    try await settled(cancelled)
    precondition(!cancelled.hasPendingAudio)

    let captured = store("captured")
    captured.saved.settings.speechProvider = .openAI
    captured.importAudio(audio)
    captured.saved.settings.speechProvider = .grok
    try await settled(captured)
    precondition(
      captured.latestTranscript?.providerName == "OpenAI",
      "validated mutable settings instead of captured request")

    let cleanup = store("cleanup")
    KeyboardInbox.shouldFail = true
    cleanup.saved.settings.cleanupProvider = .openAI
    cleanup.importAudio(audio)
    try await settled(cleanup, phase: .cleaning)
    cleanup.cancel()
    try await settled(cleanup)
    precondition(
      cleanup.latestTranscript?.text == "original speech", "cleanup cancellation lost ASR result")
    precondition(!cleanup.hasPendingAudio)
    precondition(cleanup.notice?.contains("Cleanup cancelled") == true)
    precondition(cleanup.notice?.contains("Keyboard sharing") == true)
    KeyboardInbox.shouldFail = false

    let empty = store("empty")
    empty.saved.settings.cleanupProvider = .s1Mini
    await empty.cleanupModel.setOutput("")
    let priorClears = KeyboardInbox.clearCount
    empty.importAudio(audio)
    try await settled(empty)
    precondition(empty.latestTranscript?.text == "")
    precondition(empty.latestTranscript?.original == "original speech")
    precondition(
      KeyboardInbox.clearCount == priorClears + 1, "empty cleanup left an older keyboard transcript"
    )

    let history = store("history")
    history.importAudio(audio)
    history.deleteHistory()
    try await settled(history)
    precondition(history.saved.transcripts.isEmpty, "in-flight result repopulated deleted history")

    let disabled = store("disabled")
    disabled.importAudio(audio)
    disabled.saved.settings.saveHistory = false
    try await settled(disabled)
    precondition(disabled.saved.transcripts.isEmpty, "history was saved after retention turned off")

    let corruptDirectory = directory.appending(path: "corrupt")
    try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
    let original = Data("unrecognized future schema".utf8)
    try original.write(to: corruptDirectory.appending(path: "state.json"))
    let recovered = AppStore(directory: corruptDirectory)
    recovered.saved.settings.saveHistory = false
    let backups = try FileManager.default.contentsOfDirectory(
      at: corruptDirectory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("state-recovery-") }
    precondition(backups.count == 1)
    let preserved = try Data(contentsOf: backups[0])
    precondition(preserved == original, "unreadable saved data was overwritten")
    recovered.deleteHistory()
    precondition(!FileManager.default.fileExists(atPath: backups[0].path))

    let downloading = store("downloading")
    downloading.cohere.isDownloading = true
    downloading.importAudio(audio)
    precondition(downloading.phase == .idle && downloading.errorMessage != nil)
    print(
      "PASS: duplicate retry, cancellation, captured settings, cleanup preservation, retention changes, recovery preservation/deletion, model-download exclusion"
    )
  }
}
