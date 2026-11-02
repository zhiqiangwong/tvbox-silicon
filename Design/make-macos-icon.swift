// Renders the legacy macOS app icon sizes with rounded corners and transparent margins.
// Usage (from the repository root): swift Design/make-macos-icon.swift
import AppKit
import SwiftUI

let root = URL(fileURLWithPath: "Config/macOS/Assets.xcassets/AppIcon.appiconset")
let source = NSImage(contentsOfFile: "Design/yingxia-icon.png")!
    .cgImage(forProposedRect: nil, context: nil, hints: nil)!
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let canvas = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                       bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// The tile occupies 824 points of the 1024-point canvas, leaving room for its shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let outline = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: tile).cgPath
canvas.saveGState()
canvas.setShadow(offset: CGSize(width: 0, height: -8), blur: 12,
                 color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
canvas.setFillColor(CGColor(srgbRed: 0, green: 0.01, blue: 0.08, alpha: 1))
canvas.addPath(outline)
canvas.fillPath()
canvas.restoreGState()
canvas.addPath(outline)
canvas.clip()
canvas.interpolationQuality = .high
canvas.draw(source, in: tile)
let master = canvas.makeImage()!

struct Catalog: Decodable {
    struct Image: Decodable { let filename: String; let size: String; let scale: String }
    let images: [Image]
}
let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("Contents.json")))
for image in catalog.images {
    let points = Int(image.size.components(separatedBy: "x")[0])!
    let scale = Int(image.scale.dropLast())!
    let pixels = points * scale
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: root.appendingPathComponent(image.filename), options: .atomic)
    print("Wrote \(image.filename) (\(pixels)×\(pixels))")
}
