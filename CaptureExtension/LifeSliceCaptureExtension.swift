import AVKit
import LockedCameraCapture
import QuartzCore
import SwiftUI

/// ロック中にカメラコントロール等から起動されたときの、最小限の鏡。
/// ロック中はアプリ本体の保存領域に触れないので、撮ったコマは session の一時領域に置き、
/// 次にアプリ本体を開いたとき SliceDirector が取り込む。
@main
struct LifeSliceCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedMirrorView(session: session)
        }
    }
}

struct LockedMirrorView: View {
    let session: LockedCameraCaptureSession

    @StateObject private var engine = CameraEngine()
    @Environment(\.scenePhase) private var scenePhase
    @State private var savedCount = 0
    @State private var shutterPulse = false

    private let window = 1.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(engine: engine)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text("LifeSlice")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    if savedCount > 0 {
                        Text("+\(savedCount)")
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

                Button(action: shutter) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                        Circle().fill(.white).frame(width: 60, height: 60)
                            .scaleEffect(shutterPulse ? 0.86 : 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
        .onCameraCaptureEvent { event in
            if event.phase == .ended { shutter() }
        }
        .onAppear { engine.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                engine.start()
            } else {
                engine.buffer.clear()
                engine.stop()
            }
        }
    }

    private func shutter() {
        let pressedAt = CACurrentMediaTime()
        withAnimation(.easeOut(duration: 0.08)) { shutterPulse = true }
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeOut(duration: 0.15)) { shutterPulse = false }
            try? await Task.sleep(nanoseconds: UInt64((window + 0.05) * 1_000_000_000))
            guard let frame = engine.buffer.pick(from: pressedAt - window, to: pressedAt + window) else { return }
            let offset = String(format: "%.2f", frame.time - pressedAt)
            let url = session.sessionContentURL.appendingPathComponent("\(UUID().uuidString)_\(offset).jpg")
            if (try? frame.jpeg.write(to: url, options: .atomic)) != nil {
                savedCount += 1
            }
        }
    }
}
