#!/usr/bin/env swift
// Composes the README banner (images/banner.png, 2400x600) and the GitHub social preview
// (images/social-preview.png, 1280x640) from the generated artwork in images/source/, the app
// icon (images/logo.png) and text set in SF Pro Rounded, so the lettering stays crisp.
//
// Run from the repository root:  swift scripts/make-banner.swift
import AppKit

let amber = NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.23, alpha: 1)

func load(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else {
        fputs("error: cannot read \(path); run from the repository root\n", stderr)
        exit(1)
    }
    return image
}

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func text(_ string: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font(size, weight), .foregroundColor: color, .kern: size * -0.01])
}

/// Renders `draw` into a width x height PNG at `path`.
func render(_ path: String, width: Int, height: Int, _ draw: (NSRect) -> Void) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap") }
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        fputs("error: cannot write \(path): \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    print("wrote \(path)")
}

/// Fills `canvas` with a full-width band of `art` whose vertical centre sits at `center`
/// (0 = top, 1 = bottom of the artwork), keeping the canvas's aspect ratio.
func drawBand(of art: NSImage, centeredAt center: CGFloat, in canvas: NSRect) {
    let bandHeight = art.size.width * canvas.height / canvas.width
    let middleFromTop = center * art.size.height
    let originY = art.size.height - middleFromTop - bandHeight / 2
    let source = NSRect(x: 0, y: max(0, min(originY, art.size.height - bandHeight)), width: art.size.width, height: bandHeight)
    art.draw(in: canvas, from: source, operation: .copy, fraction: 1)
}

/// Draws `art` at `scale` with its right edge on the canvas's right edge and the point
/// `focusFromTop` (0 = top, 1 = bottom of the artwork) on the canvas's vertical centre.
/// The canvas left of the artwork is filled with the artwork's own edge colour and the seam
/// is blended away, so a wide banner keeps the keycaps at a comfortable size.
func drawArtRightAligned(_ art: NSImage, scale: CGFloat, focusFromTop: CGFloat, in canvas: NSRect) {
    let size = NSSize(width: art.size.width * scale, height: art.size.height * scale)
    let frame = NSRect(
        x: canvas.maxX - size.width,
        y: canvas.midY - size.height * (1 - focusFromTop),
        width: size.width, height: size.height
    )
    var edge = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    if let data = art.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
       let sample = bitmap.colorAt(x: 4, y: Int(CGFloat(bitmap.pixelsHigh) * focusFromTop)) {
        edge = sample.usingColorSpace(.deviceRGB) ?? edge
    }
    edge.setFill()
    canvas.fill()
    art.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    let blend = NSRect(x: frame.minX - 1, y: canvas.minY, width: 420, height: canvas.height)
    NSGradient(starting: edge, ending: edge.withAlphaComponent(0))?.draw(in: blend, angle: 0)
}

let logo = load("images/logo.png")

// README banner: icon and text on the left, the glass keycaps on the right.
render("images/banner.png", width: 2400, height: 600) { canvas in
    drawArtRightAligned(load("images/source/banner-art.png"), scale: 1.36, focusFromTop: 0.465, in: canvas)
    logo.draw(in: NSRect(x: 110, y: 100, width: 400, height: 400))
    let x: CGFloat = 560
    text("Rote", 150, .bold, .white).draw(at: NSPoint(x: x - 6, y: 330))
    let secondary = NSColor.white.withAlphaComponent(0.84)
    text("The keyboard shortcut coach", 52, .semibold, secondary).draw(at: NSPoint(x: x, y: 262))
    text("for your Mac", 52, .semibold, secondary).draw(at: NSPoint(x: x, y: 200))
    text("Free  ·  Open source  ·  Nothing leaves your Mac", 34, .medium, amber).draw(at: NSPoint(x: x, y: 118))
}

// GitHub social preview (Settings › General › Social preview): same layout stacked for 2:1.
render("images/social-preview.png", width: 1280, height: 640) { canvas in
    drawBand(of: load("images/source/social-art.png"), centeredAt: 0.48, in: canvas)
    logo.draw(in: NSRect(x: 64, y: 392, width: 184, height: 184))
    text("Rote", 112, .bold, .white).draw(at: NSPoint(x: 76, y: 250))
    text("The keyboard shortcut coach", 44, .semibold, NSColor.white.withAlphaComponent(0.85)).draw(at: NSPoint(x: 80, y: 196))
    text("for your Mac", 44, .semibold, NSColor.white.withAlphaComponent(0.85)).draw(at: NSPoint(x: 80, y: 144))
    text("Free  ·  Open source  ·  Nothing leaves your Mac", 28, .medium, amber).draw(at: NSPoint(x: 80, y: 72))
}
