import SwiftUI

/// 메뉴바 팝오버(시안 A): 상태 헤더 · 최근 60분 · 우선순위 · 하단 버튼.
struct MenuView: View {
    @EnvironmentObject private var keeper: Keeper
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let status = keeper.status {
                Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.top, -6)
            }
            Divider()
            HistorySection()
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("우선순위").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if keeper.priority.isEmpty {
                    Text("설정에서 선호 네트워크를 추가하세요.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    ForEach(Array(keeper.priority.enumerated()), id: \.element) { index, ssid in
                        NetworkRow(rank: index + 1, ssid: ssid)
                    }
                }
                if keeper.hotspot.isEmpty {
                    Text("iPhone 핫스팟 미지정 — 목록에서 우클릭해 지정하세요.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Button("새로고침") { Task { await keeper.tick(forceScan: true) } }
                    .keyboardShortcut("r")
                Button("설정…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(14)
        .frame(width: 300)
        .task {
            keeper.showCachedScan() // 즉시 표시
            await keeper.tick(forceScan: true) // 이어서 새로 스캔해 갱신
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9)
                .fill(tileColor)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(nsImage: MenuBarIcon.image(.none))
                        .renderingMode(.template)
                        .foregroundStyle(iconColor)
                }
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let current = keeper.current { Text(current) } else { Text("Wi-Fi 미연결") }
                }
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(subtitleColor)
            }
            Spacer()
            Toggle("자동", isOn: $keeper.enabled)
                .toggleStyle(.switch).controlSize(.mini)
                .font(.caption).foregroundStyle(.secondary)
                .help("자동 전환")
        }
    }

    private var subtitle: LocalizedStringKey {
        if !keeper.enabled { return "자동 전환 꺼짐" }
        switch keeper.linkState {
        case .wifi: return "온라인 · 정상"
        case .cellular: return "셀룰러 사용 중"
        case .offline: return "인터넷 끊김"
        }
    }

    private var subtitleColor: Color {
        switch keeper.linkState {
        case .wifi: .secondary
        case .cellular: LinkColors.cellular
        case .offline: LinkColors.offline
        }
    }

    private var tileColor: Color {
        if !keeper.enabled { return .gray }
        switch keeper.linkState {
        case .wifi: return Color(nsColor: .labelColor).opacity(0.85)
        case .cellular: return LinkColors.cellular
        case .offline: return LinkColors.offline
        }
    }

    /// 정상 타일은 라벨색(다크모드에서 밝음)이라 아이콘은 배경색으로 반전
    private var iconColor: Color {
        keeper.enabled && keeper.linkState == .wifi ? Color(nsColor: .windowBackgroundColor) : .white
    }
}

enum LinkColors {
    static let wifi = Color(red: 0x8C / 255, green: 0x96 / 255, blue: 0xA2 / 255)
    static let cellular = Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xD6 / 255)
    static let offline = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
}

/// 최근 60분 연결 막대 (1칸 = 1분)
private struct HistorySection: View {
    @EnvironmentObject private var keeper: Keeper

    var body: some View {
        let now = Date()
        let history = keeper.history
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("최근 60분")
                Spacer()
                Text("전환 \(history.switches(now: now))회 · 끊김 \(Self.duration(history.downSeconds(now: now)))")
            }
            .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 1) {
                ForEach(Array(history.slots(now: now).enumerated()), id: \.offset) { _, slot in
                    RoundedRectangle(cornerRadius: 1.5).fill(Self.color(slot))
                }
            }
            .frame(height: 16)
            .accessibilityElement()
            .accessibilityLabel("최근 60분 연결 기록")

            HStack(spacing: 10) {
                legend("Wi-Fi", LinkColors.wifi)
                legend("셀룰러", LinkColors.cellular)
                legend("끊김", LinkColors.offline)
                Spacer()
                Text("지금")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func legend(_ title: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }

    private static func color(_ slot: LinkState?) -> Color {
        switch slot {
        case .wifi: LinkColors.wifi
        case .cellular: LinkColors.cellular
        case .offline: LinkColors.offline
        case nil: Color.primary.opacity(0.07) // 기록 없음 (앱 꺼짐·잠자기)
        }
    }

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total < 60 ? String(localized: "\(total)초") : String(localized: "\(total / 60)분 \(total % 60)초")
    }
}

/// 팝오버의 네트워크 한 줄. 누르면 macOS Wi-Fi 메뉴처럼 그 네트워크로 바로 연결.
private struct NetworkRow: View {
    @EnvironmentObject private var keeper: Keeper
    @State private var hovering = false
    let rank: Int
    let ssid: String

    var body: some View {
        let isCurrent = ssid == keeper.current
        let signal = keeper.signal(of: ssid)
        Button {
            Task { await keeper.connectNow(ssid) }
        } label: {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
                NetworkKindIcon(ssid: ssid)
                Text(ssid)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if let signal {
                    SignalBars(bars: signal.bars).help("\(signal.rssi) dBm")
                } else {
                    Text(wakesByInstantHotspot ? "Instant Hotspot" : "범위 밖" as LocalizedStringKey)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1).fixedSize()
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isCurrent ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(
                    isCurrent ? Color.accentColor.opacity(0.12)
                        : hovering ? Color.primary.opacity(0.06) : .clear
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(signal == nil && !isCurrent && !wakesByInstantHotspot ? 0.5 : 1)
        .contextMenu { priorityMenu }
    }

    private var wakesByInstantHotspot: Bool { ssid == keeper.hotspot && Distribution.supportsInstantHotspot }

    /// 우클릭: 연결 없이 우선순위만 조정
    @ViewBuilder private var priorityMenu: some View {
        let index = rank - 1
        let last = keeper.preferred.count - 1
        Button("맨 위로") { keeper.move(index, by: -index) }.disabled(index == 0)
        Button("위로") { keeper.move(index, by: -1) }.disabled(index == 0)
        Button("아래로") { keeper.move(index, by: 1) }.disabled(index == last)
        Divider()
        Button(ssid == keeper.hotspot ? "iPhone 핫스팟 지정 해제" : "iPhone 핫스팟으로 지정" as LocalizedStringKey) { keeper.toggleCellular(ssid) }
    }
}

/// 팝오버 하단의 옅은 배경 버튼
private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .contentShape(Rectangle())
    }
}

/// Wi-Fi / 셀룰러(iPhone 핫스팟) 구분 아이콘
struct NetworkKindIcon: View {
    @EnvironmentObject private var keeper: Keeper
    let ssid: String

    var body: some View {
        let cellular = ssid == keeper.hotspot
        Image(systemName: cellular ? "iphone" : "wifi")
            .frame(width: 18)
            .foregroundStyle(cellular ? LinkColors.cellular : Color.secondary)
            .help(cellular ? "셀룰러 (iPhone 핫스팟)" : "Wi-Fi" as LocalizedStringKey)
    }
}

/// 0~3칸 신호 세기
struct SignalBars: View {
    let bars: Int

    var body: some View {
        Image(systemName: "cellularbars", variableValue: Double(bars) / 3)
            .foregroundStyle(.secondary)
    }
}
