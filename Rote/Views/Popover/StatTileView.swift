import SwiftUI

struct StatTileView: View {
    let value: Int
    let delta: Int
    let label: String
    /// For "menu clicks that had a shortcut" a falling number is the good news.
    var lowerIsBetter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if lowerIsBetter ? delta < 0 : delta > 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.learned)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}
