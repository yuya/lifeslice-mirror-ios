import SwiftUI
import UIKit

/// リール（GIF / MP4）書き出しの選択肢ぜんぶ。
struct ReelOptions: Equatable {
    var format: Format = .gif
    var speed: Speed = .normal
    var size: Size = .small
    var aspect: Aspect = .portrait
    var filter: Filter = .none
    var colors: ColorDepth = .c256
    var dither: DitherMode = .pattern
    var stampFormat: StampFormat = .camcorder
    var stampFont: StampFont = .digital
    var stampStyle: StampStyle = .camcorder
    var stampLayout: StampLayout = .bottomRight

    enum Format: String, CaseIterable, Identifiable {
        case gif, mp4
        var id: String { rawValue }
        var label: String { self == .gif ? "GIF" : "MP4" }
        var fileExtension: String { rawValue }
    }

    enum Speed: Double, CaseIterable, Identifiable {
        case slow = 3, normal = 6, fast = 10, turbo = 15
        var id: Double { rawValue }
        var fps: Double { rawValue }
        var label: String {
            switch self {
            case .slow: return L("のんびり")
            case .normal: return L("ふつう")
            case .fast: return L("ぱらぱら")
            case .turbo: return L("高速")
            }
        }
    }

    enum Size: Int, CaseIterable, Identifiable {
        case tiny = 240, small = 360, medium = 480, large = 720
        var id: Int { rawValue }
        var width: Int { rawValue }
        var label: String { "\(rawValue)px" }
    }

    enum Aspect: String, CaseIterable, Identifiable {
        case portrait, classic, square
        var id: String { rawValue }
        var label: String {
            switch self {
            case .portrait: return "9:16"
            case .classic: return "3:4"
            case .square: return "1:1"
            }
        }
        /// 高さ ÷ 幅
        var ratio: Double {
            switch self {
            case .portrait: return 16.0 / 9.0
            case .classic: return 4.0 / 3.0
            case .square: return 1
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case none, instant, fade, chrome, transfer, mono, noir, sepia
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return L("そのまま")
            case .instant: return L("インスタント")
            case .fade: return L("色あせ")
            case .chrome: return L("こってり")
            case .transfer: return L("夕方")
            case .mono: return L("モノクロ")
            case .noir: return L("ノワール")
            case .sepia: return L("セピア")
            }
        }
        var ciFilterName: String? {
            switch self {
            case .none: return nil
            case .instant: return "CIPhotoEffectInstant"
            case .fade: return "CIPhotoEffectFade"
            case .chrome: return "CIPhotoEffectChrome"
            case .transfer: return "CIPhotoEffectTransfer"
            case .mono: return "CIPhotoEffectMono"
            case .noir: return "CIPhotoEffectNoir"
            case .sepia: return "CISepiaTone"
            }
        }
    }

    enum ColorDepth: String, CaseIterable, Identifiable {
        case full, c256, c64, c16, gameBoy, oneBit
        var id: String { rawValue }
        var label: String {
            switch self {
            case .full: return L("フルカラー")
            case .c256: return L("256色")
            case .c64: return L("64色")
            case .c16: return L("16色")
            case .gameBoy: return L("携帯ゲーム機")
            case .oneBit: return L("白黒2値")
            }
        }
        var adaptiveCount: Int? {
            switch self {
            case .c256: return 256
            case .c64: return 64
            case .c16: return 16
            default: return nil
            }
        }
    }

    enum StampFormat: String, CaseIterable, Identifiable {
        case none, camcorder, dotted, dateTime, english, japanese, weekdayTime, counter
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return L("なし")
            case .counter: return "#001"
            default: return text(for: Date(timeIntervalSince1970: 1_794_700_000), index: 0)
            }
        }

        func text(for date: Date, index: Int) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            switch self {
            case .none: return ""
            case .camcorder: f.dateFormat = "''yy MM dd"
            case .dotted: f.dateFormat = "yyyy.MM.dd"
            case .dateTime: f.dateFormat = "yyyy/MM/dd HH:mm"
            case .english: f.dateFormat = "MMM d, yyyy"
            case .japanese:
                f.locale = Locale(identifier: "ja_JP")
                f.dateFormat = "M月d日(E)"
            case .weekdayTime:
                f.dateFormat = "EEE HH:mm"
                return f.string(from: date).uppercased()
            case .counter:
                return String(format: "#%03d", index + 1)
            }
            return f.string(from: date)
        }
    }

    enum StampFont: String, CaseIterable, Identifiable {
        case digital, rounded, serif, mincho, typewriter, courier, marker, futura
        var id: String { rawValue }
        var label: String {
            switch self {
            case .digital: return L("デジタル")
            case .rounded: return L("まる")
            case .serif: return L("セリフ")
            case .mincho: return L("明朝")
            case .typewriter: return L("タイプ")
            case .courier: return L("クーリエ")
            case .marker: return L("マーカー")
            case .futura: return L("フーツラ")
            }
        }

        func uiFont(size: CGFloat) -> UIFont {
            func designed(_ design: UIFontDescriptor.SystemDesign, weight: UIFont.Weight) -> UIFont {
                let base = UIFont.systemFont(ofSize: size, weight: weight)
                if let descriptor = base.fontDescriptor.withDesign(design) {
                    return UIFont(descriptor: descriptor, size: size)
                }
                return base
            }
            func named(_ name: String) -> UIFont {
                UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
            }
            switch self {
            case .digital: return UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
            case .rounded: return designed(.rounded, weight: .heavy)
            case .serif: return designed(.serif, weight: .bold)
            case .mincho: return named("HiraMinProN-W6")
            case .typewriter: return named("AmericanTypewriter-Bold")
            case .courier: return named("Courier-Bold")
            case .marker: return named("MarkerFelt-Wide")
            case .futura: return named("Futura-CondensedExtraBold")
            }
        }
    }

    enum StampStyle: String, CaseIterable, Identifiable {
        case camcorder, white, subtitle, blackLabel, whiteLabel
        var id: String { rawValue }
        var label: String {
            switch self {
            case .camcorder: return L("ビデオカメラ")
            case .white: return L("白ぬき")
            case .subtitle: return L("字幕")
            case .blackLabel: return L("黒ラベル")
            case .whiteLabel: return L("白ラベル")
            }
        }
        var textColor: UIColor {
            switch self {
            case .camcorder: return UIColor(red: 1.0, green: 0.56, blue: 0.13, alpha: 1)
            case .white, .blackLabel: return .white
            case .subtitle: return UIColor(red: 1.0, green: 0.92, blue: 0.2, alpha: 1)
            case .whiteLabel: return UIColor(white: 0.08, alpha: 1)
            }
        }
        var labelColor: UIColor? {
            switch self {
            case .blackLabel: return UIColor(white: 0.05, alpha: 1)
            case .whiteLabel: return UIColor(white: 0.97, alpha: 1)
            default: return nil
            }
        }
        var outlineColor: UIColor? {
            switch self {
            case .camcorder: return UIColor(red: 0.25, green: 0.08, blue: 0, alpha: 0.9)
            case .white, .subtitle: return UIColor(white: 0, alpha: 0.85)
            default: return nil
            }
        }
    }

    enum StampLayout: String, CaseIterable, Identifiable {
        case bottomRight, bottomLeft, bottomCenter, topLeft, topRight, centerBig
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bottomRight: return L("右下")
            case .bottomLeft: return L("左下")
            case .bottomCenter: return L("下まんなか")
            case .topLeft: return L("左上")
            case .topRight: return L("右上")
            case .centerBig: return L("どーんと中央")
            }
        }
        var symbol: String {
            switch self {
            case .bottomRight: return "arrow.down.right"
            case .bottomLeft: return "arrow.down.left"
            case .bottomCenter: return "arrow.down"
            case .topLeft: return "arrow.up.left"
            case .topRight: return "arrow.up.right"
            case .centerBig: return "circle.circle"
            }
        }
    }

    /// 出力ピクセルサイズ（H.264 のために偶数へ丸める）。
    var pixelSize: (width: Int, height: Int) {
        let w = size.width
        let h = Int((Double(w) * aspect.ratio).rounded())
        return (w - w % 2, h - h % 2)
    }
}
