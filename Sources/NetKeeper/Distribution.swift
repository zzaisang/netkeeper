/// 배포판별 기능 차이. Mac App Store판은 `-D APPSTORE`로 빌드한다 (scripts/archive.sh).
/// App Sandbox에서는 다른 앱 조작(접근성)과 시스템 키체인 읽기가 막혀 두 기능을 끈다.
enum Distribution {
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif

    /// Control Center Wi-Fi 메뉴를 접근성으로 눌러 iPhone 핫스팟을 깨우기
    static let supportsInstantHotspot = !isAppStore
    /// macOS 시스템 키체인에 저장된 Wi-Fi 암호 가져오기
    static let canImportMacPasswords = !isAppStore
}
