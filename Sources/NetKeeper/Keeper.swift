import AppKit
import CoreLocation
import CoreWLAN
import OSLog
import ServiceManagement

/// 주기적으로 인터넷 상태를 확인하고, 필요하면 우선순위가 가장 높은 네트워크로 갈아탄다.
@MainActor
final class Keeper: NSObject, ObservableObject, CWEventDelegate {
    @Published var preferred: [String] { didSet { defaults.set(preferred, forKey: "preferred") } }
    @Published var hotspot: String { didSet { defaults.set(hotspot, forKey: "hotspot") } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    /// 인터넷 확인 주기(초)
    @Published var checkInterval: Double {
        didSet { defaults.set(checkInterval, forKey: "checkInterval"); scheduleTimer() }
    }
    /// 차선 네트워크 사용 중일 때 상위 네트워크 탐색 주기(초)
    @Published var scanInterval: Double { didSet { defaults.set(scanInterval, forKey: "scanInterval") } }
    /// 몇 번 연속 불통이면 다음 네트워크로 넘어갈지
    @Published var failuresBeforeSwitch: Int {
        didSet { defaults.set(failuresBeforeSwitch, forKey: "failuresBeforeSwitch") }
    }
    /// 불통 네트워크를 후보에서 빼 두는 시간(초)
    @Published var deadCooldown: Double { didSet { defaults.set(deadCooldown, forKey: "deadCooldown") } }
    @Published private(set) var current: String?
    @Published private(set) var online = false
    /// 최근 스캔에서 보인 Wi-Fi (신호 센 순)
    @Published private(set) var nearby: [Nearby] = []
    @Published private(set) var history = ConnectionHistory()
    private var lastTickAt: Date?
    private var lastSSID: String?
    /// macOS에 이미 저장된(한 번이라도 연결했던) Wi-Fi
    @Published private(set) var knownToMac: Set<String> = []
    /// 사용자에게 알릴 최근 안내. nil이면 정상(표시 안 함).
    @Published private(set) var status: String? {
        didSet {
            statusAt = Date()
            if let status, status != oldValue { log.notice("\(status, privacy: .public)") }
        }
    }
    private var statusAt = Date.distantPast
    private let log = Logger(subsystem: "com.zzaisang.NetKeeper", category: "keeper")

    private let defaults = UserDefaults.standard
    private let wifi = CWWiFiClient.shared()
    private let location = CLLocationManager()
    private var failures: [String: Int] = [:]
    private var coolUntil: [String: Date] = [:]
    private var lastScan = Date.distantPast
    private var graceUntil = Date.distantPast
    private var busy = false
    /// 시스템 키체인 조회를 이미 시도한 SSID. 관리자 인증 창은 네트워크당 최초 한 번만 (앱 재시작해도 유지).
    /// 다시 가져오려면 설정에서 직접 "macOS 암호 가져오기".
    private var macPasswordTried: Set<String> {
        get { Set(defaults.stringArray(forKey: "macPasswordTried") ?? []) }
        set { defaults.set(Array(newValue), forKey: "macPasswordTried") }
    }
    /// 사용자가 직접 고른 네트워크. 인터넷이 되는 동안은 자동 전환으로 갈아타지 않는다.
    private var manualPin: String?
    private var timer: Timer?

    private static let joinFailCooldown: TimeInterval = 60
    private static let joinGrace: TimeInterval = 20      // 연결 직후 DHCP 등 대기
    /// iPhone 핫스팟을 못 깨웠을 때 다시 시도하기까지. 이동 중엔 곧 잡히므로 짧게.
    private static let hotspotRetry: TimeInterval = 30

    /// 셀룰러(핫스팟)도 Wi-Fi와 같은 목록에서 순위를 가진다. `hotspot`은 그중 셀룰러 표시일 뿐.
    var priority: [String] { preferred }

    var badge: MenuBarIcon.Badge {
        if !enabled { return .paused }
        if !online { return .offline }
        return current != nil && current == hotspot ? .cellular : .none
    }

    override init() {
        let defaults = UserDefaults.standard
        preferred = defaults.stringArray(forKey: "preferred") ?? []
        hotspot = defaults.string(forKey: "hotspot") ?? ""
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        checkInterval = defaults.object(forKey: "checkInterval") as? Double ?? 5
        scanInterval = defaults.object(forKey: "scanInterval") as? Double ?? 30
        failuresBeforeSwitch = defaults.object(forKey: "failuresBeforeSwitch") as? Int ?? 2
        deadCooldown = defaults.object(forKey: "deadCooldown") as? Double ?? 300
        super.init()
        if !hotspot.isEmpty, !preferred.contains(hotspot) { preferred.append(hotspot) } // 예전 별도 저장분 이전
        location.requestWhenInUseAuthorization() // macOS 14+: SSID 조회에 위치 권한 필요

        // 타이머를 기다리지 않고 Wi-Fi 연결이 바뀌거나 끊기는 즉시 점검
        wifi.delegate = self
        try? wifi.startMonitoringEvent(with: .ssidDidChange)
        try? wifi.startMonitoringEvent(with: .linkDidChange)

        scheduleTimer()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.tick(forceScan: true) }
        }
        Task { await tick(forceScan: true) }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in await self.tick() }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in await self.tick() }
    }

    // MARK: - 설정 변경

    func add(_ ssid: String, password: String) {
        let ssid = ssid.trimmingCharacters(in: .whitespaces)
        guard !ssid.isEmpty, !preferred.contains(ssid) else { return }
        preferred.append(ssid)
        if !password.isEmpty {
            Keychain.set(password, for: ssid)
        } else if knownToMac.contains(ssid) {
            Task { await importMacPassword(ssid) }
        }
    }

    /// macOS 시스템 키체인에 저장된 Wi-Fi 암호를 가져와 앱 키체인에 저장한다.
    /// 시스템 키체인 접근 시 macOS가 관리자 인증을 한 번 요구한다.
    @discardableResult
    func importMacPassword(_ ssid: String) async -> String? {
        macPasswordTried.insert(ssid)
        let password = await Task.detached { Self.macPassword(ssid) }.value
        if let password {
            Keychain.set(password, for: ssid)
            status = String(localized: "\(ssid) 암호를 macOS에서 가져옴")
            objectWillChange.send()
        } else {
            status = String(localized: "\(ssid) 암호를 macOS에서 가져오지 못함 — 직접 입력하세요")
        }
        return password
    }

    nonisolated private static func macPassword(_ ssid: String) -> String? {
        var password: NSString?
        guard CWKeychainFindWiFiPassword(.system, Data(ssid.utf8), &password) == errSecSuccess else { return nil }
        return password as String?
    }

    func remove(_ ssid: String) {
        preferred.removeAll { $0 == ssid }
        if ssid == hotspot { hotspot = "" }
        Keychain.set("", for: ssid)
    }

    func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard preferred.indices.contains(index), preferred.indices.contains(target) else { return }
        preferred.move(fromOffsets: [index], toOffset: offset > 0 ? target + 1 : target)
    }

    /// 셀룰러(iPhone 핫스팟)로 표시. 목록에 없으면 맨 뒤에 추가하고, 순위는 드래그로 바꾼다.
    func setHotspot(_ ssid: String) {
        if !preferred.contains(ssid) { preferred.append(ssid) }
        hotspot = ssid // 암호는 Instant Hotspot이 처리하므로 가져오지 않음
    }

    func setPassword(_ password: String, for ssid: String) {
        guard !ssid.isEmpty else { return }
        Keychain.set(password, for: ssid)
        objectWillChange.send()
    }

    func hasPassword(_ ssid: String) -> Bool { Keychain.password(for: ssid) != nil }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                status = String(localized: "로그인 항목 설정 실패: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    func signal(of ssid: String) -> Nearby? { nearby.first { $0.ssid == ssid } }

    func toggleCellular(_ ssid: String) {
        hotspot = hotspot == ssid ? "" : ssid
    }

    /// 메뉴에서 직접 고른 네트워크로 바로 연결한다.
    func connectNow(_ ssid: String) async {
        guard ssid != current, let iface = wifi.interface() else { return }
        status = String(localized: "\(ssid) 연결 중…")
        // 진행 중인 점검이 끝날 때까지 기다렸다가 바로 연결 (클릭이 무시되지 않게)
        for _ in 0..<100 where busy { try? await Task.sleep(for: .milliseconds(100)) }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let networks = await Task.detached { (try? iface.scanForNetworks(withSSID: Data(ssid.utf8))) ?? [] }.value
        if await join(ssid, among: networks, iface: iface) {
            manualPin = ssid
        } else if networks.isEmpty {
            status = String(localized: "\(ssid) 범위 밖")
        }
    }

    // MARK: - 감시 루프

    func tick(forceScan: Bool = false) async {
        guard !busy, let iface = wifi.interface() else { return }
        busy = true
        defer { busy = false }

        let now = Date()
        current = iface.ssid()
        online = await Self.probe()
        recordHealth(now: now)
        recordHistory(now: now)
        if manualPin != nil, current != manualPin || (!online && now > graceUntil) { manualPin = nil }
        let pinned = online && manualPin != nil

        let onTop = online && current == priority.first || pinned
        let wantScan = forceScan
            || (enabled && !priority.isEmpty && !onTop
                && (!online || now.timeIntervalSince(lastScan) >= scanInterval))
        guard wantScan else { return }

        if !iface.powerOn() {
            status = String(localized: "Wi-Fi가 꺼져 있음")
            return
        }
        lastScan = now
        let networks = await Task.detached { (try? iface.scanForNetworks(withSSID: nil)) ?? [] }.value
        updateNearby(networks, iface: iface)
        if nearby.isEmpty, !networks.isEmpty {
            status = String(localized: "위치 서비스 권한 필요 (시스템 설정 > 개인정보 보호 > 위치 서비스)")
            return
        }

        guard enabled, !pinned else { return }
        let cooling = Set(coolUntil.filter { $0.value > now }.keys)
        var visible = Set(nearby.map(\.ssid))
        if !hotspot.isEmpty, Distribution.supportsInstantHotspot, !InstantHotspot.blockedBySystem {
            visible.insert(hotspot) // 스캔에 없어도 Instant Hotspot으로 깨울 수 있음
        }
        guard case let .connect(target) = decide(
            current: current, online: online, visible: visible, priority: priority, cooling: cooling
        ) else { return }
        await join(target, among: networks, iface: iface)
    }

    /// 팝오버를 열 때 스캔을 기다리지 않고 macOS가 마지막으로 스캔한 결과를 바로 보여준다.
    func showCachedScan() {
        guard let iface = wifi.interface() else { return }
        current = iface.ssid()
        updateNearby(iface.cachedScanResults() ?? [], iface: iface)
    }

    private func updateNearby(_ networks: Set<CWNetwork>, iface: CWInterface) {
        var strongest: [String: Int] = [:]
        for network in networks {
            guard let ssid = network.ssid else { continue }
            strongest[ssid] = max(strongest[ssid] ?? .min, network.rssiValue)
        }
        let profiles = iface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        // 암호를 가져올 수 없는 배포판에서는 "macOS 저장 네트워크" 표시·가져오기를 모두 끈다
        knownToMac = Distribution.canImportMacPasswords ? Set(profiles.compactMap(\.ssid)) : []
        nearby = strongest.map { Nearby(ssid: $0.key, rssi: $0.value) }.sorted { $0.rssi > $1.rssi }
    }

    var linkState: LinkState {
        if !online { return .offline }
        return current != nil && current == hotspot ? .cellular : .wifi
    }

    private func recordHistory(now: Date) {
        // 잠자기 등으로 점검 간격이 길어진 구간은 끊김 시간에 넣지 않음
        let elapsed = min(now.timeIntervalSince(lastTickAt ?? now), checkInterval * 2)
        let switched = lastSSID != nil && current != nil && current != lastSSID
        history.record(linkState, at: now, elapsed: elapsed, switched: switched)
        lastTickAt = now
        if current != nil { lastSSID = current }
    }

    /// 연속으로 인터넷이 안 되는 네트워크는 잠시 후보에서 제외한다.
    private func recordHealth(now: Date) {
        guard let ssid = current else { return }
        if online {
            failures[ssid] = nil
            coolUntil[ssid] = nil
            // 안내는 30초 보여준 뒤 인터넷이 정상이면 지운다
            if status != nil, now.timeIntervalSince(statusAt) > 30 { status = nil }
        } else if now > graceUntil {
            failures[ssid, default: 0] += 1
            if failures[ssid, default: 0] >= failuresBeforeSwitch {
                failures[ssid] = nil
                coolUntil[ssid] = now + deadCooldown
                status = String(localized: "\(ssid) 인터넷 불통 — \(Int(deadCooldown / 60))분간 제외")
            } else {
                // 다음 정기 점검까지 기다리지 않고 2초 뒤 재확인 → 끊김 판정이 빨라짐
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await tick()
                }
            }
        }
    }

    @discardableResult
    private func join(_ ssid: String, among networks: Set<CWNetwork>, iface: CWInterface) async -> Bool {
        // iPhone 핫스팟은 macOS처럼 Instant Hotspot으로 연결 (암호·비콘 불필요). 안 되면 일반 연결 시도.
        // 화면 잠금·뚜껑 닫힘 중엔 macOS가 Instant Hotspot을 막으므로 바로 일반 연결(저장된 암호)로 간다.
        if ssid == hotspot, Distribution.supportsInstantHotspot, !InstantHotspot.blockedBySystem,
           await joinInstantHotspot(ssid, iface: iface) {
            return true
        }
        guard let network = networks.filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) else {
            return false
        }
        status = String(localized: "\(ssid) 연결 중…")
        var password = Keychain.password(for: ssid)
        if password == nil, ssid != hotspot, knownToMac.contains(ssid), !macPasswordTried.contains(ssid) {
            password = await importMacPassword(ssid)
        }
        let error: Error? = await Task.detached {
            do { try iface.associate(to: network, password: password); return nil } catch { return error }
        }.value
        let now = Date()
        if let error {
            coolUntil[ssid] = now + Self.joinFailCooldown
            status = String(localized: "\(ssid) 연결 실패: \(error.localizedDescription)")
            return false
        } else {
            graceUntil = now + Self.joinGrace
            current = iface.ssid()
            status = String(localized: "\(ssid) 연결됨")
            return true
        }
    }

    /// 신호를 안 내보내는 iPhone을 Wi-Fi 메뉴의 Personal Hotspot 항목으로 깨워 연결한다.
    private func joinInstantHotspot(_ ssid: String, iface: CWInterface) async -> Bool {
        guard InstantHotspot.ensureTrusted() else {
            coolUntil[ssid] = Date() + deadCooldown
            status = String(localized: "Instant Hotspot에 손쉬운 사용 권한 필요 (시스템 설정 > 개인정보 보호 > 손쉬운 사용)")
            return false
        }
        status = String(localized: "\(ssid) Instant Hotspot 연결 중…")
        guard await Task.detached(operation: { InstantHotspot.press(ssid) }).value else {
            coolUntil[ssid] = Date() + Self.hotspotRetry
            status = String(localized: "\(ssid) 근처에 없음")
            return false
        }
        for _ in 0..<80 where iface.ssid() != ssid { // iPhone 깨우고 연결까지 최대 20초
            try? await Task.sleep(for: .milliseconds(250))
        }
        current = iface.ssid()
        guard current == ssid else {
            coolUntil[ssid] = Date() + Self.hotspotRetry
            status = String(localized: "\(ssid) Instant Hotspot 연결 실패")
            return false
        }
        graceUntil = Date() + Self.joinGrace
        status = String(localized: "\(ssid) 연결됨 (Instant Hotspot)")
        return true
    }

    nonisolated private static func probe() async -> Bool {
        let request = URLRequest(
            url: URL(string: "https://captive.apple.com/hotspot-detect.html")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 3
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return false }
        return String(decoding: data, as: UTF8.self).contains("Success")
    }
}

struct Nearby: Identifiable, Equatable {
    let ssid: String
    let rssi: Int
    var id: String { ssid }

    /// 0~3칸 신호 세기
    var bars: Int {
        if rssi >= -60 { return 3 }
        if rssi >= -70 { return 2 }
        if rssi >= -80 { return 1 }
        return 0
    }
}
