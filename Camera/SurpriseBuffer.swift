import Foundation

/// 直近数秒ぶんのフレームだけを JPEG で持つリングバッファ。
/// 「シャッターの前後 ±n 秒からランダムに 1 コマ」を実現する心臓部。
/// ここにあるものは全部メモリ上の一時データで、選ばれなかったコマはそのまま捨てられる。
final class SurpriseBuffer {
    struct Frame {
        let time: TimeInterval      // CACurrentMediaTime 基準
        let jpeg: Data
        let hasFace: Bool
    }

    private let lock = NSLock()
    private var frames: [Frame] = []

    /// 何秒ぶん保持するか。前側の振り幅＋立ち去りスライス用の余裕。
    var keepSeconds: TimeInterval = 6

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
    /// 範囲内にコマが無ければ、範囲にいちばん近いコマで妥協する。
    func pick(from: TimeInterval, to: TimeInterval) -> Frame? {
        lock.lock(); defer { lock.unlock() }
        guard !frames.isEmpty else { return nil }
        let lower = min(from, to), upper = max(from, to)
        let inRange = frames.filter { $0.time >= lower && $0.time <= upper }
        let target = TimeInterval.random(in: lower...upper)
        let pool = inRange.isEmpty ? frames : inRange
        return pool.min { abs($0.time - target) < abs($1.time - target) }
    }

    /// 立ち去りスライス用。バッファ全体から適当に 1 コマ（顔が写っているコマを優先）。
    func pickAny(preferFace: Bool = true) -> Frame? {
        lock.lock(); defer { lock.unlock() }
        guard !frames.isEmpty else { return nil }
        if preferFace {
            let faces = frames.filter(\.hasFace)
            if let f = faces.randomElement() { return f }
        }
        return frames.randomElement()
    }
}
