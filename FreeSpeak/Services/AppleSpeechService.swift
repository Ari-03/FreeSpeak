import AVFoundation
import Foundation
import Speech

/// Transcribes a recording on device, downloading Apple's language assets on first use.
@MainActor
enum AppleSpeechService {
  enum TranscriptionError: LocalizedError {
    case simulatorUnsupported
    case deviceUnsupported
    case localeUnsupported(String)
    case noSpeech

    var errorDescription: String? {
      switch self {
      case .simulatorUnsupported:
        "Apple Speech needs a supported physical iPhone. Use a cloud provider in the simulator."
      case .deviceUnsupported:
        "Apple Speech is unavailable on this device. Choose another transcription model."
      case .localeUnsupported(let identifier):
        "Apple Speech does not support the selected language (\(identifier)). Choose another language or model."
      case .noSpeech:
        "No speech was detected in the recording."
      }
    }
  }

  static func transcribe(url: URL, locale: Locale) async throws -> String {
    #if targetEnvironment(simulator)
      throw TranscriptionError.simulatorUnsupported
    #else
      guard SpeechTranscriber.isAvailable else {
        throw TranscriptionError.deviceUnsupported
      }
      guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
      else {
        throw TranscriptionError.localeUnsupported(locale.identifier)
      }
      try Task.checkCancellation()

      // This preset delivers final passages, so concatenation cannot duplicate partial text.
      let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
      if let installation = try await AssetInventory.assetInstallationRequest(
        supporting: [transcriber]
      ) {
        try await installation.downloadAndInstall()
      }
      try Task.checkCancellation()

      let audioFile = try AVAudioFile(forReading: url)
      let analyzer = SpeechAnalyzer(modules: [transcriber])

      return try await withTaskCancellationHandler {
        let results = Task {
          var transcript = ""
          for try await result in transcriber.results {
            try Task.checkCancellation()
            if result.isFinal {
              transcript += String(result.text.characters)
            }
          }
          return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        do {
          let lastSample = try await analyzer.analyzeSequence(from: audioFile)
          try Task.checkCancellation()
          if let lastSample {
            try await analyzer.finalizeAndFinish(through: lastSample)
          } else {
            await analyzer.cancelAndFinishNow()
          }
          let transcript = try await results.value
          try Task.checkCancellation()
          guard !transcript.isEmpty else {
            throw TranscriptionError.noSpeech
          }
          return transcript
        } catch {
          results.cancel()
          await analyzer.cancelAndFinishNow()
          // Wait for the consumer to exit before releasing the analysis session.
          _ = await results.result
          throw error
        }
      } onCancel: {
        Task { await analyzer.cancelAndFinishNow() }
      }
    #endif
  }
}
