#!/usr/bin/env swift
// Turns artwork into strict pixel art in Shepherdr's palette: the image is divided into a grid of
// cells, and each cell becomes one square in the palette color nearest to the cell's average.
// The palette is every hex color in App/Theme.swift, so the art always matches the app.
//
// Usage: swift scripts/pixelate.swift INPUT OUTPUT --cells WxH --scale N
//          [--palette App/Theme.swift] [--only RRGGBB,…] [--region MASK --region-only RRGGBB,…]
//          [--opacity 0.5] [--canvas WxH --background RRGGBB]
//   --cells    the grid, in art pixels
//   --scale    output pixels per art pixel
//   --only     restricts the palette to these theme colors (RRGGBB,RRGGBB,…)
//   --region   a mask image (white = inside) whose cells use their own theme colors, matched by
//              lightness alone: --region MASK --region-only RRGGBB,… recolors a subject, such as
//              the header's green dog into the amber shepherd of the app's logo. Repeatable; where
//              regions overlap, the last one wins.
//   --opacity  cells less covered than this become transparent; the rest are opaque
//   --canvas   centers the result on a solid canvas of this size (for social previews)
import AppKit
import CoreGraphics

struct Options {
    var input = "", output = "", palette = "App/Theme.swift"
    var cells = (width: 0, height: 0), scale = 1, opacity = 0.5
    var canvas: (width: Int, height: Int)?
    var background: UInt32?
    var only: Set<UInt32>?
    var regions: [(mask: String, only: Set<UInt32>?)] = []
}

func size(_ text: String) -> (width: Int, height: Int)? {
    let parts = text.split(separator: "x").compactMap { Int($0) }
    return parts.count == 2 && parts.allSatisfy { $0 > 0 } ? (parts[0], parts[1]) : nil
}

func parse() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    func value() -> String {
        guard !arguments.isEmpty else { fatalError("Missing value for an option") }
        return arguments.removeFirst()
    }
    var positional: [String] = []
    while !arguments.isEmpty {
        switch arguments.removeFirst() {
        case "--cells": options.cells = size(value()) ?? (0, 0)
        case "--scale": options.scale = Int(value()) ?? 0
        case "--palette": options.palette = value()
        case "--opacity": options.opacity = Double(value()) ?? 0.5
        case "--canvas": options.canvas = size(value())
        case "--background": options.background = UInt32(value(), radix: 16)
        case "--only": options.only = Set(value().split(separator: ",").compactMap { UInt32($0, radix: 16) })
        case "--region": options.regions.append((value(), nil))
        case "--region-only":
            guard !options.regions.isEmpty else { fatalError("--region-only must follow --region") }
            options.regions[options.regions.count - 1].only = Set(value().split(separator: ",").compactMap { UInt32($0, radix: 16) })
        case let argument: positional.append(argument)
        }
    }
    guard positional.count == 2, options.cells.width > 0, options.scale > 0 else {
        fatalError("Usage: pixelate.swift INPUT OUTPUT --cells WxH --scale N [--palette FILE] [--opacity 0.5] [--canvas WxH --background RRGGBB]")
    }
    (options.input, options.output) = (positional[0], positional[1])
    return options
}

// MARK: Color

func linear(_ channel: Double) -> Double {
    channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
}

/// CIE L*a*b* (D65) from linear sRGB, so "nearest" follows perceived difference.
func toLab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
    return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
}

struct PaletteColor {
    let hex: UInt32
    let lab: (Double, Double, Double)
    init(_ hex: UInt32) {
        self.hex = hex
        let channel = { (shift: UInt32) in linear(Double((hex >> shift) & 0xFF) / 255) }
        lab = toLab(channel(16), channel(8), channel(0))
    }
}

func palette(from path: String) -> [PaletteColor] {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { fatalError("Cannot read \(path)") }
    let pattern = try! NSRegularExpression(pattern: "0x([0-9A-Fa-f]{6})\\b")
    let hexes = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
        .compactMap { Range($0.range(at: 1), in: source).flatMap { UInt32(source[$0], radix: 16) } }
    let unique = Array(Set(hexes)).sorted()
    guard !unique.isEmpty else { fatalError("No colors found in \(path)") }
    return unique.map(PaletteColor.init)
}

func nearest(_ color: (Double, Double, Double), in palette: [PaletteColor], lightnessOnly: Bool = false) -> UInt32 {
    if lightnessOnly { return palette.min { abs($0.lab.0 - color.0) < abs($1.lab.0 - color.0) }!.hex }
    return palette.min { a, b in
        let da = pow(a.lab.0 - color.0, 2) + pow(a.lab.1 - color.1, 2) + pow(a.lab.2 - color.2, 2)
        let db = pow(b.lab.0 - color.0, 2) + pow(b.lab.1 - color.1, 2) + pow(b.lab.2 - color.2, 2)
        return da < db
    }!.hex
}

// MARK: Pixels

let options = parse()
let theme = palette(from: options.palette)
func subset(_ only: Set<UInt32>?) -> [PaletteColor] {
    guard let only else { return theme }
    let unknown = only.subtracting(theme.map(\.hex))
    guard unknown.isEmpty else {
        fatalError("Not in \(options.palette): \(unknown.map { String(format: "%06X", $0) }.sorted().joined(separator: ", "))")
    }
    return theme.filter { only.contains($0.hex) }
}
let colors = subset(options.only)
let regionColors = options.regions.map { subset($0.only) }
guard let image = NSImage(contentsOfFile: options.input)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot read \(options.input)")
}
let (width, height) = (image.width, image.height)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
/// RGBA pixels of an image, drawn at the input's size.
func pixels(of image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return pixels
}
let source = pixels(of: image)
let masks = options.regions.map { region -> [UInt8] in
    guard let image = NSImage(contentsOfFile: region.mask)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Cannot read \(region.mask)")
    }
    return pixels(of: image)
}

let (columns, rows) = options.cells
var cells = [UInt32?](repeating: nil, count: columns * rows)
for row in 0..<rows {
    let top = row * height / rows, bottom = max(top + 1, (row + 1) * height / rows)
    for column in 0..<columns {
        let left = column * width / columns, right = max(left + 1, (column + 1) * width / columns)
        // Average in linear light, weighting each pixel by its opacity.
        var red = 0.0, green = 0.0, blue = 0.0, coverage = 0.0
        var inside = [Int](repeating: 0, count: masks.count)
        for y in top..<bottom {
            for x in left..<right {
                let index = (y * width + x) * 4
                for (region, mask) in masks.enumerated() where mask[index] > 127 { inside[region] += 1 }
                let alpha = Double(source[index + 3]) / 255
                guard alpha > 0 else { continue }
                red += linear(Double(source[index]) / 255 / alpha) * alpha
                green += linear(Double(source[index + 1]) / 255 / alpha) * alpha
                blue += linear(Double(source[index + 2]) / 255 / alpha) * alpha
                coverage += alpha
            }
        }
        let count = Double((bottom - top) * (right - left))
        guard coverage / count >= options.opacity else { continue }
        let region = inside.indices.last { Double(inside[$0]) / count >= 0.5 }
        cells[row * columns + column] = nearest(toLab(red / coverage, green / coverage, blue / coverage),
                                                in: region.map { regionColors[$0] } ?? colors, lightnessOnly: region != nil)
    }
}

// MARK: Output

let artWidth = columns * options.scale, artHeight = rows * options.scale
let outputWidth = options.canvas?.width ?? artWidth, outputHeight = options.canvas?.height ?? artHeight
let originX = (outputWidth - artWidth) / 2, originY = (outputHeight - artHeight) / 2
var output = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
func put(_ x: Int, _ y: Int, _ hex: UInt32) {
    guard (0..<outputWidth).contains(x), (0..<outputHeight).contains(y) else { return }
    let index = (y * outputWidth + x) * 4
    output[index] = UInt8((hex >> 16) & 0xFF)
    output[index + 1] = UInt8((hex >> 8) & 0xFF)
    output[index + 2] = UInt8(hex & 0xFF)
    output[index + 3] = 255
}
if let background = options.background {
    for y in 0..<outputHeight { for x in 0..<outputWidth { put(x, y, background) } }
}
for row in 0..<rows {
    for column in 0..<columns {
        guard let hex = cells[row * columns + column] else { continue }
        for dy in 0..<options.scale {
            for dx in 0..<options.scale {
                put(originX + column * options.scale + dx, originY + row * options.scale + dy, hex)
            }
        }
    }
}
let result = output.withUnsafeMutableBytes { bytes in
    CGContext(data: bytes.baseAddress, width: outputWidth, height: outputHeight, bitsPerComponent: 8,
              bytesPerRow: outputWidth * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}
let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: options.output))
let used = Set(cells.compactMap { $0 }).count
print("\(options.output): \(columns)×\(rows) art pixels at \(options.scale)px, \(used) of \(theme.count) theme colors")
