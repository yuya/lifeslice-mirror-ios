import UIKit

/// アプリが前面でなくなった瞬間に画面を真っ黒で覆う。
/// アプリスイッチャー（最近使ったアプリの一覧）のサムネイルに顔が残らないようにするため。
/// ウインドウに直接かぶせるので、シートやフルスクリーン表示の上にも乗る。
enum PrivacyShield {
    private static let tag = 730_115
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            PrivacyShield.set(covered: true)
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            PrivacyShield.set(covered: false)
        }
    }

    static func set(covered: Bool) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if covered {
                    guard window.viewWithTag(tag) == nil else { continue }
                    let cover = UIView(frame: window.bounds)
                    cover.tag = tag
                    cover.backgroundColor = .black
                    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    window.addSubview(cover)
                } else {
                    window.viewWithTag(tag)?.removeFromSuperview()
                }
            }
        }
    }
}
