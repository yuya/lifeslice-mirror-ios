import AVKit
import LockedCameraCapture
import QuartzCore
import SwiftUI

/// ロック中にカメラコントロール等から起動されたときの、最小限の鏡。
/// アプリ本体と同じく撮影ボタンは無く、止まった瞬間の前後から勝手に 1 コマ残す。
/// ロック中はアプリ本体の保存領域に触れないので、コマは session の一時領域に置き、
/// 次にアプリ本体を開いたとき SliceDirector が取り込む。
@main
struct LifeSliceCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedMirrorView(slicer: LockedSlicer(directory: session.sessionContentURL))
        }
    }
}

/// ロック中の「いつ・どのコマを残すか」。設定はアプリ本体と共有できないので初期値で動く。
final class LockedSlicer: ObservableObject {
    let engine = CameraEngine()
    @Published private(set) var savedCount = 0

    private let directory: URL
    private let detector = StillnessDetector()
    private let window: TimeInterval = 3
    private let cooldown: TimeInterval = 30
    private var lastAutoAt: TimeInterval = 0
    private var startedAt: TimeInterval?

    init(directory: URL) {
        self.directory = directory
        detector.onStill = { [weak self] in self?.handleStill() }
        let detector = self.detector
        engine.motionProvider = { detector.latestRotation }
    }

    func start() {
        guard startedAt == nil else { return }
        startedAt = CACurrentMediaTime()
        engine.buffer.keepSeconds = window * 2 + 1.5
        engine.start()
        detector.start()
    }

    /// 画面を離れるとき。1 枚も残せていなければ、開いていた間のどこか 1 コマを残す。
    func stop() {
        guard let startedAt else { return }
        self.startedAt = nil
        detector.stop()
        if savedCount == 0, CACurrentMediaTime() - startedAt > 1.5, let frame = engine.buffer.pickAny() {
            write(frame, offset: nil)
        }
        if engine.isFrozen { engine.setFrozen(false) }
        engine.buffer.clear()
        engine.stop()
    }

    private func handleStill() {
        guard startedAt != nil, !engine.isFrozen, engine.faceVisible, !engine.tooDark else { return }
        let now = CACurrentMediaTime()
        guard now - lastAutoAt >= cooldown else { return }
        lastAutoAt = now
        DispatchQueue.main.asyncAfter(deadline: .now() + window + 0.15) { [weak self] in
            guard let self, self.startedAt != nil,
                  let frame = self.engine.buffer.pick(from: now - self.window, to: now + self.window) else { return }
            self.write(frame, offset: frame.time - now)
        }
    }

    private func write(_ frame: SurpriseBuffer.Frame, offset: Double?) {
        // ファイル名は "<UUID>_<offset>.jpg"（offset が無いときは UUID だけ）
        var name = UUID().uuidString
        if let offset { name += "_" + String(format: "%.2f", offset) }
        let url = directory.appendingPathComponent(name + ".jpg")
        if (try? frame.jpeg.write(to: url, options: .atomic)) != nil {
            savedCount += 1
        }
    }
}

struct LockedMirrorView: View {
    @StateObject var slicer: LockedSlicer
    @Environment(\.scenePhase) private var scenePhase
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(engine: slicer.engine)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text("LifeSlice Mirror")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    Spacer()
                    if slicer.savedCount > 0 {
                        Text("+\(slicer.savedCount)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.94, green: 0.36, blue: 0.24), in: .capsule)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }

            // 撮れた合図
            Color.white
                .opacity(flash ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        // カメラコントロール／音量ボタンは「一時停止」の切り替え
        .onCameraCaptureEvent { event in
            if event.phase == .ended { slicer.engine.setFrozen(!slicer.engine.isFrozen) }
        }
        .onChange(of: slicer.savedCount) { _, _ in
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                withAnimation(.easeOut(duration: 0.45)) { flash = false }
            }
        }
        .onAppear { slicer.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { slicer.start() } else { slicer.stop() }
        }
    }
}
