import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTab = 0
  @State private var launchRequest = DictationLaunchRequest.shared
  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Dictate", systemImage: "waveform", value: 0) { DictateView() }
      Tab("Modes", systemImage: "square.grid.2x2", value: 1) { ModesView() }
      Tab("Models", systemImage: "cpu", value: 2) { ModelsView() }
      Tab("Settings", systemImage: "slider.horizontal.3", value: 3) { SettingsView() }
    }
    .tint(SpeakStyle.accent)
    .onAppear(perform: consumeDictationRequest)
    .onChange(of: launchRequest.pending) { consumeDictationRequest() }
    .onChange(of: scenePhase) { consumeDictationRequest() }
  }

  private func consumeDictationRequest() {
    guard launchRequest.pending, scenePhase == .active else { return }
    launchRequest.pending = false
    selectedTab = 0
    if store.phase == .idle { store.startRecording() }
  }
}

struct DictateView: View {
  @Environment(AppStore.self) private var store
  @State private var importing = false
  @State private var showingHistory = false
  @State private var selectedTranscript: Transcript?
  @State private var copied = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          recordingCard
          modePicker
          if let message = store.errorMessage {
            Surface {
              VStack(alignment: .leading, spacing: 12) {
                Label("Let's try that again", systemImage: "exclamationmark.circle").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                if store.hasPendingAudio && store.phase == .idle {
                  Button("Retry saved recording", systemImage: "arrow.clockwise") {
                    store.processPendingAudio()
                  }
                }
              }
            }
          }
          if let notice = store.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
          if let transcript = store.latestTranscript {
            Surface {
              VStack(alignment: .leading, spacing: 16) {
                HStack {
                  Eyebrow(text: "Your words")
                  Spacer()
                  Text("\(transcript.wordCount) words").font(.caption).foregroundStyle(.secondary)
                }
                if transcript.text.isEmpty {
                  Text("There was nothing to keep after cleanup. Your original is still available.")
                    .font(.body).foregroundStyle(.secondary)
                } else {
                  Text(transcript.text).font(.body).textSelection(.enabled)
                }
                HStack {
                  Button(
                    copied ? "Copied" : "Copy text",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                  ) {
                    UIPasteboard.general.string = transcript.text
                    copied = true
                  }.buttonStyle(.borderedProminent).disabled(transcript.text.isEmpty)
                  ShareLink(item: transcript.text) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered).accessibilityLabel("Share transcript")
                  Spacer()
                  Button("Original") { selectedTranscript = transcript }.font(.footnote)
                }
              }
            }
          }
          recentSection
          HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text(
              "\(store.saved.settings.speechProvider.isLocal ? "Audio stays on this iPhone" : "Audio is sent to " + store.saved.settings.speechProvider.name). \(store.saved.settings.cleanupProvider == .none ? "No cloud cleanup." : "Text cleanup: " + store.saved.settings.cleanupProvider.name + ".")"
            )
          }
          .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
      }
      .background(SpeakStyle.paper)
      .toolbar(.hidden, for: .navigationBar)
      .sheet(isPresented: $showingHistory) { HistoryView() }
      .sheet(item: $selectedTranscript) { TranscriptDetailView(transcript: $0) }
      .onChange(of: store.latestTranscript?.id) { copied = false }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
        switch result {
        case .success(let url): store.importAudio(url)
        case .failure(let error): store.errorMessage = error.localizedDescription
        }
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "waveform").foregroundStyle(SpeakStyle.accent)
          Eyebrow(text: "Steno")
        }
        Text("A little less typing.").font(.system(.largeTitle, design: .serif)).tracking(-1.2)
      }
      Spacer(minLength: 8)
      Button {
        showingHistory = true
      } label: {
        Image(systemName: "clock.arrow.circlepath").font(.title3)
          .frame(width: 44, height: 44).background(SpeakStyle.card, in: Circle())
      }.accessibilityLabel("Transcript history").foregroundStyle(.primary)
    }.padding(.top, 12)
  }

  private var recordingCard: some View {
    Surface {
      VStack(spacing: 18) {
        HStack {
          Label(
            store.saved.settings.speechProvider.isLocal ? "ON DEVICE" : "CLOUD",
            systemImage: store.saved.settings.speechProvider.isLocal ? "iphone" : "cloud"
          )
          .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
          Spacer()
          Text(store.saved.settings.speechProvider.name).font(.caption).foregroundStyle(.secondary)
        }
        WaveformView(level: store.recorder.level, active: store.phase == .recording)
        VStack(spacing: 8) {
          Text(store.phase.label).font(.system(.title2, design: .serif))
          if store.phase == .recording {
            Text(Duration.seconds(store.recorder.duration).formatted(.time(pattern: .minuteSecond)))
              .font(.system(.body, design: .monospaced)).foregroundStyle(SpeakStyle.accent)
          } else {
            Text(
              store.phase.isBusy
                ? "You can cancel at any time." : "Speak naturally. Make room for your thoughts."
            )
            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
          }
        }
        Button {
          if store.phase == .recording { store.finishRecording() } else { store.startRecording() }
        } label: {
          HStack(spacing: 10) {
            if store.phase.isBusy {
              ProgressView().tint(.white)
            } else {
              Image(systemName: store.phase == .recording ? "stop.fill" : "mic.fill")
            }
            Text(
              store.phase == .recording
                ? "Finish dictation" : store.phase.isBusy ? "Working…" : "Start dictating"
            ).fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity).padding(.vertical, 17)
          .background(SpeakStyle.accent, in: Capsule()).foregroundStyle(.white)
        }
        .disabled(store.phase.isBusy)
        .sensoryFeedback(.impact(weight: .medium), trigger: store.phase == .recording)
        if store.phase != .idle {
          Button("Cancel", role: .cancel) { store.cancel() }.font(.subheadline)
        } else {
          Button {
            importing = true
          } label: {
            Label("Or import audio", systemImage: "arrow.up.doc").font(.subheadline)
          }.foregroundStyle(.secondary)
        }
      }
    }
  }

  private var modePicker: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack {
        Eyebrow(text: "Make it yours")
        Spacer()
        Text("\(store.selectedMode.name) mode").font(.caption).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(store.saved.modes) { mode in
            Button {
              store.saved.selectedModeID = mode.id
            } label: {
              Label(mode.name, systemImage: mode.symbol).font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(
                  store.selectedMode.id == mode.id
                    ? SpeakStyle.accent.opacity(0.12) : SpeakStyle.card, in: Capsule()
                )
                .foregroundStyle(store.selectedMode.id == mode.id ? SpeakStyle.accent : .primary)
                .overlay(
                  Capsule().strokeBorder(
                    store.selectedMode.id == mode.id ? SpeakStyle.accent.opacity(0.35) : .clear))
            }.accessibilityAddTraits(store.selectedMode.id == mode.id ? .isSelected : [])
          }
        }
      }.disabled(store.phase != .idle)
      if store.saved.settings.cleanupProvider == .none && !store.selectedMode.instructions.isEmpty {
        Text(
          "Enable a cleanup model in Settings to apply this mode. Original transcription works without one."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Eyebrow(text: "Recent words")
        Spacer()
        if !store.saved.transcripts.isEmpty {
          Button("View all") { showingHistory = true }.font(.caption)
        }
      }
      if store.saved.transcripts.isEmpty {
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: "text.alignleft").font(.title2).foregroundStyle(.tertiary)
          VStack(alignment: .leading, spacing: 5) {
            Text("Your next thought starts here.").font(.subheadline.weight(.medium))
            Text("Dictations you choose to keep will appear here.").font(.caption).foregroundStyle(
              .secondary)
          }
        }.padding(.vertical, 10)
      } else {
        ForEach(store.saved.transcripts.prefix(3)) { transcript in
          Button {
            selectedTranscript = transcript
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "text.quote").foregroundStyle(SpeakStyle.accent)
                .frame(width: 38, height: 42).background(
                  SpeakStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
              VStack(alignment: .leading, spacing: 5) {
                Text(transcript.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                Text(
                  "\(transcript.modeName) · \(transcript.date.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption2).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(14).background(SpeakStyle.card, in: RoundedRectangle(cornerRadius: 18))
          }.buttonStyle(.plain)
        }
      }
    }
  }
}

struct HistoryView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  private var transcripts: [Transcript] {
    store.saved.transcripts.filter {
      query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    NavigationStack {
      List {
        ForEach(transcripts) { transcript in
          NavigationLink {
            TranscriptDetailView(transcript: transcript)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(transcript.title).lineLimit(2)
              Text(transcript.date, format: .dateTime.month().day().hour().minute()).font(.caption)
                .foregroundStyle(.secondary)
            }.padding(.vertical, 5)
          }
        }.onDelete { offsets in
          let ids = Set(offsets.map { transcripts[$0].id })
          store.saved.transcripts.removeAll { ids.contains($0.id) }
        }
      }
      .overlay {
        if transcripts.isEmpty {
          ContentUnavailableView(
            "No transcripts", systemImage: "text.alignleft",
            description: Text(
              query.isEmpty ? "Your saved dictations will appear here." : "Try a different search.")
          )
        }
      }
      .searchable(text: $query, prompt: "Find your words")
      .navigationTitle("History")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

struct TranscriptDetailView: View {
  let transcript: Transcript
  @State private var original = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Text(transcript.date, format: .dateTime.month(.wide).day().hour().minute()).font(
            .subheadline
          ).foregroundStyle(.secondary)
          Picker("Version", selection: $original) {
            Text("Result").tag(false)
            Text("Original").tag(true)
          }.pickerStyle(.segmented)
          Text(original ? transcript.original : transcript.text).font(.title3).textSelection(
            .enabled)
          Label("\(transcript.providerName) · \(transcript.modeName)", systemImage: "waveform")
            .font(.caption).foregroundStyle(.secondary)
          ShareLink(item: original ? transcript.original : transcript.text) {
            Label("Share text", systemImage: "square.and.arrow.up")
          }.buttonStyle(.borderedProminent)
        }.padding(24)
      }.navigationTitle("Transcript").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}
