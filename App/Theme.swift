import SwiftUI
import UIKit

/// 見た目の共通部品。ガラス表現（iOS 26）はここに集約してある。
enum Theme {
    /// 朱色。アプリ全体でアクセントはこの 1 色だけ。
    static let accent = Color(red: 0.94, green: 0.36, blue: 0.24)
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let ink = Color(red: 0.09, green: 0.085, blue: 0.08)
    static let card = Color(white: 0.13)
}

extension View {
    /// パネル用のガラス。
    func glassPanel(cornerRadius: CGFloat = 26) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// 丸ボタン用のガラス（押すと反応する）。
    func glassButton() -> some View {
        glassEffect(.regular.interactive(), in: .circle)
    }

    /// カプセル用のガラス。
    func glassCapsule() -> some View {
        glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// 鏡画面の丸いツールボタン。
struct ToolButton: View {
    let symbol: String
    var text: String? = nil
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let text {
                    Text(text).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                } else {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(isOn ? Theme.accent : .white)
            .frame(width: 48, height: 48)
            .glassButton()
            // 絵柄だけでなく丸全体を押せるようにする
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

/// 幅に収まらないぶんは次の行へ折り返す並べ方。選択肢を 1 つも隠さないために使う。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 1 つ選ぶチップの集まり。横スクロールで隠さず、入りきらないぶんは折り返して全部見せる。
struct ChipRow<Item: Identifiable & Equatable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    let selected = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(label(item))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Theme.ink : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selected ? Theme.paper : Theme.card, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

// MARK: - 鏡へ戻る導線

private struct ReturnToMirrorKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// 一覧やリール作りの奥からでも、一気に鏡の画面まで戻るための合図。
    var returnToMirror: () -> Void {
        get { self[ReturnToMirrorKey.self] }
        set { self[ReturnToMirrorKey.self] = newValue }
    }
}

/// スライスのサムネイル（必要な大きさだけ読んでキャッシュ）。
struct SliceThumb: View {
    let slice: Slice
    let url: URL
    var maxPixel = 360
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.card
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: slice.id) {
            if let cached = ThumbnailCache.shared.image(for: slice.id) {
                image = cached
                return
            }
            let target = url
            let pixels = maxPixel
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let cg = ImageLoader.downsampled(url: target, maxPixel: pixels) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            if let loaded {
                ThumbnailCache.shared.set(loaded, for: slice.id)
                image = loaded
            }
        }
    }
}

enum ScreenLight {
    private static var saved: CGFloat?

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// ライト＝画面の明るさを最大にするだけ（映像には何も重ねない）。消したら元に戻す。
    static func set(on: Bool) {
        guard let screen else { return }
        if on {
            if saved == nil { saved = screen.brightness }
            screen.brightness = 1
        } else if let previous = saved {
            screen.brightness = previous
            saved = nil
        }
    }
}
