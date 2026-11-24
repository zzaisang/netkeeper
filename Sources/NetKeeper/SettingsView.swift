import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            NetworksTab().tabItem { Label("네트워크", systemImage: "list.number") }
            GeneralTab().tabItem { Label("일반", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 640)
    }
}

/// 우선순위 목록(Wi-Fi·셀룰러 공통): 드래그로 순서 변경, 선택한 항목의 셀룰러 표시·암호 변경·삭제.
private struct NetworksTab: View {
    @EnvironmentObject private var keeper: Keeper
    @State private var selection: String?
    @State private var newSSID = ""
    @State private var newPassword = ""
    @State private var changedPassword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("위에 있을수록 우선 연결합니다. 드래그하거나 항목 선택 후 ⌥↑/⌥↓로 순서를 바꾸세요. iPhone 아이콘은 iPhone 핫스팟(셀룰러 데이터)입니다.")
                .font(.callout).foregroundStyle(.secondary)

            List(selection: $selection) {
                // id를 SSID 자체로 둬야 이동 시 행이 통째로 다시 그려지지 않고 자연스럽게 움직인다
                ForEach(keeper.preferred, id: \.self) { ssid in
                    HStack {
                        Text("\((keeper.preferred.firstIndex(of: ssid) ?? 0) + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
                        NetworkKindIcon(ssid: ssid)
                        Text(ssid)
                        Spacer()
                        if let signal = keeper.signal(of: ssid) {
                            SignalBars(bars: signal.bars).help("\(signal.rssi) dBm")
                        } else {
                            Text("범위 밖").font(.caption).foregroundStyle(.tertiary)
                        }
                        if keeper.hasPassword(ssid) {
                            Image(systemName: "key.fill").foregroundStyle(.secondary).help("암호 저장됨")
                        }
                        if ssid == keeper.current {
                            Text("연결됨").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(ssid)
                }
                .onMove { from, to in
                    withAnimation { keeper.preferred.move(fromOffsets: from, toOffset: to) }
                }
            }
            .overlay {
                if keeper.preferred.isEmpty {
                    Text("선호 네트워크 없음 — 아래 주변 Wi-Fi에서 선택해 추가하세요.").foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 120)

            if let ssid = selection, let index = keeper.preferred.firstIndex(of: ssid) {
                HStack {
                    Button { withAnimation { keeper.move(index, by: -1) } } label: { Image(systemName: "arrow.up") }
                        .keyboardShortcut(.upArrow, modifiers: .option)
                        .disabled(index == 0)
                        .help("위로 (⌥↑)")
                    Button { withAnimation { keeper.move(index, by: 1) } } label: { Image(systemName: "arrow.down") }
                        .keyboardShortcut(.downArrow, modifiers: .option)
                        .disabled(index == keeper.preferred.count - 1)
                        .help("아래로 (⌥↓)")
                    Toggle("iPhone 핫스팟", isOn: Binding(get: { keeper.hotspot == ssid },
                                                 set: { _ in keeper.toggleCellular(ssid) }))
                        .help("iPhone 핫스팟이면 켜세요. 메뉴바 뱃지가 파랑으로 표시됩니다.")
                    Spacer()
                    Button("삭제", role: .destructive) {
                        keeper.remove(ssid)
                        selection = nil
                    }
                }
                HStack {
                    SecureField("\(ssid) 새 암호", text: $changedPassword)
                    Button("암호 변경") {
                        keeper.setPassword(changedPassword, for: ssid)
                        changedPassword = ""
                    }
                    .disabled(changedPassword.isEmpty)
                    if !keeper.hasPassword(ssid), keeper.knownToMac.contains(ssid), ssid != keeper.hotspot {
                        Button("macOS 암호 가져오기") { Task { await keeper.importMacPassword(ssid) } }
                            .help("macOS 시스템 키체인에서 가져옴 — 관리자 인증 필요")
                    }
                }
            }

            Divider()
            HStack {
                Text("주변 Wi-Fi").font(.headline)
                Spacer()
                Button {
                    Task { await keeper.tick(forceScan: true) }
                } label: { Label("다시 검색", systemImage: "arrow.clockwise") }
                Button("macOS Wi-Fi 설정 열기") { openWiFiSettings() }
            }
            List(keeper.nearby) { network in
                HStack {
                    SignalBars(bars: network.bars).help("\(network.rssi) dBm")
                    Text(network.ssid)
                    if keeper.knownToMac.contains(network.ssid) {
                        Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
                            .help("macOS에 저장된 네트워크 — 암호 입력 불필요")
                    }
                    if network.ssid == keeper.current {
                        Text("연결됨").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if keeper.priority.contains(network.ssid) {
                        Text("목록에 있음").font(.caption).foregroundStyle(.secondary)
                    } else {
                        // 기본 핫스팟 이름("…의 iPhone", "…'s iPad")에만 보인다. 그 외는 목록에서 토글로 지정.
                        if network.ssid.range(of: "iPhone|iPad", options: [.regularExpression, .caseInsensitive]) != nil {
                            Button("iPhone 핫스팟으로 추가") { keeper.setHotspot(network.ssid) }
                                .help("셀룰러 데이터를 쓰는 iPhone 핫스팟으로 표시해 목록 맨 뒤에 추가")
                        }
                        Button("선택") { newSSID = network.ssid }
                    }
                }
            }
            .overlay {
                if keeper.nearby.isEmpty {
                    Text("검색 결과 없음 — 위치 서비스 권한을 확인하세요.").foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 140)

            HStack {
                TextField("SSID", text: $newSSID)
                SecureField(macKnowsNewSSID ? "macOS 저장 암호 사용 (입력 불필요)" : "암호 (보안 네트워크 필수)" as LocalizedStringKey,
                            text: $newPassword)
                Button("추가") {
                    keeper.add(newSSID, password: newPassword)
                    newSSID = ""
                    newPassword = ""
                }
                .disabled(newSSID.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .task { await keeper.tick(forceScan: true) }
    }

    private var macKnowsNewSSID: Bool {
        keeper.knownToMac.contains(newSSID.trimmingCharacters(in: .whitespaces))
    }

    private func openWiFiSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject private var keeper: Keeper

    var body: some View {
        Form {
            Section {
                Toggle("자동 전환", isOn: $keeper.enabled)
                Toggle("로그인 시 실행", isOn: Binding(get: { keeper.launchAtLogin }, set: { keeper.launchAtLogin = $0 }))
                LanguagePicker()
            }
            Section("감시") {
                Picker("인터넷 확인 주기", selection: $keeper.checkInterval) {
                    ForEach([5.0, 10, 15, 30, 60], id: \.self) { Text("\(Int($0))초").tag($0) }
                }
                Picker("상위 네트워크 탐색 주기", selection: $keeper.scanInterval) {
                    ForEach([15.0, 30, 60, 120, 300], id: \.self) { Text("\(Int($0))초").tag($0) }
                }
                Stepper("연속 \(keeper.failuresBeforeSwitch)회 불통 시 전환",
                        value: $keeper.failuresBeforeSwitch, in: 1...5)
                Picker("불통 네트워크 제외 시간", selection: $keeper.deadCooldown) {
                    ForEach([60.0, 180, 300, 600, 1800], id: \.self) { Text("\(Int($0) / 60)분").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 앱 언어 선택. macOS는 실행 시점에 언어를 정하므로 바꾸면 다시 시작한다.
private struct LanguagePicker: View {
    /// 앱 자체 설정에 언어가 지정돼 있으면 그 값, 없으면 시스템 언어
    @State private var language = (UserDefaults.standard
        .persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first ?? "system"

    var body: some View {
        Picker("언어", selection: $language) {
            Text("시스템 설정 따름").tag("system")
            Text("한국어").tag("ko")
            Text("English").tag("en")
        }
        .onChange(of: language) { _, newValue in
            if newValue == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            }
            relaunch()
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
