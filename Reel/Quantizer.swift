import Foundation

/// GIF らしいチープさを作る減色まわり。UIKit に依存しない素の Swift。
/// - 全フレーム共通のパレットを中央値分割（median cut）で作る → コマ間で色がチラつかない
/// - 15bit(32×32×32) の逆引き表で「いちばん近いパレット色」を O(1) で引く
/// - ディザ：なし / パターン（Bayer 4×4）/ 拡散（Floyd–Steinberg）
struct RGB: Equatable {
    var r: UInt8, g: UInt8, b: UInt8
}

enum DitherMode: String, CaseIterable, Identifiable {
    case none, pattern, diffusion
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "なし"
        case .pattern: return "あみ点"
        case .diffusion: return "ざらざら"
        }
    }
}

struct QuantPalette {
    /// 近さを測るときに使う色
    var match: [RGB]
    /// 実際に塗る色（ゲームボーイ風のように、測る色と塗る色が違う場合がある）
    var display: [RGB]
    /// 先にグレースケール化してから当てはめるか
    var grayscaleFirst: Bool = false
    /// 15bit RGB → パレット番号
    private(set) var lut: [UInt8] = []

    init(colors: [RGB]) {
        match = colors
        display = colors
        buildLUT()
    }

    init(match: [RGB], display: [RGB], grayscaleFirst: Bool) {
        self.match = match
        self.display = display
        self.grayscaleFirst = grayscaleFirst
        buildLUT()
    }

    private mutating func buildLUT() {
        var table = [UInt8](repeating: 0, count: 32768)
        let colors = match
        guard !colors.isEmpty else { lut = table; return }
        for index in 0..<32768 {
            let r = Int((index >> 10) & 31) * 8 + 4
            let g = Int((index >> 5) & 31) * 8 + 4
            let b = Int(index & 31) * 8 + 4
            var best = 0
            var bestDistance = Int.max
            for (i, c) in colors.enumerated() {
                let dr = r - Int(c.r), dg = g - Int(c.g), db = b - Int(c.b)
                // 人の目は緑に敏感なので少し重みをつける
                let d = dr * dr * 3 + dg * dg * 5 + db * db * 2
                if d < bestDistance { bestDistance = d; best = i }
            }
            table[index] = UInt8(best)
        }
        lut = table
    }

    /// ゲームボーイっぽい 4 階調の緑。
    static let gameBoy = QuantPalette(
        match: [RGB(r: 20, g: 20, b: 20), RGB(r: 95, g: 95, b: 95), RGB(r: 170, g: 170, b: 170), RGB(r: 240, g: 240, b: 240)],
        display: [RGB(r: 15, g: 56, b: 15), RGB(r: 48, g: 98, b: 48), RGB(r: 139, g: 172, b: 15), RGB(r: 155, g: 188, b: 15)],
        grayscaleFirst: true)

    /// 白黒 2 値。
    static let oneBit = QuantPalette(
        match: [RGB(r: 0, g: 0, b: 0), RGB(r: 255, g: 255, b: 255)],
        display: [RGB(r: 24, g: 22, b: 20), RGB(r: 246, g: 242, b: 232)],
        grayscaleFirst: true)
}

enum Quantizer {
    // MARK: パレット作成（median cut）

    /// RGBA8 のフレーム群から `count` 色のパレットを作る。
    static func buildPalette(frames: [[UInt8]], count: Int) -> QuantPalette {
        var histogram = [Int](repeating: 0, count: 32768)
        for frame in frames {
            frame.withUnsafeBufferPointer { p in
                var i = 0
                let n = p.count - 3
                while i < n {
                    let key = (Int(p[i]) >> 3) << 10 | (Int(p[i + 1]) >> 3) << 5 | (Int(p[i + 2]) >> 3)
                    histogram[key] += 1
                    i += 4
                }
            }
        }

        struct Bin { var r: Int; var g: Int; var b: Int; var n: Int }
        var bins: [Bin] = []
        bins.reserveCapacity(4096)
        for key in 0..<32768 where histogram[key] > 0 {
            bins.append(Bin(r: (key >> 10) & 31, g: (key >> 5) & 31, b: key & 31, n: histogram[key]))
        }
        guard !bins.isEmpty else { return QuantPalette(colors: [RGB(r: 0, g: 0, b: 0)]) }

        var boxes: [[Bin]] = [bins]
        while boxes.count < count {
            // いちばん「色の幅 × 画素数」が大きい箱を割る
            var target = -1
            var bestScore = -1.0
            var bestAxis = 0
            for (i, box) in boxes.enumerated() where box.count > 1 {
                var minR = 31, maxR = 0, minG = 31, maxG = 0, minB = 31, maxB = 0, total = 0
                for bin in box {
                    minR = min(minR, bin.r); maxR = max(maxR, bin.r)
                    minG = min(minG, bin.g); maxG = max(maxG, bin.g)
                    minB = min(minB, bin.b); maxB = max(maxB, bin.b)
                    total += bin.n
                }
                let ranges = [maxR - minR, maxG - minG, maxB - minB]
                let axis = ranges.firstIndex(of: ranges.max() ?? 0) ?? 0
                let score = Double(ranges[axis] + 1) * Double(total).squareRoot()
                if score > bestScore { bestScore = score; target = i; bestAxis = axis }
            }
            guard target >= 0 else { break }

            var box = boxes[target]
            switch bestAxis {
            case 0: box.sort { $0.r < $1.r }
            case 1: box.sort { $0.g < $1.g }
            default: box.sort { $0.b < $1.b }
            }
            let total = box.reduce(0) { $0 + $1.n }
            var running = 0
            var cut = 1
            for (i, bin) in box.enumerated() {
                running += bin.n
                if running * 2 >= total { cut = i + 1; break }
            }
            cut = min(max(1, cut), box.count - 1)
            boxes[target] = Array(box[..<cut])
            boxes.append(Array(box[cut...]))
        }

        let colors: [RGB] = boxes.map { box in
            var r = 0, g = 0, b = 0, n = 0
            for bin in box {
                r += (bin.r * 8 + 4) * bin.n
                g += (bin.g * 8 + 4) * bin.n
                b += (bin.b * 8 + 4) * bin.n
                n += bin.n
            }
            n = max(n, 1)
            return RGB(r: UInt8(min(255, r / n)), g: UInt8(min(255, g / n)), b: UInt8(min(255, b / n)))
        }
        return QuantPalette(colors: colors)
    }

    // MARK: 適用

    private static let bayer: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    /// RGBA8 の 1 フレームをパレットに当てはめる（その場で書き換え）。
    static func apply(_ pixels: inout [UInt8], width: Int, height: Int,
                      palette: QuantPalette, dither: DitherMode) {
        guard width > 0, height > 0, pixels.count >= width * height * 4, !palette.lut.isEmpty else { return }
        let gray = palette.grayscaleFirst
        // 色数が少ないほど強くディザをかける
        let levels = max(2.0, Double(palette.match.count).squareRoot() * (gray ? 2 : 1))
        let spread = Int(min(96.0, 255.0 / levels * 1.2))

        @inline(__always) func clamp(_ v: Int) -> Int { v < 0 ? 0 : (v > 255 ? 255 : v) }

        palette.lut.withUnsafeBufferPointer { lut in
            palette.display.withUnsafeBufferPointer { display in
                palette.match.withUnsafeBufferPointer { match in
                    pixels.withUnsafeMutableBufferPointer { p in
                        switch dither {
                        case .none, .pattern:
                            let usePattern = dither == .pattern
                            for y in 0..<height {
                                for x in 0..<width {
                                    let i = (y * width + x) * 4
                                    var r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
                                    if gray {
                                        let l = (r * 77 + g * 150 + b * 29) >> 8
                                        r = l; g = l; b = l
                                    }
                                    if usePattern {
                                        let t = (bayer[(y & 3) * 4 + (x & 3)] * 2 - 15) * spread / 32
                                        r = clamp(r + t); g = clamp(g + t); b = clamp(b + t)
                                    }
                                    let c = display[Int(lut[(r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)])]
                                    p[i] = c.r; p[i + 1] = c.g; p[i + 2] = c.b
                                }
                            }
                        case .diffusion:
                            // Floyd–Steinberg。誤差は 2 行ぶんだけ持つ。
                            var current = [Int](repeating: 0, count: (width + 2) * 3)
                            var next = [Int](repeating: 0, count: (width + 2) * 3)
                            for y in 0..<height {
                                for x in 0..<width {
                                    let i = (y * width + x) * 4
                                    let e = (x + 1) * 3
                                    var r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
                                    if gray {
                                        let l = (r * 77 + g * 150 + b * 29) >> 8
                                        r = l; g = l; b = l
                                    }
                                    r = clamp(r + current[e] / 16)
                                    g = clamp(g + current[e + 1] / 16)
                                    b = clamp(b + current[e + 2] / 16)
                                    let index = Int(lut[(r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)])
                                    let m = match[index]
                                    let c = display[index]
                                    p[i] = c.r; p[i + 1] = c.g; p[i + 2] = c.b
                                    let er = r - Int(m.r), eg = g - Int(m.g), eb = b - Int(m.b)
                                    current[e + 3] += er * 7; current[e + 4] += eg * 7; current[e + 5] += eb * 7
                                    next[e - 3] += er * 3; next[e - 2] += eg * 3; next[e - 1] += eb * 3
                                    next[e] += er * 5; next[e + 1] += eg * 5; next[e + 2] += eb * 5
                                    next[e + 3] += er; next[e + 4] += eg; next[e + 5] += eb
                                }
                                swap(&current, &next)
                                for k in 0..<next.count { next[k] = 0 }
                            }
                        }
                    }
                }
            }
        }
    }
}
