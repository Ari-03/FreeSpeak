import SwiftUI

enum SpeakStyle {
  static let accent = Color(red: 0.83, green: 0.29, blue: 0.14)
  static let ink = Color.primary
  static let paper = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.08, green: 0.075, blue: 0.07, alpha: 1)
        : UIColor(red: 0.965, green: 0.951, blue: 0.929, alpha: 1)
    })
  static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct Eyebrow: View {
  let text: String
  var body: some View {
    Text(text.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
      .tracking(2).foregroundStyle(.secondary)
  }
}

struct Surface<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(SpeakStyle.card, in: RoundedRectangle(cornerRadius: 24))
  }
}

struct WaveformView: View {
  var level: Float
  var active: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let heights: [CGFloat] = [
    10, 18, 12, 30, 20, 42, 55, 32, 70, 44, 88, 55, 100, 74, 46, 83, 62, 96, 54, 76, 39, 61, 28, 42,
    24, 16, 25, 12, 8,
  ]
  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
        Capsule().fill(SpeakStyle.accent.opacity(active ? 0.85 : 0.22 + Double(index % 4) * 0.12))
          .frame(width: 4, height: active ? max(5, height * CGFloat(level)) : height * 0.65)
      }
    }
    .frame(height: 108)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
    .accessibilityHidden(true)
  }
}
