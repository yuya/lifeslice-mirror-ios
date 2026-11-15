import Foundation

/// 直近数秒ぶんのフレームだけを JPEG で持つリングバッファ。
/// 「止まった瞬間の前後 ±n 秒からランダムに 1 コマ」を実現する心臓部。
/// ここにあるものは全部メモリ上の一時データで、選ばれなかったコマはそのまま捨てられる。
final class SurpriseBuffer {
    struct Frame {
        let time: TimeInterval      // CACurrentMediaTime 基準
        let jpeg: Data
        let hasFace: Bool
        /// 画面全体の平均の明るさ（0＝真っ黒、1＝真っ白）
        let luma: Float
    }

    /// これより暗いコマは「ほぼ真っ暗」とみなして、残す候補から外す。
    /// 目安：ふつうの室内で 0.3〜0.6、明かりを消した部屋で 0.03 前後。
    static let minimumLuma: Float = 0.08

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

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return frames.isEmpty
    }

    /// [from, to] の範囲から一様ランダムに時刻を選び、いちばん近いコマを返す。
    /// 暗すぎるコマは候補にしない。範囲内に候補が無ければ、範囲にいちばん近い（暗くない）コマで妥協する。
    /// 候補が 1 つも無ければ nil（＝今回は残さない）。
    func pick(from: TimeInterval, to: TimeInterval) -> Frame? {
        lock.lock(); defer { lock.unlock() }
        let usable = frames.filter { $0.luma >= Self.minimumLuma }
        guard !usable.isEmpty else { return nil }
        let lower = min(from, to), upper = max(from, to)
        let inRange = usable.filter { $0.time >= lower && $0.time <= upper }
        let target = TimeInterval.random(in: lower...upper)
        let pool = inRange.isEmpty ? usable : inRange
        return pool.min { abs($0.time - target) < abs($1.time - target) }
    }

    /// 立ち去りスライス用。バッファ全体から適当に 1 コマ（顔が写っているコマを優先、暗すぎるコマは除く）。
    func pickAny(preferFace: Bool = true) -> Frame? {
        lock.lock(); defer { lock.unlock() }
        let usable = frames.filter { $0.luma >= Self.minimumLuma }
        guard !usable.isEmpty else { return nil }
        if preferFace, let face = usable.filter(\.hasFace).randomElement() { return face }
        return usable.randomElement()
    }
}
