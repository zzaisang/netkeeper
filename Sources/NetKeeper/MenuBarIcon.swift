import AppKit

/// 메뉴바 아이콘 '궤도': 중심점 + 열린 원호 + 위성 점. 상태는 우하단 뱃지로만 표시한다.
enum MenuBarIcon {
    enum Badge: CaseIterable {
        case none, cellular, offline, paused
    }

    static func image(_ badge: Badge) -> NSImage { cache[badge]! }

    private static let cache = Dictionary(uniqueKeysWithValues: Badge.allCases.map { ($0, make($0)) })

    private static let size = NSSize(width: 20, height: 20)
    private static let scale: CGFloat = 0.75 // 24pt 시안 좌표 → 18pt
    private static let badgeCenter = NSPoint(x: 16.5, y: 16.5)
    private static let badgeRadius: CGFloat = 3.5
    private static let badgeCutout: CGFloat = 1.5

    private static func make(_ badge: Badge) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            // 뱃지가 있으면 컬러 이미지라 글리프 색을 메뉴바 외형에 맞춰 직접 고른다.
            (badge == .none ? NSColor.black : NSColor.labelColor).set()
            drawGlyph()
            if badge != .none { drawBadge(badge) }
            return true
        }
        image.isTemplate = badge == .none
        return image
    }

    private static func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x * scale, y: y * scale + 1)
    }

    private static func drawGlyph() {
        // 시안 SVG: M19.2 10.6 A7.5 7.5 0 1 1 15.5 5.3 (중심 12,12) — y 아래 방향 기준 -11°→297.6°
        let orbit = NSBezierPath()
        let start: CGFloat = -11, end: CGFloat = 297.6
        for degree in stride(from: start, through: end, by: 4) + [end] {
            let radian = degree * .pi / 180
            let p = point(12 + 7.5 * cos(radian), 12 + 7.5 * sin(radian))
            orbit.isEmpty ? orbit.move(to: p) : orbit.line(to: p)
        }
        orbit.lineWidth = 2 * scale
        orbit.lineCapStyle = .round
        orbit.lineJoinStyle = .round
        orbit.stroke()

        for (x, y) in [(12.0, 12.0), (18.6, 6.4)] {
            let c = point(x, y), r = 2 * scale
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        }
    }

    private static func drawBadge(_ badge: Badge) {
        func circle(_ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - radius, y: badgeCenter.y - radius,
                                        width: radius * 2, height: radius * 2))
        }
        // 뱃지 둘레를 투명하게 파내 글리프와 분리
        NSGraphicsContext.current?.compositingOperation = .clear
        circle(badgeRadius + badgeCutout).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        switch badge {
        case .cellular:
            NSColor(srgbRed: 0x2F / 255, green: 0x6F / 255, blue: 0xD6 / 255, alpha: 1).set()
            circle(badgeRadius).fill()
        case .offline:
            NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1).set()
            circle(badgeRadius).fill()
        case .paused:
            NSColor.systemGray.set()
            let ring = circle(badgeRadius - 0.75)
            ring.lineWidth = 1.5
            ring.stroke()
        case .none:
            break
        }
    }
}
