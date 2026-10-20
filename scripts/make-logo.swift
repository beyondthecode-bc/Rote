#!/usr/bin/env swift
// Turns the generated icon artwork (images/source/icon-art.png) into the 1024x1024 app icon
// (images/logo.png). It finds the artwork's tile, fits it to the macOS icon grid (an 824 px
// rounded-square tile on a 1024 px canvas), clips it to that shape so stray glow and matte specks
// outside the tile disappear, and adds a system-style drop shadow.
//
// Run from the repository root:  swift scripts/make-logo.swift [source] [output]
import AppKit

let source = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "images/source/icon-art.png"
let output = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "images/logo.png"

guard let art = NSImage(contentsOfFile: source),
      let artCG = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("error: cannot read \(source); run from the repository root or pass its path\n", stderr)
    exit(1)
}

// Redraw into a known RGBA layout so the alpha channel can be scanned directly.
let width = artCG.width, height = artCG.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let scanContext = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("scan context") }
scanContext.draw(artCG, in: CGRect(x: 0, y: 0, width: width, height: height))

// The tile is the band of rows and columns that are mostly opaque. Counting per row and column
// ignores isolated specks and the soft glow that leaks past the tile's edge.
var rowCounts = [Int](repeating: 0, count: height)
var columnCounts = [Int](repeating: 0, count: width)
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 230 {
        rowCounts[y] += 1
        columnCounts[x] += 1
    }
}
let rows = rowCounts.indices.filter { rowCounts[$0] > width / 3 }
let columns = columnCounts.indices.filter { columnCounts[$0] > height / 3 }
guard let top = rows.first, let bottom = rows.last, let left = columns.first, let right = columns.last else {
    fputs("error: no opaque tile found in \(source)\n", stderr)
    exit(1)
}
// CGContext rows run bottom-up; CGImage cropping is top-down.
let tileRect = CGRect(x: left, y: height - 1 - bottom, width: right - left + 1, height: bottom - top + 1)
guard let tile = artCG.cropping(to: tileRect) else { fatalError("crop") }

let side = 1024
let tileSide: CGFloat = 824
let cornerRadius: CGFloat = tileSide * 0.225
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Slightly above centre, leaving room for the shadow below, as on Apple's icon grid.
let tileFrame = NSRect(x: (CGFloat(side) - tileSide) / 2, y: 108, width: tileSide, height: tileSide)
let shape = NSBezierPath(roundedRect: tileFrame, xRadius: cornerRadius, yRadius: cornerRadius)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSImage(cgImage: tile, size: tileFrame.size).draw(in: tileFrame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

// A hairline inner highlight keeps the edge crisp on dark backgrounds.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSColor.white.withAlphaComponent(0.10).setStroke()
shape.lineWidth = 3
shape.stroke()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
do {
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    fputs("error: cannot write \(output): \(error.localizedDescription)\n", stderr)
    exit(1)
}
print("wrote \(output) (tile \(Int(tileRect.width))x\(Int(tileRect.height)) from \(source))")
