import SwiftUI

/// Two minimal brand glyphs drawn with SwiftUI Shape — enough visual
/// recognition for the About page's support links without shipping binary
/// assets. Not exact brand reproductions; simplified silhouettes.
enum BrandIcons {

    /// GitHub mark approximation — circle with the signature "octocat" notch.
    struct GitHubMark: View {
        var size: CGFloat = 14

        var body: some View {
            ZStack {
                Circle()
                    .fill(Color(red: 0.09, green: 0.09, blue: 0.10))
                GitHubGlyph()
                    .fill(Color.white)
                    .padding(size * 0.18)
            }
            .frame(width: size, height: size)
        }
    }

    /// Buy Me a Coffee mark — yellow square with coffee cup glyph.
    struct CoffeeMark: View {
        var size: CGFloat = 14

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.87, blue: 0.0))
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.06))
            }
            .frame(width: size, height: size)
        }
    }
}

/// Stylized octocat-ish glyph. Silhouette of a cat face — head + two ears + smile.
private struct GitHubGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Head (rounded square)
        let head = CGRect(x: rect.minX + w * 0.1, y: rect.minY + h * 0.28, width: w * 0.8, height: h * 0.55)
        p.addRoundedRect(in: head, cornerSize: CGSize(width: w * 0.26, height: h * 0.26))

        // Ears — two triangular tufts on top
        p.move(to: CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.35))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.28, y: rect.minY + h * 0.08))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.4, y: rect.minY + h * 0.28))
        p.closeSubpath()

        p.move(to: CGPoint(x: rect.minX + w * 0.6, y: rect.minY + h * 0.28))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.72, y: rect.minY + h * 0.08))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.8, y: rect.minY + h * 0.35))
        p.closeSubpath()

        // Tail flick — a little hook on the bottom right
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.72, y: rect.minY + h * 0.74, width: w * 0.16, height: h * 0.12))

        return p
    }
}
