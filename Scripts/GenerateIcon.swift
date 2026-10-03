import AppKit

func render(width: Int, height: Int, foreground: Bool, background: Bool, path: String) throws {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
    bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let w = CGFloat(width)
  let h = CGFloat(height)
  let side = min(w, h)
  if background {
    NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.2, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()
  }
  if foreground {
    let x = w / 2 - side * 0.27
    let y = h / 2 - side * 0.24
    NSColor(calibratedRed: 0.4, green: 0.86, blue: 0.72, alpha: 1).setFill()
    let card = NSBezierPath(
      roundedRect: NSRect(x: x, y: y, width: side * 0.54, height: side * 0.48),
      xRadius: side * 0.08, yRadius: side * 0.08)
    card.fill()
    NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.2, alpha: 1).setFill()
    for dx in [0.0, 0.16] {
      for dy in [0.0, 0.15] {
        NSBezierPath(
          ovalIn: NSRect(
            x: x + side * (0.14 + dx), y: y + side * (0.095 + dy), width: side * 0.11,
            height: side * 0.11)
        ).fill()
      }
    }
  }
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let root = "Resources/TV.xcassets/App Icon & Top Shelf Image.brandassets"
for (name, w, h) in [("App Icon", 400, 240), ("App Icon - App Store", 1280, 768)] {
  for layer in ["Front", "Back"] {
    try render(
      width: w, height: h, foreground: layer == "Front", background: layer == "Back",
      path: "\(root)/\(name).imagestack/\(layer).imagestacklayer/Content.imageset/Image.png")
  }
}
try render(
  width: 1920, height: 720, foreground: true, background: true,
  path: "\(root)/Top Shelf Image.imageset/Image.png")
try render(
  width: 1024, height: 1024, foreground: true, background: true,
  path: "Resources/Phone.xcassets/AppIcon.appiconset/Icon.png")
