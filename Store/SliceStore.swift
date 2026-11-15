import Foundation
import ImageIO
import UIKit
import WidgetKit

/// 1 枚のスライス（＝不意打ちの 1 コマ）。
struct Slice: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case shutter    // 自分でシャッターを押した
        case still      // 静止を検知して自動
        case drift      // 立ち去り際に適当に 1 コマ
        case locked     // ロック中の撮影から取り込み
    }

    let id: UUID
    let date: Date
    let source: Source
    /// シャッター（または静止検知）の瞬間から何秒ずれたコマか。マイナスは「前」。
    let offset: Double?
    let fileName: String

    var caption: String {
        let head: String
        switch source {
        case .shutter: head = L("シャッター")
        case .still: head = L("静止を検知")
        case .drift: return L("立ち去り際のどこか 1 コマ")
        case .locked: head = L("ロック中に撮影")
        }
        guard let offset else { return head }
        if abs(offset) < 0.07 { return L("%@・ぴったりその瞬間", head) }
        let seconds = String(format: "%.1f", abs(offset))
        return offset < 0 ? L("%@の %@ 秒前", head, seconds) : L("%@の %@ 秒後", head, seconds)
    }
}

/// スライスの保存先。画像はアプリ内（Application Support）に JPEG で置き、索引は JSON 1 枚。
@MainActor
final class SliceStore: ObservableObject {
    @Published private(set) var slices: [Slice] = []   // 古い順

    private let directory: URL
    private let indexURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Slices", isDirectory: true)
        indexURL = base.appendingPathComponent("slices.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func url(for slice: Slice) -> URL { directory.appendingPathComponent(slice.fileName) }

    var latest: Slice? { slices.last }

    // MARK: 追加・削除

    @discardableResult
    func add(jpeg: Data, date: Date = Date(), source: Slice.Source, offset: Double?) -> Slice? {
        let id = UUID()
        let slice = Slice(id: id, date: date, source: source, offset: offset, fileName: "\(id.uuidString).jpg")
        do {
            try jpeg.write(to: url(for: slice), options: .atomic)
        } catch {
            return nil
        }
        slices.append(slice)
        slices.sort { $0.date < $1.date }
        persist()
        publishToWidget()
        if Prefs.saveToPhotos { PhotoAlbum.save(imageData: jpeg, date: date) }
        return slice
    }

    func delete(_ slice: Slice) {
        try? FileManager.default.removeItem(at: url(for: slice))
        slices.removeAll { $0.id == slice.id }
        ThumbnailCache.shared.remove(slice.id)
        persist()
        publishToWidget()
    }

    // MARK: 永続化

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? decoder.decode([Slice].self, from: data)) ?? []
        // 画像が無くなっている索引は捨てる。
        slices = loaded
            .filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
            .sorted { $0.date < $1.date }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(slices) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: ウィジェット連携

    func publishToWidget() {
        var state = WidgetState()
        state.count = slices.count
        state.lastDate = slices.last?.date
        state.reelThreshold = Prefs.reelThreshold
        state.save()

        if let imageURL = AppGroup.widgetLatestImageURL {
            if let latest, let image = ImageLoader.downsampled(url: url(for: latest), maxPixel: 600),
               let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) {
                try? data.write(to: imageURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: imageURL)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - 画像の読み込み

enum ImageLoader {
    /// 元画像を丸ごとデコードせず、必要な大きさだけ読む。
    static func downsampled(url: URL, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as [CFString: Any] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSUUID, UIImage>()

    func image(for id: UUID) -> UIImage? { cache.object(forKey: id as NSUUID) }
    func set(_ image: UIImage, for id: UUID) { cache.setObject(image, forKey: id as NSUUID) }
    func remove(_ id: UUID) { cache.removeObject(forKey: id as NSUUID) }
}
