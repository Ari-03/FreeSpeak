import SwiftUI

struct ModelsView: View {
  @Environment(AppStore.self) private var store
  @State private var s1Ready = CleanupModelService.isDownloaded
  @State private var s1Downloading = false
  @State private var s1Task: Task<Void, Never>?
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Your voice. Your choice.")
            Text("Find your voice engine.").font(.system(.largeTitle, design: .serif)).tracking(-1)
            Text("Keep it on your iPhone, or bring your own API key.")
              .font(.subheadline).foregroundStyle(.secondary)
          }.padding(.vertical, 8)
          Eyebrow(text: "On this iPhone")
          Surface {
            VStack(alignment: .leading, spacing: 14) {
              modelHeading(
                "Apple Speech", subtitle: "Speech Analyzer", symbol: "apple.logo", badge: "SYSTEM")
              Text(
                "On-device dictation with language models managed by iOS. Language assets download on first use."
              )
              .font(.subheadline).foregroundStyle(.secondary)
              selectButton(.apple)
            }
          }
          downloadableModel(
            name: "Parakeet v3", subtitle: "NVIDIA · 25 languages · about 632 MB", symbol: "bird",
            badge: "LOCAL",
            description:
              "A fast speech model running through Core ML. A good place to start for everyday dictation.",
            ready: store.localModels.isReady, downloading: store.localModels.isDownloading,
            status: store.localModels.status,
            provider: .parakeet,
            download: {
              try await store.localModels.download()
              store.localModels.unload()
            },
            cancel: { store.localModels.cancelDownload() },
            remove: { try store.localModels.delete() }
          )
          downloadableModel(
            name: "Whisper Large v3", subtitle: "OpenAI · Multilingual · 3.09 GB",
            symbol: "waveform", badge: "LOCAL",
            description:
              "The full Large v3 model. Needs several gigabytes of storage and more memory than Parakeet. First preparation can take a while.",
            ready: store.whisper.isReady, downloading: store.whisper.isDownloading,
            status: store.whisper.status,
            provider: .whisper,
            download: { try await store.whisper.download() },
            cancel: { store.whisper.cancelDownload() }, remove: { try store.whisper.delete() }
          )
          downloadableModel(
            name: "Cohere Transcribe", subtitle: "Cohere · 14 languages · about 2.2 GB",
            symbol: "circle.hexagongrid", badge: "EXPERIMENTAL",
            description:
              "An optional local model for recordings up to five minutes, processed in short sections. iPhone speed and memory use still need device testing.",
            ready: store.cohere.isReady, downloading: store.cohere.isDownloading,
            status: store.cohere.status,
            provider: .cohere,
            download: {
              try await store.cohere.download()
              store.cohere.unload()
            },
            cancel: { store.cohere.cancelDownload() }, remove: { try store.cohere.delete() }
          )
          Eyebrow(text: "After you speak")
          Surface {
            VStack(alignment: .leading, spacing: 14) {
              modelHeading(
                "S1-mini", subtitle: "By Superwhisper · English · 484 MB",
                symbol: "text.badge.checkmark", badge: "LOCAL")
              Text(
                "Removes fillers and tidies dictation on your iPhone. Supports style and list formatting for short English transcripts. Custom prompts require cloud cleanup."
              )
              .font(.subheadline).foregroundStyle(.secondary)
              if s1Downloading {
                HStack {
                  ProgressView()
                  Text("Downloading and verifying…").font(.caption)
                  Spacer()
                  Button("Cancel") { s1Task?.cancel() }
                }
              } else if s1Ready {
                HStack {
                  Button(
                    store.saved.settings.cleanupProvider == .s1Mini
                      ? "Selected for cleanup" : "Use for cleanup", systemImage: "checkmark.circle"
                  ) { store.saved.settings.cleanupProvider = .s1Mini }.buttonStyle(.bordered)
                  Spacer()
                  Button("Remove", role: .destructive) {
                    Task {
                      do {
                        try await store.cleanupModel.remove()
                        s1Ready = false
                        if store.saved.settings.cleanupProvider == .s1Mini {
                          store.saved.settings.cleanupProvider = .none
                        }
                      } catch { failure = error.localizedDescription }
                    }
                  }.font(.caption)
                }
              } else {
                Button("Download · 484 MB", systemImage: "arrow.down.circle") {
                  s1Downloading = true
                  s1Task = Task {
                    defer {
                      s1Downloading = false
                      s1Ready = CleanupModelService.isDownloaded
                    }
                    do { try await store.cleanupModel.download() } catch {
                      if !Task.isCancelled { failure = error.localizedDescription }
                    }
                  }
                }.buttonStyle(.bordered)
                  .disabled(
                    store.localModels.isDownloading || store.whisper.isDownloading
                      || store.cohere.isDownloading)
              }
            }
          }
          Eyebrow(text: "Connected models")
          ForEach([SpeechProvider.openAI, .grok]) { provider in
            Surface {
              VStack(alignment: .leading, spacing: 14) {
                modelHeading(
                  provider.name, subtitle: provider.subtitle, symbol: "cloud", badge: "API KEY")
                Text(
                  "Audio is sent directly to \(provider.name). Add your own key in Settings; usage is billed by the provider."
                )
                .font(.subheadline).foregroundStyle(.secondary)
                selectButton(provider)
              }
            }
          }
          Text(
            "Local model downloads need an internet connection. Once prepared, audio transcription and S1-mini cleanup run on your iPhone. Download one model at a time to limit memory use."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
      }.background(SpeakStyle.paper)
        .navigationTitle("Models").navigationBarTitleDisplayMode(.inline)
        .disabled(store.phase != .idle)
        .alert(
          "Model needs attention",
          isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
          Button("OK") { failure = nil }
        } message: {
          Text(failure ?? "")
        }
    }
  }

  private func modelHeading(_ name: String, subtitle: String, symbol: String, badge: String)
    -> some View
  {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.title2).foregroundStyle(SpeakStyle.accent)
        .frame(width: 40, height: 42).background(
          SpeakStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 5) {
        Text(name).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Text(badge).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.4)
        .padding(6).background(.quaternary, in: Capsule())
    }
  }

  private func selectButton(_ provider: SpeechProvider) -> some View {
    Button(
      store.saved.settings.speechProvider == provider ? "Selected" : "Use model",
      systemImage: store.saved.settings.speechProvider == provider
        ? "checkmark.circle.fill" : "circle"
    ) {
      store.saved.settings.speechProvider = provider
    }.buttonStyle(.bordered)
  }

  private func downloadableModel(
    name: String, subtitle: String, symbol: String, badge: String, description: String,
    ready: Bool, downloading: Bool, status: String, provider: SpeechProvider,
    download: @escaping () async throws -> Void, cancel: @escaping () -> Void,
    remove: @escaping () throws -> Void
  ) -> some View {
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        modelHeading(name, subtitle: subtitle, symbol: symbol, badge: badge)
        Text(description).font(.subheadline).foregroundStyle(.secondary)
        Text(status).font(.caption).foregroundStyle(.secondary)
        if downloading {
          HStack {
            ProgressView()
            Spacer()
            Button("Cancel", action: cancel)
          }
        } else if ready {
          HStack {
            selectButton(provider)
            Spacer()
            Button("Remove", role: .destructive) {
              do {
                try remove()
                if store.saved.settings.speechProvider == provider {
                  store.saved.settings.speechProvider = .apple
                }
              } catch { failure = error.localizedDescription }
            }.font(.caption)
          }
        } else {
          Button("Download model", systemImage: "arrow.down.circle") {
            Task {
              do { try await download() } catch {
                if !(error is CancellationError) { failure = error.localizedDescription }
              }
            }
          }.buttonStyle(.bordered)
            .disabled(
              store.localModels.isDownloading || store.whisper.isDownloading
                || store.cohere.isDownloading || s1Downloading)
        }
      }
    }
  }
}
