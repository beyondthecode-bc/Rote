import SwiftUI

/// Amber marks what the coach is working on, green marks what is learned,
/// everything else is system neutral. Keycaps carry the visual identity.
enum DesignTokens {
    static let accent = Color(red: 0.96, green: 0.66, blue: 0.23)
    static let learned = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let hairline = Color(nsColor: .separatorColor).opacity(0.5)
    static let surfaceMuted = Color(nsColor: .controlBackgroundColor).opacity(0.4)

    static let popoverWidth: CGFloat = 360
    static let popoverMaxHeight: CGFloat = 520
    static let settingsWidth: CGFloat = 480
    static let aboutWidth: CGFloat = 380
    static let aboutHeight: CGFloat = 560
    static let onboardingSize = CGSize(width: 520, height: 420)

    static let hudCornerRadius: CGFloat = 16
    static let hudTopInset: CGFloat = 12
    static let hudShadowPadding: CGFloat = 24
    static let overlayColumnWidth: CGFloat = 260
    static let overlayColumnSpacing: CGFloat = 24

    static let sectionLabelSize: CGFloat = 9
    static let sectionLabelTracking: CGFloat = 2.0
}
