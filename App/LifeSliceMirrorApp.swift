import SwiftUI

@main
struct LifeSliceMirrorApp: App {
    @StateObject private var director = SliceDirector()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.Key.language) private var language = "system"
    /// アプリを離れた時刻（戻ってきたとき、しばらく経っていたら鏡から始めるため）
    @State private var leftAt: Date?

    init() {
        // アプリスイッチャーのサムネイルに顔を残さない
        PrivacyShield.install()
    }

    var body: some Scene {
        WindowGroup {
            MirrorView()
                .environmentObject(director)
                .environmentObject(director.engine)
                .environmentObject(director.store)
                .environmentObject(director.reels)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
                .environment(\.locale, L10n.locale)
                // 言語を切り替えたら画面を作り直して、全部の文言を引き直す
                .id(language)
                .onAppear { director.setSceneActive(scenePhase == .active) }
                // ウィジェットから開かれたら鏡から
                .onOpenURL { url in
                    if url.scheme == MirrorLaunch.url.scheme { director.returnToMirror() }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                leftAt = Date()
            case .active:
                // ロック画面のボタンから開かれた／しばらく離れていた → 鏡から
                let idle = leftAt.map { Date().timeIntervalSince($0) > MirrorLaunch.idleReset } ?? false
                if MirrorLaunch.consumeRequest() || idle { director.returnToMirror() }
                leftAt = nil
            default:
                break
            }
            // 前面でなくなった瞬間に「立ち去りスライス」を確定してバッファを捨てる。
            director.setSceneActive(phase == .active)
        }
    }
}
