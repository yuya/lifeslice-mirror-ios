import CoreMotion
import Foundation

/// 端末の揺れから「手が止まった瞬間」を見つける。
/// 顔チェックで人はだいたい 1 秒くらい止まる、というのがこのアプリの前提。
final class StillnessDetector {
    enum Sensitivity: Int, CaseIterable, Identifiable {
        case loose = 0, normal = 1, strict = 2
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .loose: return L("ゆるめ")
            case .normal: return L("ふつう")
            case .strict: return L("きびしめ")
            }
        }
        /// (回転 rad/s, 加速度 g, 止まっている必要のある秒数)
        var thresholds: (rotation: Double, acceleration: Double, hold: TimeInterval) {
            switch self {
            case .loose: return (0.35, 0.08, 0.6)
            case .normal: return (0.22, 0.05, 0.9)
            case .strict: return (0.12, 0.03, 1.3)
            }
        }
    }

    var sensitivity: Sensitivity = .normal
    /// 静止が成立した瞬間に 1 回だけ呼ばれる（メインスレッド）。
    var onStill: (() -> Void)?

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var calmSince: TimeInterval?
    private var fired = false

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        calmSince = nil
        fired = false
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let r = data.rotationRate
            let a = data.userAcceleration
            let rotation = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            let acceleration = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let t = self.sensitivity.thresholds
            let calm = rotation < t.rotation && acceleration < t.acceleration

            if calm {
                if self.calmSince == nil { self.calmSince = data.timestamp }
                if !self.fired, let since = self.calmSince, data.timestamp - since >= t.hold {
                    self.fired = true
                    DispatchQueue.main.async { self.onStill?() }
                }
            } else if rotation > t.rotation * 1.8 || acceleration > t.acceleration * 1.8 {
                // はっきり動いたら再武装。小さな揺れでは連発しない。
                self.calmSince = nil
                self.fired = false
            }
        }
    }

    func stop() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
    }
}
