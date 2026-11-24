import AppKit

/// macOS Wi-Fi 메뉴의 "Personal Hotspot"(Instant Hotspot) 항목을 대신 눌러 iPhone 핫스팟을 깨운다.
/// Instant Hotspot은 공개 API가 없어 접근성(Accessibility)으로 Control Center 메뉴를 조작한다.
/// ponytail: Control Center 접근성 식별자(`wifi-network-<SSID>`)에 의존 — macOS 업데이트로 바뀌면 여기만 고치면 된다.
enum InstantHotspot {
    /// 접근성 권한 확인. 없으면 macOS가 권한 요청 창을 띄운다.
    static func ensureTrusted() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    /// iPhone 항목을 찾아 눌렀으면 true. 근처에 iPhone이 없으면 메뉴에 항목이 없어 false.
    static func press(_ ssid: String) -> Bool {
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
        else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar: AXUIElement = value(app, kAXExtrasMenuBarAttribute),
              let wifiMenu = find(in: menuBar, depth: 2, where: {
                  role($0) == kAXMenuBarItemRole && (description($0)?.hasPrefix("Wi") ?? false)
              })
        else { return false }

        AXUIElementPerformAction(wifiMenu, kAXPressAction as CFString)
        defer { closeMenu(app, wifiMenu) }

        let identifier = "wifi-network-\(ssid)"
        for _ in 0..<20 { // 메뉴가 그려질 때까지 최대 2초
            usleep(100_000)
            for window in windows(app) {
                if let item = find(in: window, depth: 8, where: { self.identifier($0) == identifier }) {
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    private static func closeMenu(_ app: AXUIElement, _ wifiMenu: AXUIElement) {
        usleep(300_000)
        if !windows(app).isEmpty { AXUIElementPerformAction(wifiMenu, kAXPressAction as CFString) }
    }

    // MARK: - AX 헬퍼

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }

    private static func role(_ e: AXUIElement) -> String? { value(e, kAXRoleAttribute) }
    private static func description(_ e: AXUIElement) -> String? { value(e, kAXDescriptionAttribute) }
    private static func identifier(_ e: AXUIElement) -> String? { value(e, kAXIdentifierAttribute) }
    private static func windows(_ app: AXUIElement) -> [AXUIElement] { value(app, kAXWindowsAttribute) ?? [] }

    private static func find(in element: AXUIElement, depth: Int, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(element) { return element }
        guard depth > 0 else { return nil }
        for child: AXUIElement in value(element, kAXChildrenAttribute) ?? [] {
            if let found = find(in: child, depth: depth - 1, where: match) { return found }
        }
        return nil
    }
}
