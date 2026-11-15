import AVFoundation
import CoreImage
import QuartzCore
import SwiftUI
import Vision

/// インカメラのセッション管理と、不意打ちバッファへのフレーム供給。
/// アプリ本体とロック中キャプチャ拡張の両方から使うので、UIApplication には触らない。
final class CameraEngine: NSObject, ObservableObject {
    enum MirrorMode: String, CaseIterable, Identifiable {
        case mirror     // 通常：鏡と同じ左右
        case trueView   // 反転：相手から見た自分
        var id: String { rawValue }
        var label: String { self == .mirror ? L("鏡") : L("相手から") }
    }

    // MARK: 公開状態（メインスレッドで更新）
    @Published var mode: MirrorMode = .mirror { didSet { modeFlag = (mode == .trueView) } }
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 4
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var isFrozen = false
    @Published private(set) var faceVisible = false
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var hasCamera = true

    let session = AVCaptureSession()
    let buffer = SurpriseBuffer()
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    /// 1 秒あたり何コマをバッファに入れるか。
    var bufferFPS: Double = 8

    // MARK: 内部
    private let sessionQueue = DispatchQueue(label: "lifeslice.camera.session")
    private let videoQueue = DispatchQueue(label: "lifeslice.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var device: AVCaptureDevice?
    private var configured = false

    // videoQueue からだけ触る
    private var lastBufferedTime: TimeInterval = 0
    private var frameCounter = 0
    private var lastFace = false
    // スレッドをまたいで読むフラグ（厳密な同期は不要な程度の値）
    private var modeFlag = false
    private var frozenFlag = false

    // MARK: ライフサイクル

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorization = granted ? .authorized : .denied
                    if granted { self?.startSession() }
                }
            }
        default:
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            if self.configured, !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configure() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            DispatchQueue.main.async { self.hasCamera = false }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.hasCamera = false }
            return
        }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // 保存用フレームは常に「縦・鏡像」で受け取り、反転モードのときだけ後段で左右を戻す。
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }

        // カメラコントロール（側面ボタン）を軽く押したときのズームスライダー。
        if session.supportsControls {
            let zoomControl = AVCaptureSystemZoomSlider(device: camera) { [weak self] factor in
                DispatchQueue.main.async { self?.zoom = factor }
            }
            if session.canAddControl(zoomControl) { session.addControl(zoomControl) }
            session.setControlsDelegate(self, queue: sessionQueue)
        }

        session.commitConfiguration()
        applyPortraitOrientation()

        device = camera
        configured = true
        let limit = min(camera.maxAvailableVideoZoomFactor, 5)
        DispatchQueue.main.async {
            self.maxZoom = max(1, limit)
            self.hasCamera = true
        }
    }

    /// 保存用フレームを「縦・鏡像」で受け取る指定。構成の確定後にも念のためもう一度かける。
    private func applyPortraitOrientation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    // MARK: 鏡としての操作

    func setZoom(_ value: CGFloat) {
        let clamped = min(max(1, value), maxZoom)
        zoom = clamped
        sessionQueue.async { [weak self] in
            guard let device = self?.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = min(max(device.minAvailableVideoZoomFactor, clamped),
                                             device.maxAvailableVideoZoomFactor)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// 明るさ（露出補正）。-2...+2 EV。
    func setExposureBias(_ value: Float) {
        exposureBias = value
        sessionQueue.async { [weak self] in
            guard let device = self?.device else { return }
            do {
                try device.lockForConfiguration()
                let bias = min(max(device.minExposureTargetBias, value), device.maxExposureTargetBias)
                device.setExposureTargetBias(bias, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// 映像を一時停止して、じっくり見られるようにする。
    func setFrozen(_ frozen: Bool) {
        isFrozen = frozen
        frozenFlag = frozen
        previewLayer?.connection?.isEnabled = !frozen
    }
}

// MARK: - フレーム受信

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !frozenFlag else { return }
        let now = CACurrentMediaTime()
        guard now - lastBufferedTime >= (1.0 / bufferFPS) - 0.005 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastBufferedTime = now
        frameCounter += 1

        // 顔検出は 4 コマに 1 回で十分（約 2 回/秒）。
        if frameCounter % 4 == 0 {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try? handler.perform([request])
            let found = !(request.results ?? []).isEmpty
            if found != lastFace {
                lastFace = found
                DispatchQueue.main.async { self.faceVisible = found }
            }
        }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if image.extent.width > image.extent.height {
            // 接続側の回転指定が効かず横倒しで届いた場合の保険。時計回りに 90° 起こして縦にする。
            image = image.oriented(.right)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x,
                                                            y: -image.extent.origin.y))
        }
        if modeFlag {
            // 反転モード：鏡像で届いているので左右を戻す。
            let width = image.extent.width
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -width, y: 0))
        }
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        guard let jpeg = ciContext.jpegRepresentation(of: image,
                                                      colorSpace: colorSpace,
                                                      options: [quality: 0.82]) else { return }
        buffer.append(.init(time: now, jpeg: jpeg, hasFace: lastFace))
    }
}

// MARK: - カメラコントロール

extension CameraEngine: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

// MARK: - プレビュー

/// AVCaptureVideoPreviewLayer を SwiftUI に載せる薄いラッパー。
struct CameraPreview: UIViewRepresentable {
    let engine: CameraEngine

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = engine.session
        view.previewLayer.videoGravity = .resizeAspectFill
        engine.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
