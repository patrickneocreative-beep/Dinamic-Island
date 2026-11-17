import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let tile = CGPath(roundedRect: CGRect(x: 32, y: 32, width: 960, height: 960), cornerWidth: 220, cornerHeight: 220, transform: nil)
context.addPath(tile)
context.clip()
let gradient = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0.43, alpha: 1), CGColor(gray: 0.12, alpha: 1)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 1024), end: CGPoint(x: 900, y: 0), options: [])
let pill = CGPath(roundedRect: CGRect(x: 138, y: 357, width: 748, height: 310), cornerWidth: 155, cornerHeight: 155, transform: nil)
context.addPath(pill)
context.setFillColor(CGColor(gray: 0.12, alpha: 0.4))
context.fillPath()
context.saveGState()
context.addPath(pill)
context.clip()
let glass = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.30), CGColor(gray: 1, alpha: 0.04), CGColor(gray: 1, alpha: 0.15)] as CFArray, locations: [0, 0.6, 1])!
context.drawLinearGradient(glass, start: CGPoint(x: 200, y: 667), end: CGPoint(x: 800, y: 357), options: [])
context.restoreGState()
context.addPath(pill)
context.setLineWidth(3)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
context.strokePath()
context.setFillColor(CGColor(gray: 1, alpha: 0.9))
context.fillEllipse(in: CGRect(x: 218, y: 459, width: 106, height: 106))
for (index, height) in [58.0, 118, 168, 100, 50].enumerated() {
    let bar = CGPath(roundedRect: CGRect(x: 571 + Double(index) * 35, y: 512 - height / 2, width: 16, height: height), cornerWidth: 8, cornerHeight: 8, transform: nil)
    context.addPath(bar)
    context.fillPath()
}
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
