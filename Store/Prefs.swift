import Foundation

/// 設定のキーと初期値。SwiftUI 側は @AppStorage、ロジック側は Prefs.xxx で読む。
enum Prefs {
    enum Key {
        static let preWindow = "surprise.pre"            // シャッター前の振り幅（秒）
        static let postWindow = "surprise.post"          // シャッター後の振り幅（秒）
        static let autoSlice = "auto.still"              // 静止を検知して自動で撮る
        static let driftSlice = "auto.drift"             // 静止しなかったら立ち去り際に 1 コマ
        static let cooldown = "auto.cooldown"            // 自動スライスの最短間隔（秒）
        static let sensitivity = "auto.sensitivity"
        static let saveToPhotos = "photos.autosave"
        static let quietMode = "ui.quiet"                // 撮れたことを知らせない
        static let showGuides = "ui.guides"
        static let reelThreshold = "reel.threshold"
    }

    static let defaults: [String: Any] = [
        Key.preWindow: 1.5,
        Key.postWindow: 1.5,
        Key.autoSlice: true,
        Key.driftSlice: true,
        Key.cooldown: 30.0,
        Key.sensitivity: 1,
        Key.saveToPhotos: false,
        Key.quietMode: false,
        Key.showGuides: false,
        Key.reelThreshold: 12,
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }

    private static var ud: UserDefaults { .standard }
    static var preWindow: Double { ud.double(forKey: Key.preWindow) }
    static var postWindow: Double { ud.double(forKey: Key.postWindow) }
    static var autoSlice: Bool { ud.bool(forKey: Key.autoSlice) }
    static var driftSlice: Bool { ud.bool(forKey: Key.driftSlice) }
    static var cooldown: Double { ud.double(forKey: Key.cooldown) }
    static var sensitivity: Int { ud.integer(forKey: Key.sensitivity) }
    static var saveToPhotos: Bool { ud.bool(forKey: Key.saveToPhotos) }
    static var quietMode: Bool { ud.bool(forKey: Key.quietMode) }
    static var reelThreshold: Int { max(2, ud.integer(forKey: Key.reelThreshold)) }
}
