import Foundation

/// アプリ本体とウィジェットで共有する置き場所。
/// App Group が未設定でもアプリ本体は動くように、取れなければ通常のコンテナへフォールバックする。
enum AppGroup {
    /// ⚠️ 自分の Team で作った App Group ID に合わせて変更してください（entitlements も同じ値に）。
    static let identifier = "group.app.lifeslice.mirror"

    static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var widgetDirectory: URL? {
        guard let base = sharedContainer else { return nil }
        let dir = base.appendingPathComponent("widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var widgetStateURL: URL? { widgetDirectory?.appendingPathComponent("state.json") }
    static var widgetLatestImageURL: URL? { widgetDirectory?.appendingPathComponent("latest.jpg") }
}

/// ウィジェットに渡す最小限の状態。
struct WidgetState: Codable, Equatable {
    var count: Int = 0
    var lastDate: Date? = nil
    var reelThreshold: Int = 12

    static func load() -> WidgetState {
        guard let url = AppGroup.widgetStateURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data) else {
            return WidgetState()
        }
        return state
    }

    func save() {
        guard let url = AppGroup.widgetStateURL,
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// リール化まであと何枚か（0 ならもう作れる）。
    var remainingToReel: Int { max(0, reelThreshold - count) }
}
