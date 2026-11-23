import Foundation
import UIKit
import Vision

/// 「隙のある顔」をどれくらい選ばれやすくするか。
enum CandidBias: Int, CaseIterable, Identifiable {
    case off = 0, some = 1, strong = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off: return L("ふつう（くじ引きだけ）")
        case .some: return L("ちょっと寄せる")
        case .strong: return L("がっつり寄せる")
        }
    }
    /// 隙の点数 1 あたり、選ばれやすさを何倍ぶん足すか
    var strength: Double {
        switch self {
        case .off: return 0
        case .some: return 2
        case .strong: return 6
        }
    }
}

/// 候補のコマに「隙の点数」をつけて、点数が高いほど当たりやすいくじを引く。
/// 点数 0 のコマにも必ず当たりの目を残すので、たまにはキメ顔も選ばれる。
enum CandidScorer {
    /// 顔の検出は重いので、候補はこの数まで間引いて採点する。
    static let maxScored = 16

    static func choose(_ frames: [SurpriseBuffer.Frame], bias: CandidBias) -> SurpriseBuffer.Frame? {
        guard !frames.isEmpty else { return nil }
        guard bias != .off, frames.count > 1 else { return frames.randomElement() }

        // 時間方向に均等に間引く
        let step = max(1, Int((Double(frames.count) / Double(maxScored)).rounded(.up)))
        let sampled = stride(from: 0, to: frames.count, by: step).map { frames[$0] }

        let weights = sampled.map { 1 + bias.strength * score($0) }
        let total = weights.reduce(0, +)
        var ticket = Double.random(in: 0..<total)
        for (frame, weight) in zip(sampled, weights) {
            if ticket < weight { return frame }
            ticket -= weight
        }
        return sampled.last
    }

    /// 隙の点数（だいたい 0〜2.5）。ブレ・目つむり・口あき・顔の傾き。
    static func score(_ frame: SurpriseBuffer.Frame) -> Double {
        // ブレ：撮った瞬間の回転の速さ。1.2 rad/s でいっぱい
        var total = min(1, Double(frame.motion) / 1.2)
        if let face = faceTraits(of: frame.jpeg) {
            total += face.eyesClosed
            total += face.mouthOpen * 0.6
            total += face.tilted * 0.4
        }
        return total
    }

    private struct Traits {
        var eyesClosed: Double   // 0〜1
        var mouthOpen: Double    // 0〜1
        var tilted: Double       // 0〜1
    }

    private static func faceTraits(of jpeg: Data) -> Traits? {
        guard let image = UIImage(data: jpeg)?.cgImage else { return nil }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let marks = face.landmarks else { return nil }

        // 目：縦÷横。開いた目でだいたい 0.3 前後、閉じると 0.15 を切る
        let openness = [marks.leftEye, marks.rightEye].compactMap { $0.map(aspect) }
        let eyesClosed = openness.isEmpty ? 0
            : openness.map { clamp((0.30 - $0) / 0.15) }.reduce(0, +) / Double(openness.count)
        // 口：唇の内側の縦÷横。閉じていれば 0 近く
        let mouthOpen = marks.innerLips.map { clamp((aspect($0) - 0.12) / 0.35) } ?? 0
        // 傾き：首をかしげている・端末が傾いている
        let roll = abs(face.roll?.doubleValue ?? 0)
        let tilted = clamp((roll - 0.2) / 0.4)
        return Traits(eyesClosed: eyesClosed, mouthOpen: mouthOpen, tilted: tilted)
    }

    private static func aspect(_ region: VNFaceLandmarkRegion2D) -> Double {
        let points = region.normalizedPoints
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              maxX - minX > 0 else { return 0.3 }
        return Double((maxY - minY) / (maxX - minX))
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}
