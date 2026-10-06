#!/usr/bin/env swift
// Renders Shepherdr's app icon from its pixel art: a German Shepherd in amber, in Matrix digital rain,
// on the macOS icon grid. The art is one image pixel per art pixel, in App/Theme.swift's palette (see
// pixelate.swift); at 206×206 it fills the grid's 824-point body exactly: 4 pixels per art pixel at 1024.
// Usage: swift scripts/make-icon.swift docs/assets/icon.png App/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let source = URL(fileURLWithPath: arguments.first ?? "docs/assets/icon.png")
guard let art = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot read icon art at \(source.path)")
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    // Where every art pixel covers a whole number of output pixels, keep the edges hard. Smaller
    // icons average art pixels together instead of dropping some.
    let pixelsPerArtPixel = 824 * s / 1024 / CGFloat(art.width)
    ctx.interpolationQuality = pixelsPerArtPixel >= 1 && pixelsPerArtPixel.rounded() == pixelsPerArtPixel ? .none : .high

    // macOS icon grid: 824pt body with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x090C0A))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(art, in: body)
    ctx.restoreGState()

    // Hairline phosphor rim.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(rgb(0x4DFFA0, 0.22))
    ctx.setLineWidth(4)
    ctx.strokePath()

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images to \(output.path)")
