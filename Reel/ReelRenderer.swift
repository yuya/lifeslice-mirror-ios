import AVFoundation
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// スライスの列 → 1 コマずつ加工（切り抜き・フィルタ・日付スタンプ・減色）→ GIF / MP4。
/// プレビューと書き出しで同じ処理を通すので、見たままが出てくる。
final class ReelRenderer {
    struct Source {
        let url: URL
        let date: Date
    }

    enum ReelError: Error {
        case noFrames
        case writerFailed
    }

    let sources: [Source]
    let options: ReelOptions
    private let width: Int
    private let height: Int
    private let ciContext = CIContext()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var palette: QuantPalette?
    private var paletteReady = false

    init(sources: [Source], options: ReelOptions) {
        self.sources = sources
        self.options = options
        let size = options.pixelSize
        width = size.width
        height = size.height
    }

    var frameCount: Int { sources.count }

    // MARK: 1 コマを作る

    /// 完成形の 1 コマ。
    func frame(at index: Int) -> CGImage? {
        preparePaletteIfNeeded()
        guard var pixels = rawPixels(at: index) else { return nil }
        if let palette {
            Quantizer.apply(&pixels, width: width, height: height, palette: palette, dither: options.dither)
        }
        return makeImage(from: pixels)
    }

    /// 全コマ共通のパレットを用意する（最大 24 コマを抜き取って決める）。
    private func preparePaletteIfNeeded() {
        guard !paletteReady else { return }
        paletteReady = true
        switch options.colors {
        case .full:
            palette = nil
        case .gameBoy:
            palette = .gameBoy
        case .oneBit:
            palette = .oneBit
        case .c256, .c64, .c16:
            let count = options.colors.adaptiveCount ?? 256
            let step = max(1, sources.count / 24)
            var samples: [[UInt8]] = []
            var i = 0
            while i < sources.count {
                if let pixels = rawPixels(at: i) { samples.append(pixels) }
                i += step
            }
            palette = samples.isEmpty ? nil : Quantizer.buildPalette(frames: samples, count: count)
        }
    }

    /// 切り抜き・フィルタ・スタンプまで済ませた RGBA8（減色前）。
    private func rawPixels(at index: Int) -> [UInt8]? {
        guard sources.indices.contains(index) else { return nil }
        let source = sources[index]
        let needed = max(height, Int(Double(width) * 16.0 / 9.0)) + 2
        guard var image = ImageLoader.downsampled(url: source.url, maxPixel: needed) else { return nil }

        if let name = options.filter.ciFilterName, let filter = CIFilter(name: name) {
            let input = CIImage(cgImage: image)
            filter.setValue(input, forKey: kCIInputImageKey)
            if let output = filter.outputImage,
               let filtered = ciContext.createCGImage(output, from: input.extent) {
                image = filtered
            }
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // UIKit の座標（左上原点）で描く
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .medium
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }

            // アスペクトフィル。顔が切れにくいよう、縦は少し上寄せ。
            let iw = CGFloat(image.width), ih = CGFloat(image.height)
            let scale = max(CGFloat(width) / iw, CGFloat(height) / ih)
            let dw = iw * scale, dh = ih * scale
            let rect = CGRect(x: (CGFloat(width) - dw) / 2, y: (CGFloat(height) - dh) * 0.4, width: dw, height: dh)
            UIImage(cgImage: image).draw(in: rect)

            drawStamp(date: source.date, index: index)
            return true
        }
        return drawn ? pixels : nil
    }

    private func drawStamp(date: Date, index: Int) {
        let text = options.stampFormat.text(for: date, index: index)
        guard !text.isEmpty else { return }
        let w = CGFloat(width), h = CGFloat(height)
        let big = options.stampLayout == .centerBig
        let fontSize = (w * (big ? 0.13 : 0.075)).rounded()
        let font = options.stampFont.uiFont(size: fontSize)
        let style = options.stampStyle
        let string = text as NSString
        let size = string.size(withAttributes: [.font: font])
        let margin = (w * 0.055).rounded()
        let pad = style.labelColor == nil ? 0 : (fontSize * 0.28).rounded()

        var origin: CGPoint
        switch options.stampLayout {
        case .bottomRight: origin = CGPoint(x: w - margin - size.width - pad, y: h - margin - size.height - pad)
        case .bottomLeft: origin = CGPoint(x: margin + pad, y: h - margin - size.height - pad)
        case .bottomCenter: origin = CGPoint(x: (w - size.width) / 2, y: h - margin - size.height - pad)
        case .topLeft: origin = CGPoint(x: margin + pad, y: margin + pad)
        case .topRight: origin = CGPoint(x: w - margin - size.width - pad, y: margin + pad)
        case .centerBig: origin = CGPoint(x: (w - size.width) / 2, y: (h - size.height) / 2)
        }
        origin = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())

        if let label = style.labelColor {
            label.setFill()
            UIRectFill(CGRect(origin: origin, size: size).insetBy(dx: -pad, dy: -pad * 0.6))
        }
        if let outline = style.outlineColor {
            let d = max(1, (fontSize / 16).rounded())
            for (dx, dy) in [(-d, 0), (d, 0), (0, -d), (0, d), (d, d)] {
                string.draw(at: CGPoint(x: origin.x + dx, y: origin.y + dy),
                            withAttributes: [.font: font, .foregroundColor: outline])
            }
        }
        string.draw(at: origin, withAttributes: [.font: font, .foregroundColor: style.textColor])
    }

    private func makeImage(from pixels: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: 書き出し

    /// 一時フォルダに書き出して URL を返す。`progress` は 0...1。
    func export(progress: @escaping (Double) -> Void) async throws -> URL {
        guard frameCount > 0 else { throw ReelError.noFrames }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = "LifeSlice-\(stamp.string(from: Date())).\(options.format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)

        switch options.format {
        case .gif: try writeGIF(to: url, progress: progress)
        case .mp4: try await writeMP4(to: url, progress: progress)
        }
        return url
    }

    private func writeGIF(to url: URL, progress: (Double) -> Void) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                frameCount, nil) else { throw ReelError.writerFailed }
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)

        let delay = 1.0 / options.speed.fps
        var written = 0
        for index in 0..<frameCount {
            if Task.isCancelled { throw CancellationError() }
            autoreleasepool {
                guard let image = frame(at: index) else { return }
                // 最後のコマは少し長めに見せてからループ
                let d = index == frameCount - 1 ? max(delay, 0.8) : delay
                let properties = [kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: d,
                    kCGImagePropertyGIFUnclampedDelayTime: d,
                ]] as CFDictionary
                CGImageDestinationAddImage(destination, image, properties)
                written += 1
            }
            progress(Double(index + 1) / Double(frameCount))
        }
        guard written > 0, CGImageDestinationFinalize(destination) else { throw ReelError.writerFailed }
    }

    private func writeMP4(to url: URL, progress: (Double) -> Void) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw ReelError.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ReelError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        // 短すぎる動画は再生しづらいので、3 秒に届くまで同じ並びを繰り返す。
        let fps = options.speed.fps
        let onePass = Double(frameCount) / fps
        let loops = max(1, Int((3.0 / onePass).rounded(.up)))
        let total = frameCount * loops
        let timescale: Int32 = 600
        let frameTicks = Int64((Double(timescale) / fps).rounded())

        var presented: Int64 = 0
        for n in 0..<total {
            if Task.isCancelled {
                writer.cancelWriting()
                throw CancellationError()
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let index = n % frameCount
            if let image = frame(at: index), let buffer = pixelBuffer(from: image, pool: adaptor.pixelBufferPool) {
                adaptor.append(buffer, withPresentationTime: CMTime(value: presented, timescale: timescale))
            }
            presented += frameTicks
            progress(Double(n + 1) / Double(total))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: presented, timescale: timescale))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ReelError.writerFailed }
    }

    private func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colorSpace, bitmapInfo: info) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
