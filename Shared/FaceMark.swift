import SwiftUI

/// アプリアイコンと同じ線画の顔。ウィジェットなど、色を持たない場所で使う。
/// `FaceMark().stroke(style: FaceMark.strokeStyle(for: 幅))` のように線で描く。
struct FaceMark: Shape {
    /// 元の図面（1024×1024）のうち、顔が収まっている範囲。
    private static let bounds = CGRect(x: 216, y: 130, width: 614, height: 752)

    static func strokeStyle(for side: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: max(1.5, side * 0.05), lineCap: .round, lineJoin: .round)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        // 輪郭（右上は閉じない）
        path.move(to: p(640, 182))
        path.addCurve(to: p(246, 520), control1: p(430, 130), control2: p(236, 290))
        path.addCurve(to: p(548, 852), control1: p(254, 716), control2: p(392, 856))
        path.addCurve(to: p(800, 590), control1: p(690, 848), control2: p(790, 740))
        // 眉から鼻
        path.move(to: p(706, 330))
        path.addCurve(to: p(548, 400), control1: p(630, 300), control2: p(566, 330))
        path.addCurve(to: p(474, 600), control1: p(534, 470), control2: p(520, 540))
        path.addCurve(to: p(580, 612), control1: p(500, 628), control2: p(548, 630))
        // 左目（開）と瞳
        path.move(to: p(350, 440))
        path.addCurve(to: p(454, 440), control1: p(380, 410), control2: p(428, 410))
        path.addEllipse(in: CGRect(x: 396, y: 480, width: 12, height: 12))
        // 右目（つむった瞬間）
        path.move(to: p(632, 446))
        path.addCurve(to: p(730, 446), control1: p(662, 474), control2: p(704, 474))
        // 口
        path.move(to: p(430, 712))
        path.addCurve(to: p(646, 700), control1: p(500, 756), control2: p(590, 752))

        // rect の中央に、縦横比を保って収める
        let b = Self.bounds
        let scale = min(rect.width / b.width, rect.height / b.height)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -b.midX, y: -b.midY)
        return path.applying(transform)
    }
}
