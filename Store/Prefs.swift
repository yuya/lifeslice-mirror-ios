import Foundation

/// 設定のキーと初期値。SwiftUI 側は @AppStorage、ロジック側は Prefs.xxx で読む。
enum Prefs {
    enum Key {
        static let preWindow = "surprise.pre"            // 止まった瞬間より前の振り幅（秒）
        static let postWindow = "surprise.post"          // 止まった瞬間より後の振り幅（秒）
        static let slicing = "slicing.enabled"           // スライスを集めるか（オフ＝ただの鏡）
        static let backgroundBlur = "mirror.blur"        // 背景ぼかし
        static let autoSlice = "auto.still"              // 静止を検知して自動で撮る
        static let driftSlice = "auto.drift"             // 静止しなかったら立ち去り際に 1 コマ
        static let cooldown = "auto.cooldown"            // 自動スライスの最短間隔（秒）
        static let sensitivity = "auto.sensitivity"
        static let candidBias = "auto.candid"            // 隙のある顔を選びやすくする度合い
        static let saveToPhotos = "photos.autosave"
        static let quietMode = "ui.quiet"                // 撮れたことを知らせない
        static let reelThreshold = "reel.threshold"
        static let reelHistory = "reel.history"          // 書き出したリールを何本まで残すか
        static let lastReelOptions = "reel.lastOptions"  // 前回書き出したときの設定（JSON）
        static let lastReelRange = "reel.lastRange"
        static let language = "app.language"             // "system" / "ja" / "en"
    }

    static let defaults: [String: Any] = [
        Key.preWindow: 3.0,
        Key.postWindow: 3.0,
        Key.slicing: true,
        Key.backgroundBlur: false,
        Key.autoSlice: true,
        Key.driftSlice: true,
        Key.cooldown: 30.0,
        Key.sensitivity: 1,
        Key.candidBias: 2,
        Key.saveToPhotos: false,
        Key.quietMode: false,
        Key.reelThreshold: 12,
        Key.reelHistory: 8,
    ]

    /// 振り幅スライダーの上限（秒）。
    static let windowLimit: Double = 5

    /// リール履歴の本数の選択肢。合計サイズの上限は ReelArchive 側で別に持つ。
    static let reelHistoryChoices = [3, 5, 8]

    /// 「次に撮るまで」の選択肢（秒）。
    static let cooldownChoices: [Double] = [5, 15, 30, 45, 60]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
        // 以前の選択肢（10 秒・5 分）が残っていたら既定値に戻す。
        if !cooldownChoices.contains(UserDefaults.standard.double(forKey: Key.cooldown)) {
            UserDefaults.standard.set(30.0, forKey: Key.cooldown)
        }
    }

    private static var ud: UserDefaults { .standard }
    static var preWindow: Double { ud.double(forKey: Key.preWindow) }
    static var postWindow: Double { ud.double(forKey: Key.postWindow) }
    static var slicing: Bool { ud.bool(forKey: Key.slicing) }
    static var autoSlice: Bool { ud.bool(forKey: Key.autoSlice) }
    static var driftSlice: Bool { ud.bool(forKey: Key.driftSlice) }
    static var cooldown: Double { ud.double(forKey: Key.cooldown) }
    static var sensitivity: Int { ud.integer(forKey: Key.sensitivity) }
    static var candidBias: Int { ud.integer(forKey: Key.candidBias) }
    static var saveToPhotos: Bool { ud.bool(forKey: Key.saveToPhotos) }
    static var quietMode: Bool { ud.bool(forKey: Key.quietMode) }
    static var reelThreshold: Int { max(2, ud.integer(forKey: Key.reelThreshold)) }
    static var reelHistory: Int {
        let value = ud.integer(forKey: Key.reelHistory)
        return reelHistoryChoices.contains(value) ? value : 8
    }
}
