import AppIntents

/// カメラコントロール / ロック画面 / コントロールセンターから鏡を開くためのインテント。
/// アプリ本体・ウィジェット拡張・キャプチャ拡張の 3 ターゲットすべてに含める必要がある。
struct MirrorAppContext: Codable, Sendable {}

struct MirrorCaptureIntent: CameraCaptureIntent {
    typealias AppContext = MirrorAppContext

    static let title: LocalizedStringResource = "Open Mirror"
    static let description = IntentDescription("Opens LifeSlice Mirror for a quick face check.")

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
