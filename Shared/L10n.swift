import Foundation

/// 日本語 / 英語の切り替え。
/// - 最初は iPhone の言語が日本語なら日本語、それ以外は英語
/// - iPhone の「設定 > アプリ > LifeSlice > 言語」でも、アプリ内の設定でも変えられる
/// コード中の文言は日本語で書き、英語は下の対応表から引く。
enum L10n {
    static let overrideKey = "app.language"

    /// いま使う言語コード（"ja" か "en"）。
    static var code: String {
        let chosen = UserDefaults.standard.string(forKey: overrideKey) ?? "system"
        if chosen == "ja" || chosen == "en" { return chosen }
        // OS 側のアプリ別言語設定は Bundle の優先ローカライズに反映される。
        let system: String?
        if Bundle.main.localizations.contains("ja") {
            system = Bundle.main.preferredLocalizations.first
        } else {
            system = Locale.preferredLanguages.first
        }
        return (system ?? "en").hasPrefix("ja") ? "ja" : "en"
    }

    /// 日付や数字の書式に使うロケール。
    static var locale: Locale {
        if Locale.current.language.languageCode?.identifier == code { return .current }
        return Locale(identifier: code == "ja" ? "ja_JP" : "en_US")
    }

    static let english: [String: String] = [
        "鏡": "Mirror",
        "相手から": "True view",
        "ゆるめ": "Loose",
        "ふつう": "Normal",
        "きびしめ": "Strict",
        "なし": "None",
        "あみ点": "Pattern",
        "ざらざら": "Grainy",
        "のんびり": "Slow",
        "ぱらぱら": "Flipbook",
        "高速": "Fast",
        "そのまま": "Original",
        "インスタント": "Instant",
        "色あせ": "Faded",
        "こってり": "Rich",
        "夕方": "Dusk",
        "モノクロ": "Mono",
        "ノワール": "Noir",
        "セピア": "Sepia",
        "フルカラー": "Full color",
        "256色": "256 colors",
        "64色": "64 colors",
        "16色": "16 colors",
        "携帯ゲーム機": "Handheld",
        "白黒2値": "1-bit",
        "デジタル": "Digital",
        "まる": "Rounded",
        "セリフ": "Serif",
        "明朝": "Mincho",
        "タイプ": "Typewriter",
        "クーリエ": "Courier",
        "マーカー": "Marker",
        "フーツラ": "Futura",
        "ビデオカメラ": "Camcorder",
        "白ぬき": "White",
        "字幕": "Subtitle",
        "黒ラベル": "Black label",
        "白ラベル": "White label",
        "右下": "Bottom right",
        "左下": "Bottom left",
        "下まんなか": "Bottom center",
        "左上": "Top left",
        "右上": "Top right",
        "どーんと中央": "Big center",
        "シャッター": "Shutter",
        "静止を検知": "Stillness",
        "立ち去り際のどこか 1 コマ": "A random frame from before you left",
        "ロック中に撮影": "Taken while locked",
        "%@・ぴったりその瞬間": "%@ · that exact moment",
        "%@の %@ 秒前": "%2$@ s before · %1$@",
        "%@の %@ 秒後": "%2$@ s after · %1$@",
        "スライス": "Slices",
        "鏡にもどる": "Back to mirror",
        "もう十分たまってます。ぱらぱら動かしてみましょう。": "You've got plenty. Let's make them move.",
        "リールにする": "Make a reel",
        "あと %d 枚でリールが作れます。鏡を見るたびに勝手にたまります。": "%d more to go before you can make a reel. They pile up every time you check the mirror.",
        "これまでのリール": "Past reels",
        "まだ 1 枚もありません": "No slices yet",
        "いつもどおり鏡として使ってください。\n止まった瞬間の前後から、こっそり 1 コマもらいます。": "Just use it as a mirror.\nWhen you hold still, it quietly keeps one frame from around that moment.",
        "共有": "Share",
        "捨てる": "Discard",
        "このスライスを捨てますか？": "Discard this slice?",
        "カメラが使えません": "Can't use the camera",
        "鏡になるにはカメラへのアクセスが必要です。": "Camera access is needed to work as a mirror.",
        "設定をひらく": "Open Settings",
        "インカメラが見つかりません": "No front camera found",
        "シミュレータでは鏡は映りません。実機で試してください。": "The mirror doesn't work in the simulator. Try it on a real iPhone.",
        "とめています": "Paused",
        "左右の切り替え、いまは%@": "Flip left and right, now %@",
        "初期値に戻す": "Reset to default",
        "スライス一覧、%d 枚": "Slices, %d",
        "%d コマ・%@": "%d frames · %@",
        "保存済み": "Saved",
        "写真に保存": "Save to Photos",
        "このリールを捨てますか？": "Discard this reel?",
        "直近30枚": "Last 30",
        "直近100枚": "Last 100",
        "月でえらぶ": "By month",
        "期間でえらぶ": "By dates",
        "ぜんぶ": "All",
        "%@（%d）": "%@ (%d)",
        "色数": "Colors",
        "ディザ（色のまぜ方）": "Dither",
        "フィルタ": "Filter",
        "日付の書き方": "Date format",
        "フォント": "Font",
        "日付の色": "Date style",
        "日付の位置": "Date position",
        "はやさ": "Speed",
        "かたち": "Shape",
        "大きさ（小さいほど軽くてチープ）": "Size (smaller is lighter and cheaper-looking)",
        "形式": "Format",
        "リール": "Reel",
        "書き出せませんでした": "Couldn't export",
        "どこからどこまで": "Range",
        "どの月": "Which month",
        "この日から": "From",
        "この日まで": "To",
        "この範囲にスライスがありません": "No slices in this range",
        "プレビューは直近 %d コマ": "Preview shows the last %d frames",
        "書き出し中…": "Exporting…",
        "%d コマを %@ にする": "Export %d frames as %@",
        "できました": "Done",
        "シェアする": "Share",
        "このリールは一覧の「これまでのリール」にも残っています。": "This reel is also kept under “Past reels” in the slice list.",
        "「%@」に保存しました": "Saved to “%@”",
        "保存できませんでした（写真へのアクセスを確認）": "Couldn't save (check Photos access)",
        "振り幅ゼロ。止まった瞬間がそのまま残ります。": "No randomness. You get the exact moment you hold still.",
        "止まった瞬間の %.1f 秒前 〜 %.1f 秒後のどこか 1 コマが残ります。どれになるかは毎回くじ引きです。": "Keeps one frame from somewhere between %.1f s before and %.1f s after the moment you hold still. Which one is a lottery every time.",
        "%d分": "%d min",
        "%d秒": "%d s",
        "前": "Before",
        "−%.1f 秒": "−%.1f s",
        "後": "After",
        "＋%.1f 秒": "+%.1f s",
        "不意打ちの振り幅": "Surprise window",
        "止まったら自動で撮る": "Capture when I hold still",
        "止まった判定": "Stillness sensitivity",
        "次に撮るまでの間隔": "Wait before the next one",
        "止まらなくても 1 枚もらう": "Keep one even if I don't hold still",
        "勝手にたまる仕組み": "How slices pile up",
        "顔が映った状態で手が止まると自動で撮ります。一度も撮れないまま閉じたときは、開いていた間の映像から適当に 1 コマだけ残します。真っ暗に近いコマは残しません。残さなかった映像はその場で捨てています。": "Captures automatically when your face is in view and your hand holds still. If nothing was captured before you leave, it keeps one random frame from the time the mirror was open. Frames that are almost pitch dark are never kept. Everything else is thrown away on the spot.",
        "写真アプリにも保存": "Also save to Photos",
        "保存": "Saving",
        "スライスはいつもアプリの中に残ります。オンにすると、写真アプリの「%@」アルバムにも同じものを入れます。": "Slices always stay inside the app. Turn this on to also add them to the “%@” album in Photos.",
        "撮れたことを知らせない": "Don't tell me when it captures",
        "ふだんは撮れた瞬間に画面が一瞬白く光ります。": "Normally the screen flashes white for a moment when a slice is captured.",
        "%d 枚たまったら": "After %d slices",
        "リールが作れるようになる枚数": "Slices needed to make a reel",
        "残す本数": "Reels to keep",
        "%d 本": "%d",
        "リールの履歴": "Reel history",
        "書き出したリールをアプリ内に残します。本数を超えたぶんと、合計が %@ を超えたぶんは古い順に消えます。いまは %d 本・%@ です。": "Exported reels are kept inside the app. The oldest are removed once you pass this number, or once the total passes %@. Right now: %d reels, %@.",
        "言語": "Language",
        "iPhone の設定に合わせる": "Follow iPhone settings",
        "iPhone の設定アプリで変える": "Change in the Settings app",
        "ウィジェットとロック画面の表示は iPhone の設定に従います。": "Widgets and the Lock Screen follow your iPhone settings.",
        "開発用": "Developer",
        "ダミーのスライスを 24 枚つくる": "Create 24 dummy slices",
        "設定": "Settings",
        "閉じる": "Done",
        "写真へのアクセスが許可されていません": "Photos access is not allowed",
        "設定アプリで写真へのアクセスを許可すると使えます。": "Allow Photos access in the Settings app to use this.",
        "さっきの自分": "Latest slice",
        "いちばん新しいスライスを表示します。タップで鏡がひらきます。": "Shows your newest slice. Tap to open the mirror.",
        "リールが作れます": "Ready for a reel",
        "リールまであと %d": "%d to go for a reel",
        "スライスの数": "Slice count",
        "たまった枚数と、リールまでの残り。タップで鏡がひらきます。": "How many slices you have and how many to go. Tap to open the mirror.",
        "線画アイコン": "Line icon",
        "アイコンだけのシンプルな入口。タップで鏡がひらきます。": "Just the icon. Tap to open the mirror.",
        "範囲": "Range",
        "日付": "Date",
        "出力": "Output",
        "見本は、えらんだ範囲のいちばん新しいスライスで作っています。": "Samples use the newest slice in the selected range.",
    ]
}

/// 文言を引く。`L("あと %d 枚", 3)` のように書式つきでも使える。
func L(_ key: String, _ args: CVarArg...) -> String {
    let base = L10n.code == "ja" ? key : (L10n.english[key] ?? key)
    guard !args.isEmpty else { return base }
    return String(format: base, locale: L10n.locale, arguments: args)
}
