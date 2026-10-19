#!/usr/bin/env swift
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "images/banner.png"
let logoPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "images/logo.png"
let width = 2400, height = 600
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(
    starting: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.16, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1)
)?.draw(in: canvas, angle: -20)

guard let logo = NSImage(contentsOfFile: logoPath) else {
    fatalError("logo not found at \(logoPath); run from the repo root or pass its path")
}
logo.draw(in: NSRect(x: 160, y: 110, width: 380, height: 380), from: .zero, operation: .sourceOver, fraction: 1)

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded)
    let font = descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? NSFont.systemFont(ofSize: size, weight: weight)
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        .draw(at: NSPoint(x: 640, y: y))
}
text("Rote", size: 180, weight: .bold, color: .white, y: 290)
text("The keyboard shortcut coach for your Mac", size: 64, weight: .medium, color: NSColor(calibratedWhite: 1, alpha: 0.7), y: 190)
text("Free · Open source · Nothing leaves your Mac", size: 40, weight: .regular, color: NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.23, alpha: 1), y: 120)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
