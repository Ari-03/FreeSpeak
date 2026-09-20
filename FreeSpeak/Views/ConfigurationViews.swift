import SwiftUI

struct ModesView: View {
  @Environment(AppStore.self) private var store
  @State private var editingMode: DictationMode?

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      Form {
        Section {
          Picker(
            "Current mode",
            selection: Binding(
              get: { store.selectedMode.id },
              set: { store.saved.selectedModeID = $0 }
            )
          ) {
            ForEach(store.saved.modes) { mode in
              Label(mode.name, systemImage: mode.symbol).tag(mode.id)
            }
          }
        } footer: {
          Text(
            "Choose how your words are written. Cloud models follow your instructions. S1-mini uses each mode's local style settings."
          )
        }

        Section {
          ForEach(store.saved.modes) { mode in
            Button {
              editingMode = mode
            } label: {
              HStack(spacing: 14) {
                Image(systemName: mode.symbol)
                  .font(.title3)
                  .foregroundStyle(.tint)
                  .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                  Text(mode.name).font(.headline).foregroundStyle(.primary)
                  Text(mode.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if mode.id == store.selectedMode.id {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Current mode")
                }
                Image(systemName: "chevron.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tertiary)
              }
              .padding(.vertical, 5)
            }
          }
          .onDelete(perform: deleteModes)
          .deleteDisabled(store.saved.modes.count == 1)
        } header: {
          Text("Your modes")
        } footer: {
          Text(
            "Leave a mode's instructions empty to keep the original transcript. You can always compare the original with the cleaned result."
          )
        }

        Button {
          editingMode = DictationMode(name: "", symbol: "sparkles", detail: "", instructions: "")
        } label: {
          Label("Create a mode", systemImage: "plus")
        }
      }
      .modifier(ConfigurationBackground())
      .navigationTitle("Modes")
      .sheet(item: $editingMode) { mode in
        ModeEditor(mode: mode) { updated in
          if let index = store.saved.modes.firstIndex(where: { $0.id == updated.id }) {
            store.saved.modes[index] = updated
          } else {
            store.saved.modes.append(updated)
          }
        }
      }
    }
  }

  private func deleteModes(at offsets: IndexSet) {
    guard store.saved.modes.count > offsets.count else { return }
    store.saved.modes.remove(atOffsets: offsets)
    if !store.saved.modes.contains(where: { $0.id == store.saved.selectedModeID }) {
      store.saved.selectedModeID = store.saved.modes.first?.id
    }
  }
}

private struct ModeEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var mode: DictationMode
  let onSave: (DictationMode) -> Void

  private let symbols = [
    "waveform", "bubble.left", "envelope", "list.bullet", "quote.opening", "sparkles",
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section("Make it yours") {
          TextField("Mode name", text: $mode.name)
            .accessibilityLabel("Mode name")
          TextField("A short description", text: $mode.detail)
            .accessibilityLabel("Mode description")
          Picker("Icon", selection: $mode.symbol) {
            ForEach(symbols, id: \.self) { symbol in
              Image(systemName: symbol).tag(symbol)
            }
          }
        }
        Section {
          TextField(
            "How should your transcript be cleaned up?", text: $mode.instructions, axis: .vertical
          )
          .lineLimit(6...12)
          .accessibilityLabel("Cleanup instructions")
        } header: {
          Text("Cleanup instructions")
        } footer: {
          Text(
            "For example: Remove filler words and add punctuation. Keep my wording and language. Never add facts. Leave this empty to skip cleanup."
          )
        }
        Section {
          Picker("Style", selection: $mode.localStyle) {
            Text("Casual").tag("casual")
            Text("Semi-casual").tag("semi-casual")
            Text("Semi-formal").tag("semi-formal")
            Text("Formal").tag("formal")
          }
          Picker("Structure", selection: $mode.localStructure) {
            Text("Paragraphs").tag("prose")
            Text("Lists").tag("lists")
          }
          Picker("Context", selection: $mode.localContext) {
            Text("General").tag("general")
            Text("Email").tag("email")
          }
        } header: {
          Text("S1-mini settings")
        } footer: {
          Text(
            "S1-mini uses these controls instead of custom instructions. Leave cleanup instructions empty to bypass cleanup entirely."
          )
        }
      }
      .modifier(ConfigurationBackground())
      .navigationTitle("Edit mode")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            mode.name = mode.name.trimmingCharacters(in: .whitespacesAndNewlines)
            mode.detail = mode.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            mode.instructions = mode.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave(mode)
            dismiss()
          }
          .disabled(mode.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

struct VocabularyView: View {
  @Environment(AppStore.self) private var store
  @State private var search = ""
  @State private var word = ""
  @State private var hint = ""
  @State private var showingAdd = false

  private var filteredEntries: [VocabularyEntry] {
    store.saved.vocabulary.filter {
      search.isEmpty || $0.word.localizedCaseInsensitiveContains(search)
        || $0.hint.localizedCaseInsensitiveContains(search)
    }
  }

  private var canAdd: Bool {
    let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty
      && !store.saved.vocabulary.contains {
        $0.word.caseInsensitiveCompare(trimmed) == .orderedSame
      }
  }

  var body: some View {
    List {
      Section {
        Text("Names, products, and words you use often.")
          .font(.title3.weight(.medium))
          .padding(.vertical, 4)
        Text(
          "Terms help supported cloud transcription and cleanup models. Apple Speech does not use this list yet. Hints provide context, not guaranteed replacements."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }

      Section("Your vocabulary") {
        if store.saved.vocabulary.isEmpty {
          ContentUnavailableView(
            "Your words belong here", systemImage: "text.book.closed",
            description: Text("Add a name or term that dictation often misses."))
        } else if filteredEntries.isEmpty {
          Text("No matching words").foregroundStyle(.secondary)
        }
        ForEach(filteredEntries) { entry in
          VStack(alignment: .leading, spacing: 5) {
            Text(entry.word).font(.headline)
            if !entry.hint.isEmpty {
              Text(entry.hint).font(.subheadline).foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 3)
        }
        .onDelete { offsets in
          let identifiers = Set(offsets.map { filteredEntries[$0].id })
          store.saved.vocabulary.removeAll { identifiers.contains($0.id) }
        }
      }
    }
    .modifier(ConfigurationBackground())
    .navigationTitle("Vocabulary")
    .searchable(text: $search, prompt: "Find a word")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add word", systemImage: "plus") { showingAdd = true }
      }
    }
    .sheet(isPresented: $showingAdd) {
      NavigationStack {
        Form {
          Section {
            TextField("Word or phrase", text: $word)
              .autocorrectionDisabled()
            TextField("Context or pronunciation, optional", text: $hint, axis: .vertical)
              .lineLimit(2...4)
          } footer: {
            Text(
              "Use the spelling you want to see, such as Steno. A hint can explain that it is the name of your app."
            )
          }
        }
        .modifier(ConfigurationBackground())
        .navigationTitle("Add a word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { showingAdd = false }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Add") {
              store.saved.vocabulary.append(
                VocabularyEntry(
                  word: word.trimmingCharacters(in: .whitespacesAndNewlines),
                  hint: hint.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
              word = ""
              hint = ""
              showingAdd = false
            }
            .disabled(!canAdd)
          }
        }
      }
    }
  }
}

struct SettingsView: View {
  @Environment(AppStore.self) private var store
  @State private var showingDeleteConfirmation = false

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      Form {
        Section {
          Picker("Speech to text", selection: $store.saved.settings.speechProvider) {
            ForEach(SpeechProvider.allCases) { provider in
              Text(provider.name).tag(provider)
            }
          }
          Picker("Text cleanup", selection: $store.saved.settings.cleanupProvider) {
            ForEach(CleanupProvider.allCases) { provider in
              Text(provider.name).tag(provider)
            }
          }
        } header: {
          Text("Your pipeline")
        } footer: {
          Text(pipelineExplanation)
        }

        Section {
          TextField("Language identifier", text: $store.saved.settings.localeIdentifier)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Spoken language")
        } footer: {
          Text(
            "Use a locale such as en-US, en-GB, es-ES, fr-FR, or ja-JP. Apple Speech checks language availability on this device before transcription."
          )
        }

        Section("Your vocabulary") {
          NavigationLink {
            VocabularyView()
          } label: {
            Label("Names & terms", systemImage: "text.book.closed")
          }
        }

        Section("Steno keyboard") {
          Text(
            "For a quicker start, add Steno's Start dictation action in Shortcuts or assign it to your Action Button. It opens Steno and starts the microphone."
          )
          .font(.footnote).foregroundStyle(.secondary)
          Text(
            "Add Steno in iPhone Settings → General → Keyboard → Keyboards → Add New Keyboard.")
          Text(
            "Record in Steno, return to your text field, and switch to the Steno keyboard to insert your latest transcript. Full Access is not required."
          )
          .font(.footnote).foregroundStyle(.secondary)
          Text(
            "The latest transcript is shared with the keyboard even when history is off. Delete all transcripts to clear it."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }

        Section {
          ProviderKeyRow(provider: "OpenAI", account: "openAI")
          ProviderKeyRow(provider: "Grok · xAI", account: "grok")
        } header: {
          Text("API keys")
        } footer: {
          Text(
            "Keys are stored in this device's Keychain. Your selected provider bills API usage to your account. Grok is xAI's service; Groq is a different provider."
          )
        }

        Section {
          LabeledContent("OpenAI") {
            TextField("Model name", text: $store.saved.settings.openAICleanupModel)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Grok") {
            TextField("Model name", text: $store.saved.settings.grokCleanupModel)
              .multilineTextAlignment(.trailing)
          }
        } header: {
          Text("Cleanup models")
        } footer: {
          Text(
            "Use a text model available to your API account. A mode with empty instructions skips cleanup, regardless of this setting."
          )
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

        Section {
          Toggle("Save transcript history", isOn: $store.saved.settings.saveHistory)
          Button("Delete all transcripts", role: .destructive) {
            showingDeleteConfirmation = true
          }
          .disabled(store.saved.transcripts.isEmpty && store.latestTranscript == nil)
        } header: {
          Text("History & privacy")
        } footer: {
          Text(
            "History stays on this device. Turning history off applies to future recordings and keeps existing transcripts. Temporary audio is removed after a successful transcription; failed recordings remain available to retry during this session."
          )
        }
      }
      .modifier(ConfigurationBackground())
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          NavigationLink {
            AttributionsView()
          } label: {
            Image(systemName: "info.circle")
          }.accessibilityLabel("Acknowledgments")
        }
      }
      .confirmationDialog(
        "Delete all transcripts?", isPresented: $showingDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete all transcripts", role: .destructive) { store.deleteHistory() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This removes your saved history and the current result from Steno. It cannot be undone."
        )
      }
    }
  }

  private var pipelineExplanation: String {
    let speech = store.saved.settings.speechProvider
    let cleanup = store.saved.settings.cleanupProvider
    var explanation =
      speech.isLocal
      ? "\(speech.name) processes audio on this iPhone. Model assets may need a download."
      : "Recording with \(speech.name) sends your audio and vocabulary to \(speech.name) for transcription."
    if cleanup.isCloud {
      explanation +=
        " Modes with cleanup send transcript text, instructions, and vocabulary to \(cleanup.name)."
    } else if cleanup == .s1Mini {
      explanation +=
        " S1-mini by Superwhisper cleans English text on this iPhone using your mode's style settings."
    } else {
      explanation += " Cleanup is off, so you receive the original transcript."
    }
    return explanation
  }
}

private struct ProviderKeyRow: View {
  let provider: String
  let account: String
  @State private var draft = ""
  @State private var savedSuffix = ""
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(provider).font(.headline)
        Spacer()
        if !savedSuffix.isEmpty {
          Label("Saved · \(savedSuffix)", systemImage: "checkmark.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      SecureField(savedSuffix.isEmpty ? "API key" : "Replace API key", text: $draft)
        .textContentType(.password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      HStack {
        Button("Save key") { save(draft) }
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if !savedSuffix.isEmpty {
          Spacer()
          Button("Remove", role: .destructive) { save("") }
        }
      }
      .buttonStyle(.borderless)
      if let errorMessage {
        Text(errorMessage).font(.caption).foregroundStyle(.red)
      }
    }
    .padding(.vertical, 5)
    .onAppear { refreshSuffix() }
  }

  private func save(_ value: String) {
    do {
      try KeychainStore.save(value, account: account)
      draft = ""
      errorMessage = nil
      refreshSuffix()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refreshSuffix() {
    let key = KeychainStore.read(account)
    savedSuffix = key.isEmpty ? "" : "••••" + key.suffix(4)
  }
}

private struct ConfigurationBackground: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(
        colorScheme == .dark
          ? Color(uiColor: .systemGroupedBackground) : Color(red: 0.97, green: 0.955, blue: 0.93))
  }
}
