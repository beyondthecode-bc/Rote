#!/usr/bin/env swift
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "images/logo.png"
let side = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let amberTop = NSColor(calibratedRed: 0.99, green: 0.76, blue: 0.36, alpha: 1)
let amberBottom = NSColor(calibratedRed: 0.93, green: 0.58, blue: 0.14, alpha: 1)
let edgeColor = NSColor(calibratedRed: 0.70, green: 0.41, blue: 0.06, alpha: 1)

// Depth edge below the cap, then the cap face with a vertical gradient.
let edge = NSBezierPath(roundedRect: NSRect(x: 112, y: 64, width: 800, height: 760), xRadius: 176, yRadius: 176)
edgeColor.setFill()
edge.fill()
let face = NSBezierPath(roundedRect: NSRect(x: 112, y: 128, width: 800, height: 800), xRadius: 176, yRadius: 176)
NSGradient(starting: amberTop, ending: amberBottom)?.draw(in: face, angle: -90)

// Legend.
let descriptor = NSFont.systemFont(ofSize: 540, weight: .bold).fontDescriptor.withDesign(.rounded)
let font = NSFont(descriptor: descriptor ?? NSFont.systemFont(ofSize: 540, weight: .bold).fontDescriptor, size: 540)
    ?? NSFont.systemFont(ofSize: 540, weight: .bold)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let legend = NSAttributedString(string: "R", attributes: [
    .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
])
let textHeight = legend.size().height
legend.draw(in: NSRect(x: 0, y: 128 + (800 - textHeight) / 2, width: CGFloat(side), height: textHeight))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
