// Renders the Alquimia mark onto a canvas-colored 1024x1024 PNG for the app icon.
// Usage: swift tools/render_icon.swift tools/logo-mark.svg AlquimiaVoice/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { fputs("usage: render_icon.swift <mark.svg> <out.png>\n", stderr); exit(2) }
guard let mark = NSImage(contentsOfFile: args[1]) else { fputs("cannot load \(args[1])\n", stderr); exit(1) }

let side = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSColor(srgbRed: 0xFA / 255.0, green: 0xFA / 255.0, blue: 0xF7 / 255.0, alpha: 1)
canvas.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
let markWidth = CGFloat(side) * 0.56
let aspect = mark.size.width / mark.size.height
let markHeight = markWidth / aspect
let rect = NSRect(x: (CGFloat(side) - markWidth) / 2, y: (CGFloat(side) - markHeight) / 2, width: markWidth, height: markHeight)
NSGraphicsContext.current?.imageInterpolation = .high
mark.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
