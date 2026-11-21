import Foundation

/// 直近数秒ぶんのフレームだけを JPEG で持つリングバッファ。
/// 「止まった瞬間の前後 ±n 秒から 1 コマ」を実現する心臓部。
/// ここにあるものは全部メモリ上の一時データで、選ばれなかったコマはそのまま捨てられる。
final class SurpriseBuffer {
    struct Frame {
        let time: TimeInterval      // CACurrentMediaTime 基準
        let jpeg: Data
        let hasFace: Bool
        /// 画面中央（顔のあたり）の明るさ（0＝真っ黒、1＝真っ白）
        let luma: Float
        /// そのコマを撮った瞬間の端末の回転の速さ（rad/s）。大きいほどブレている
        let motion: Float
        /// カメラを起動した直後（露出が合う前）のコマではないか
        let settled: Bool
    }

    /// 顔のあたりがこれより暗いコマは、残す候補にしない。
    /// 目安：ふつうの室内で 0.35〜0.6、薄暗くて顔がほぼ黒いコマで 0.1 前後。
    static let minimumLuma: Float = 0.2
    /// 同じバッファのほかのコマ（中央値）と比べて、これより暗いコマも外す。
    /// 露出が一瞬だけ落ちたコマや、手で画面を隠しかけたコマを避けるため。
    static let relativeLuma: Float = 0.65
    /// カメラを起動してから露出が落ち着くまでの秒数。この間のコマは使わない。
    static let warmUpSeconds: TimeInterval = 1.0

    private let lock = NSLock()
    private var frames: [Frame] = []

    /// 何秒ぶん保持するか。前後の振り幅ぶん＋余裕。
    var keepSeconds: TimeInterval = 8

    func append(_ frame: Frame) {
        lock.lock(); defer { lock.unlock() }
        frames.append(frame)
        let cutoff = frame.time - keepSeconds
        if let first = frames.first, first.time < cutoff {
            frames.removeAll { $0.time < cutoff }
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        frames.removeAll(keepingCapacity: false)
    }

    /// いちばん新しいコマ（一時停止したときに映しておく 1 枚）。
    var latest: Frame? {
        lock.lock(); defer { lock.unlock() }
        return frames.last
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return frames.isEmpty
    }

    /// 残してよいコマ：起動直後でなく、顔のあたりが暗すぎず、まわりのコマより極端に暗くないもの。
    private func usableFrames() -> [Frame] {
        let bright = frames.filter { $0.settled && $0.luma >= Self.minimumLuma }
        guard !bright.isEmpty else { return [] }
        let sorted = bright.map(\.luma).sorted()
        let median = sorted[sorted.count / 2]
        return bright.filter { $0.luma >= median * Self.relativeLuma }
    }

    /// [from, to] の範囲にある、残してよいコマ全部（抽選の候補）。
    /// 範囲内に無ければ、範囲の中心にいちばん近い 1 コマだけを返す。どれも使えなければ空。
    func candidates(from: TimeInterval, to: TimeInterval) -> [Frame] {
        lock.lock(); defer { lock.unlock() }
        let usable = usableFrames()
        guard !usable.isEmpty else { return [] }
        let lower = min(from, to), upper = max(from, to)
        let inRange = usable.filter { $0.time >= lower && $0.time <= upper }
        if !inRange.isEmpty { return inRange }
        let center = (lower + upper) / 2
        return usable.min { abs($0.time - center) < abs($1.time - center) }.map { [$0] } ?? []
    }

    /// 立ち去りスライスの候補。顔が写っているコマがあればそれだけ。
    func driftCandidates() -> [Frame] {
        lock.lock(); defer { lock.unlock() }
        let usable = usableFrames()
        let faces = usable.filter(\.hasFace)
        return faces.isEmpty ? usable : faces
    }

    /// 範囲から一様ランダムに 1 コマ（顔の崩れ具合などは見ない、軽い版。ロック中の撮影で使う）。
    func pick(from: TimeInterval, to: TimeInterval) -> Frame? {
        candidates(from: from, to: to).randomElement()
    }

    /// 立ち去りスライスの軽い版。
    func pickAny() -> Frame? {
        driftCandidates().randomElement()
    }
}
