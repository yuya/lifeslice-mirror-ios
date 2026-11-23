import AppIntents
import Foundation

/// 「鏡の画面から始める」ための合図。
/// ホーム画面のウィジェット・ロック画面のボタン・URL から開かれたときと、
/// アプリを離れてしばらく経ってから戻ってきたときは、一覧やリールを閉じて鏡に戻す。
enum MirrorLaunch {
    /// ウィジェットなどに付ける URL（lifeslice://mirror）
    static let url = URL(string: "lifeslice://mirror")!
    /// これより長くアプリを離れていたら、戻ってきたとき鏡から始める
    static let idleReset: TimeInterval = 60

    private static let key = "launch.mirrorRequestedAt"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    /// ボタン（コントロール）から開かれた、と書き残す。ウィジェット側のプロセスから呼ばれることもある。
    static func request() {
        defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    /// 直近（10 秒以内）にボタンから開かれていたら true を返し、合図を消す。
    static func consumeRequest() -> Bool {
        let at = defaults.double(forKey: key)
        guard at > 0 else { return false }
        defaults.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - at < 10
    }
}

/// ロック画面の下・コントロールセンターのボタン用。アプリを開いて鏡から始める。
struct OpenMirrorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Mirror"
    static let description = IntentDescription("Opens LifeSlice Mirror for a quick face check.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MirrorLaunch.request()
        return .result()
    }
}
