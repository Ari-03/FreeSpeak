import AVFoundation
import Observation

@MainActor @Observable
final class AudioRecorder {
  private let worker = RecordingWorker()
  private var meterTask: Task<Void, Never>?
  private var interruptionObserver: NSObjectProtocol?
  private var recordingID: UUID?
  var level: Float = 0
  var duration: TimeInterval = 0
  var onInterruption: (() -> Void)?

  func start() async throws {
    guard recordingID == nil else { throw RecordingError.couldNotStart }
    try Task.checkCancellation()
    let allowed = await AVAudioApplication.requestRecordPermission()
    try Task.checkCancellation()
    guard allowed else { throw RecordingError.permissionDenied }
    try await worker.start()
    let recordingID = UUID()
    self.recordingID = recordingID
    duration = 0
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        value == AVAudioSession.InterruptionType.began.rawValue
      else { return }
      Task { @MainActor [weak self] in
        guard let self, self.recordingID == recordingID else { return }
        self.onInterruption?()
      }
    }
    meterTask = Task { [weak self] in
      do {
        while !Task.isCancelled {
          guard let self else { return }
          let reading = try await self.worker.readMeters()
          try Task.checkCancellation()
          self.level = reading.level
          self.duration = max(self.duration, reading.duration)
          if !reading.isRecording {
            self.onInterruption?()
            return
          }
          try await Task.sleep(for: .milliseconds(80))
        }
      } catch is CancellationError {
      } catch {
        self?.onInterruption?()
      }
    }
  }

  func stop() async throws -> URL? {
    resetObservation()
    let result = try await worker.stop()
    duration = max(duration, result.duration)
    return result.url
  }

  /// Discard is nonblocking even if the driver is stuck. The serial queue cleans up
  /// before allowing another recording to start when the driver eventually returns.
  func discard() {
    resetObservation()
    worker.discard()
  }

  private func resetObservation() {
    recordingID = nil
    meterTask?.cancel()
    meterTask = nil
    if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    interruptionObserver = nil
    level = 0
  }

  enum RecordingError: LocalizedError {
    case permissionDenied, couldNotStart
    var errorDescription: String? {
      switch self {
      case .permissionDenied:
        "Microphone access is off. Enable it for Steno in Settings to record."
      case .couldNotStart: "The microphone could not start. Check that another app isn't using it."
      }
    }
  }
}

/// Every AVAudioRecorder and AVAudioSession operation is confined to this queue.
/// Only sendable measurements and URLs cross back to the main actor.
nonisolated private final class RecordingWorker: @unchecked Sendable {
  private let queue = DispatchQueue(label: "ari.FreeSpeak.audio", qos: .userInitiated)
  private var recorder: AVAudioRecorder?

  struct Reading: Sendable {
    var level: Float
    var duration: TimeInterval
    var isRecording: Bool
  }
  struct Recording: Sendable {
    var url: URL?
    var duration: TimeInterval
  }

  func start() async throws {
    try await AudioOperation.run(on: queue) { [self] in
      guard recorder == nil else { throw AudioRecorder.RecordingError.couldNotStart }
      let session = AVAudioSession.sharedInstance()
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".m4a")
      do {
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true)
        let recording = try AVAudioRecorder(
          url: url,
          settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
          ])
        recorder = recording
        recording.isMeteringEnabled = true
        guard recording.record(forDuration: 300) else {
          throw AudioRecorder.RecordingError.couldNotStart
        }
      } catch {
        discardOnQueue()
        try? FileManager.default.removeItem(at: url)
        throw error
      }
    } discard: { [self] in
      discardOnQueue()
    }
  }

  func readMeters() async throws -> Reading {
    try await AudioOperation.run(on: queue) { [self] in
      guard let recorder else { return Reading(level: 0, duration: 0, isRecording: false) }
      recorder.updateMeters()
      return Reading(
        level: max(0, min(1, (recorder.averagePower(forChannel: 0) + 55) / 55)),
        duration: recorder.currentTime, isRecording: recorder.isRecording)
    }
  }

  func stop() async throws -> Recording {
    try await AudioOperation.run(on: queue, alwaysRun: true) { [self] in
      stopOnQueue()
    } discard: { recording in
      if let url = recording.url { try? FileManager.default.removeItem(at: url) }
    }
  }

  func discard() {
    queue.async { [self] in discardOnQueue() }
  }

  private func discardOnQueue() {
    if let url = stopOnQueue().url { try? FileManager.default.removeItem(at: url) }
  }

  private func stopOnQueue() -> Recording {
    let result = Recording(url: recorder?.url, duration: recorder?.currentTime ?? 0)
    recorder?.stop()
    recorder = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    return result
  }
}
