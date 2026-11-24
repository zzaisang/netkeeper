import SwiftUI

@main
struct NetKeeperApp: App {
    @StateObject private var keeper = Keeper()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(keeper)
        } label: {
            Image(nsImage: MenuBarIcon.image(keeper.badge))
        }
        .menuBarExtraStyle(.window)

        // 메뉴바 전용(LSUIElement) 앱에서는 Settings 씬이 openSettings로 잘 안 열려 일반 Window 사용
        Window("NetKeeper 설정", id: "settings") {
            SettingsView().environmentObject(keeper)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
