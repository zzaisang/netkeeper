// 앱 아이콘(Resources/AppIcon.icns) 생성: swift scripts/make-icon.swift
// 메뉴바 아이콘과 같은 '궤도' 모양을 macOS 아이콘 격자(1024 캔버스, 824 둥근 사각형)에 그린다.
import AppKit

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor(srgbRed: 0.17, green: 0.19, blue: 0.22, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.27, blue: 0.31, alpha: 1),
               ending: NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1))!.draw(in: shape, angle: -90)

    // 궤도: 24pt 시안 좌표(중심 12,12 / 반지름 7.5)를 타일 안 512 영역에 맞춘다
    let unit = 520 * s / 24, origin = NSPoint(x: 512 * s - 12 * unit, y: 512 * s - 12 * unit)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * unit, y: origin.y + (24 - y) * unit) }
    let orbit = NSBezierPath()
    for degree in stride(from: CGFloat(-11), through: 297.6, by: 2) {
        let r = degree * .pi / 180
        let point = p(12 + 7.5 * cos(r), 12 + 7.5 * sin(r))
        orbit.isEmpty ? orbit.move(to: point) : orbit.line(to: point)
    }
    orbit.lineWidth = 2.1 * unit
    orbit.lineCapStyle = .round
    NSColor.white.setStroke()
    orbit.stroke()
    func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor) {
        let c = p(x, y)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r * unit, y: c.y - r * unit, width: 2 * r * unit, height: 2 * r * unit)).fill()
    }
    dot(12, 12, 2.1, .white)
    dot(18.6, 6.4, 2.1, NSColor(srgbRed: 0x2F / 255, green: 0x6F / 255, blue: 0xD6 / 255, alpha: 1))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil failed")
