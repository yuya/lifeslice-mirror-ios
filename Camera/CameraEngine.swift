import AVFoundation
import CoreImage
import QuartzCore
import SwiftUI
import UIKit
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
    /// 一時停止した瞬間の 1 枚（止めている間はこれを拡大して見る）
    @Published private(set) var frozenImage: UIImage?
    /// その 1 枚を撮ったとき「相手から」だったか（あとで左右を切り替えたら絵も反転させるため）
    private(set) var frozenWasTrueView = false
    @Published private(set) var faceVisible = false
    /// いま映っている映像が、残す価値のないほど暗いかどうか。
    @Published private(set) var tooDark = false
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var hasCamera = true

    let session = AVCaptureSession()
    let buffer = SurpriseBuffer()
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    /// 背景ぼかし中に、加工した映像を流すレイヤー
    weak var blurLayer: CALayer?

    /// 被写体（人）以外をぼかす。オンの間は加工した映像を blurLayer に流し、スライスもぼかした絵で残す。
    @Published var backgroundBlur = false {
        didSet {
            blurFlag = backgroundBlur
            if !backgroundBlur { blurLayer?.contents = nil }
        }
    }

    /// スライスを集めるか。オフのときはバッファに何も貯めない（ただの鏡）。
    var slicingEnabled = true {
        didSet {
            slicingFlag = slicingEnabled
            if !slicingEnabled { buffer.clear() }
        }
    }

    /// コマごとのブレ具合（端末の回転の速さ）を教えてもらう口。無ければ 0 扱い。
    var motionProvider: (() -> Float)?

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
    private var lastDark = false
    // 起動直後（露出が合う前）のコマを見分けるため
    private var restartPending = true
    private var warmUntil: TimeInterval = 0
    // スレッドをまたいで読むフラグ（厳密な同期は不要な程度の値）
    private var modeFlag = false
    private var frozenFlag = false
    private var blurFlag = false
    private var slicingFlag = true
    /// 一時停止を頼まれた。次のコマを 1 枚とっておいてから止める
    private var stillRequested = false

    // 背景ぼかし用（videoQueue からだけ触る）
    private lazy var segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private let sequenceHandler = VNSequenceRequestHandler()

    // MARK: ライフサイクル

    func start() {
        restartPending = true
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
    /// 止めるときは、次に届くコマをそのまま 1 枚とっておいてから止める（スライスを集めていなくても拡大できるように）。
    func setFrozen(_ frozen: Bool) {
        isFrozen = frozen
        if frozen {
            frozenWasTrueView = mode == .trueView
            stillRequested = true
        } else {
            stillRequested = false
            frozenImage = nil
            frozenFlag = false
            previewLayer?.connection?.isEnabled = true
        }
    }

    /// videoQueue から：とっておいた 1 枚を渡して、ここで本当に止める。
    private func finishFreeze(with still: CGImage?) {
        DispatchQueue.main.async {
            guard self.isFrozen else { return }
            self.frozenImage = still.map { UIImage(cgImage: $0) }
            self.frozenFlag = true
            self.previewLayer?.connection?.isEnabled = false
        }
    }
}

// MARK: - フレーム受信

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !frozenFlag else { return }
        let now = CACurrentMediaTime()
        let blur = blurFlag
        let still = stillRequested
        let wantsBuffer = slicingFlag && now - lastBufferedTime >= (1.0 / bufferFPS) - 0.005
        guard blur || still || wantsBuffer else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 見えている絵（ぼかし・向き・左右）を作る
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if blur, let blurred = blurredBackground(image, pixelBuffer: pixelBuffer) {
            image = blurred
        }
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

        if blur { show(image) }
        if still {
            stillRequested = false
            // カメラのコマ自身の色空間で書き出す（決め打ちの sRGB だと、止めたとき明るく見える）
            let space = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue() ?? colorSpace
            finishFreeze(with: ciContext.createCGImage(image, from: image.extent,
                                                       format: .BGRA8, colorSpace: space))
            return
        }
        guard wantsBuffer else { return }
        lastBufferedTime = now
        if restartPending {
            restartPending = false
            warmUntil = now + SurpriseBuffer.warmUpSeconds
        }
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

        // 明るさ。暗すぎるコマは後で候補から外す。
        let luma = Self.meanLuma(of: pixelBuffer)
        let dark = luma < SurpriseBuffer.minimumLuma
        if dark != lastDark {
            lastDark = dark
            DispatchQueue.main.async { self.tooDark = dark }
        }

        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        let jpegSpace = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue() ?? colorSpace
        guard let jpeg = ciContext.jpegRepresentation(of: image,
                                                      colorSpace: jpegSpace,
                                                      options: [quality: 0.82]) else { return }
        buffer.append(.init(time: now, jpeg: jpeg, hasFace: lastFace, luma: luma,
                            motion: motionProvider?() ?? 0, settled: now >= warmUntil))
    }

    /// 人の形を切り出して、それ以外をぼかした絵を返す。
    private func blurredBackground(_ image: CIImage, pixelBuffer: CVPixelBuffer) -> CIImage? {
        try? sequenceHandler.perform([segmentation], on: pixelBuffer, orientation: .up)
        guard let maskBuffer = segmentation.results?.first?.pixelBuffer else { return nil }
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(scaleX: image.extent.width / mask.extent.width,
                                                      y: image.extent.height / mask.extent.height))
        // 境目を少しなじませる
        mask = mask.clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: image.extent)
        let background = image.clampedToExtent().applyingGaussianBlur(sigma: 24).cropped(to: image.extent)
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask,
        ])
    }

    /// ぼかした映像を画面に流す（画面に要る大きさまで縮めてから）。
    private func show(_ image: CIImage) {
        let scale = min(1, 720 / image.extent.width)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let frame = ciContext.createCGImage(small, from: small.extent) else { return }
        DispatchQueue.main.async {
            guard self.backgroundBlur else { return }
            self.blurLayer?.contents = frame
        }
    }

    /// BGRA のピクセルバッファの、中央（顔が来るあたり：横 25〜75%・縦 20〜70%）の明るさ（0...1）。
    /// 画面全体の平均だと、明るい天井や窓に引っぱられて「顔だけ真っ暗」を見逃すため。
    private static func meanLuma(of pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 1 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let step = 16
        var sum = 0
        var count = 0
        var y = height / 5
        while y < height * 7 / 10 {
            let row = pixels + y * bytesPerRow
            var x = width / 4
            while x < width * 3 / 4 {
                let p = row + x * 4
                sum += Int(p[2]) * 77 + Int(p[1]) * 150 + Int(p[0]) * 29   // R, G, B
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return 1 }
        return Float(sum) / Float(count) / 65280.0
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

/// 背景ぼかし中の映像を出す面。CameraPreview の上に重ねる。
struct BlurredPreview: UIViewRepresentable {
    let engine: CameraEngine

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.contentsGravity = .resizeAspectFill
        view.layer.masksToBounds = true
        engine.blurLayer = view.layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
