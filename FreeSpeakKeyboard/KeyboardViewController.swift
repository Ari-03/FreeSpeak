import Observation
import SwiftUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
  private let state = KeyboardState()

  override func viewDidLoad() {
    super.viewDidLoad()
    let content = KeyboardView(
      state: state,
      type: { [weak self] in self?.textDocumentProxy.insertText($0) },
      delete: { [weak self] in self?.textDocumentProxy.deleteBackward() },
      nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
      insertTranscript: { [weak self] in self?.insertTranscript() }
    )
    let host = UIHostingController(rootView: content)
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    host.view.backgroundColor = .clear
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    host.didMove(toParent: self)
    let height = view.heightAnchor.constraint(equalToConstant: 330)
    height.priority = .defaultHigh
    height.isActive = true
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    state.refresh()
  }

  private func insertTranscript() {
    guard let transcript = state.pending else { return }
    do {
      // Persist before the proxy call so a recreated extension cannot repeat an insertion.
      // iOS offers no transaction or acknowledgement spanning storage and the host field.
      guard try state.recordInsertion(transcript.id) else {
        state.refresh()
        return
      }
      textDocumentProxy.insertText(transcript.text)
      state.pending = nil
      state.message = "Transcript inserted"
      UIAccessibility.post(notification: .announcement, argument: "Transcript inserted")
    } catch {
      state.message = "Couldn't save insertion status. Your transcript is still in Steno."
    }
  }
}

@MainActor @Observable
private final class KeyboardState {
  var pending: KeyboardTranscript?
  var message = "Record in Steno, then return here to insert."
  var uppercase = false
  var symbols = false
  var alternateSymbols = false
  private let inbox = KeyboardInbox()
  private var insertedIDs: [UUID] = []
  private var receiptError = false
  private let receiptURL = URL.applicationSupportDirectory.appendingPathComponent(
    "keyboard-insertions.json")

  init() {
    do {
      insertedIDs = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: receiptURL))
    } catch CocoaError.fileReadNoSuchFile {
      insertedIDs = []
    } catch {
      receiptError = true
    }
  }

  func refresh() {
    guard !receiptError else {
      pending = nil
      message = "Insertion history couldn't be read. Copy your transcript from Steno."
      return
    }
    do {
      guard let latest = try inbox.latest() else {
        pending = nil
        message = "Record in Steno, then return here to insert."
        return
      }
      if insertedIDs.contains(latest.id) {
        pending = nil
        message = "Transcript inserted. Record again in Steno."
      } else {
        pending = latest
        message = "Ready to insert"
      }
    } catch {
      pending = nil
      message = "Can't read your transcript. Open Steno and try again."
    }
  }

  func recordInsertion(_ id: UUID) throws -> Bool {
    // Another controller in this extension may have inserted while this one was hidden.
    do {
      insertedIDs = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: receiptURL))
    } catch CocoaError.fileReadNoSuchFile {
      insertedIDs = []
    }
    guard !insertedIDs.contains(id) else { return false }
    let updated = Array((insertedIDs + [id]).suffix(128))
    try FileManager.default.createDirectory(
      at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(updated).write(
      to: receiptURL, options: [.atomic, .completeFileProtection])
    insertedIDs = updated
    return true
  }
}

private struct KeyboardView: View {
  @Bindable var state: KeyboardState
  let type: (String) -> Void
  let delete: () -> Void
  let nextKeyboard: () -> Void
  let insertTranscript: () -> Void

  private let accent = Color(red: 0.83, green: 0.29, blue: 0.14)
  private var rows: [[String]] {
    let characters: [String]
    if state.symbols {
      characters =
        state.alternateSymbols
        ? ["[]{}^+=_\\|", "~`<>€£¥•", "!?.,:;\""]
        : ["1234567890", "@#$%&*()-", "!?.,'\"/"]
    } else {
      characters = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    }
    return characters.map { $0.map(String.init) }
  }

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "waveform").foregroundStyle(accent)
        VStack(alignment: .leading, spacing: 3) {
          Text("Steno").font(.caption.weight(.semibold))
          Text(state.pending?.text ?? state.message)
            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        Spacer(minLength: 0)
        Button(action: state.refresh) {
          Image(systemName: "arrow.clockwise").frame(width: 32, height: 44)
        }
        .accessibilityLabel("Refresh transcript")
        Button(action: insertTranscript) {
          Text("Insert").font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).frame(height: 44)
            .background(state.pending == nil ? Color.secondary.opacity(0.15) : accent)
            .foregroundStyle(state.pending == nil ? Color.secondary : .white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(state.pending == nil)
        .accessibilityLabel("Insert latest transcript")
      }
      .frame(height: 66)

      ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
        HStack(spacing: 5) {
          if index == 2 {
            key(
              state.symbols ? (state.alternateSymbols ? "123" : "#+=") : "⇧",
              accessibility: state.symbols ? "More symbols" : "Shift"
            ) {
              if state.symbols { state.alternateSymbols.toggle() } else { state.uppercase.toggle() }
            }
            .accessibilityValue(state.uppercase ? "On" : "Off")
          }
          ForEach(row, id: \.self) { character in
            let displayed = state.uppercase && !state.symbols ? character.uppercased() : character
            key(displayed) {
              type(displayed)
              state.uppercase = false
            }
          }
          if index == 2 {
            key("⌫", accessibility: "Delete", action: delete)
          }
        }
        .padding(.horizontal, index == 1 ? 12 : 0)
      }
      HStack(spacing: 6) {
        key(
          state.symbols ? "ABC" : "123",
          accessibility: state.symbols ? "Letters" : "Numbers and symbols"
        ) {
          state.symbols.toggle()
        }
        .frame(maxWidth: 50)
        Button(action: nextKeyboard) {
          Image(systemName: "globe").font(.system(size: 20))
            .frame(width: 36, height: 44)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityLabel("Next keyboard")
        key(",") { type(",") }.frame(maxWidth: 32)
        key("space", accessibility: "Space") { type(" ") }
        key(".") { type(".") }.frame(maxWidth: 32)
        key("return", accessibility: "Return") { type("\n") }.frame(maxWidth: 64)
      }
    }
    .padding(.horizontal, 7).padding(.top, 4).padding(.bottom, 8)
    .background(Color(uiColor: .secondarySystemBackground))
    .buttonStyle(.plain)
    .task {
      while !Task.isCancelled {
        state.refresh()
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
      }
    }
  }

  private func key(_ title: String, accessibility: String? = nil, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(title).font(title.count > 1 ? .system(size: 13) : .system(size: 20))
        .frame(maxWidth: .infinity).frame(height: 44)
        .foregroundStyle(.primary)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
    .accessibilityLabel(accessibility ?? title)
  }
}
