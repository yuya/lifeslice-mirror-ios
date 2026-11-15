import SwiftUI

@main
struct LifeSliceMirrorApp: App {
    @StateObject private var director = SliceDirector()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.Key.language) private var language = "system"

    var body: some Scene {
        WindowGroup {
            MirrorView()
                .environmentObject(director)
                .environmentObject(director.engine)
                .environmentObject(director.store)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
                .environment(\.locale, L10n.locale)
                // 言語を切り替えたら画面を作り直して、全部の文言を引き直す
                .id(language)
                .onAppear { director.setSceneActive(scenePhase == .active) }
        }
        .onChange(of: scenePhase) { _, phase in
            // 前面でなくなった瞬間に「立ち去りスライス」を確定してバッファを捨てる。
            director.setSceneActive(phase == .active)
        }
    }
}
