import SwiftUI

@main
struct LifeSliceMirrorApp: App {
    @StateObject private var director = SliceDirector()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MirrorView()
                .environmentObject(director)
                .environmentObject(director.engine)
                .environmentObject(director.store)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
                .onAppear { director.setSceneActive(scenePhase == .active) }
        }
        .onChange(of: scenePhase) { _, phase in
            // 前面でなくなった瞬間に「立ち去りスライス」を確定してバッファを捨てる。
            director.setSceneActive(phase == .active)
        }
    }
}
