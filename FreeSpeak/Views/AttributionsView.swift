import SwiftUI

struct AttributionsView: View {
  var body: some View {
    List {
      Section("Speech models") {
        Link(
          "Parakeet TDT v3 · NVIDIA · CC BY 4.0",
          destination: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!)
        Text(
          "Parakeet runs with FluidInference's converted Core ML weights and corrected INT8 encoder."
        )
        .font(.caption).foregroundStyle(.secondary)
        Link(
          "Whisper Large v3 · OpenAI · MIT",
          destination: URL(string: "https://huggingface.co/openai/whisper-large-v3")!)
        Link(
          "Cohere Transcribe · Cohere · Apache 2.0",
          destination: URL(string: "https://huggingface.co/CohereLabs/cohere-transcribe-03-2026")!)
      }
      Section("Text cleanup") {
        Link(
          "S1-mini by Superwhisper",
          destination: URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF")!)
        NavigationLink("S1-mini license") { LicenseTextView(name: "S1-mini-LICENSE") }
        NavigationLink("S1-mini attribution") { LicenseTextView(name: "S1-mini-NOTICE") }
      }
      Section("Open source runtimes") {
        Link(
          "FluidAudio", destination: URL(string: "https://github.com/FluidInference/FluidAudio")!)
        Link(
          "WhisperKit", destination: URL(string: "https://github.com/argmaxinc/argmax-oss-swift")!)
        NavigationLink("llama.cpp license") { LicenseTextView(name: "llama-LICENSE") }
      }
    }.navigationTitle("Acknowledgments").navigationBarTitleDisplayMode(.inline)
  }
}

private struct LicenseTextView: View {
  let name: String
  private var contents: String {
    guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      return "The license file could not be opened. Model sources are linked in Acknowledgments."
    }
    return text
  }
  var body: some View {
    ScrollView { Text(contents).font(.footnote).textSelection(.enabled).padding(20) }
      .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
  }
}
