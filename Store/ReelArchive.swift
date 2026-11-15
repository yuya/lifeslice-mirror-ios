import Foundation
import UIKit

/// 書き出したリール 1 本ぶんの記録。
struct ReelRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let fileName: String
    let posterName: String?
    let isVideo: Bool
    let frameCount: Int
    let bytes: Int
    let fps: Double
}

/// 書き出したリールの履歴。アプリ内（Application Support/Reels）に置く。
/// 肥大化しないよう「本数の上限（設定で 3 / 5 / 8）」と「合計サイズの上限」の両方で古い順に消す。
@MainActor
final class ReelArchive: ObservableObject {
    /// 合計サイズの上限。大きい設定（720px・100 コマなど）で書き出すと 1 本 10〜20MB になりうるため。
    static let byteLimit = 100 * 1024 * 1024

    @Published private(set) var records: [ReelRecord] = []   // 新しい順

    private let directory: URL
    private let indexURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Reels", isDirectory: true)
        indexURL = base.appendingPathComponent("reels.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func url(for record: ReelRecord) -> URL { directory.appendingPathComponent(record.fileName) }

    func posterURL(for record: ReelRecord) -> URL? {
        record.posterName.map { directory.appendingPathComponent($0) }
    }

    var totalBytes: Int { records.reduce(0) { $0 + $1.bytes } }

    /// 一時フォルダに書き出されたファイルを履歴へ移す。
    @discardableResult
    func add(exportedFile: URL, poster: CGImage?, isVideo: Bool, frameCount: Int, fps: Double) -> ReelRecord? {
        let id = UUID()
        var name = exportedFile.lastPathComponent
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(exportedFile.deletingPathExtension().lastPathComponent)-\(id.uuidString.prefix(4)).\(exportedFile.pathExtension)"
        }
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: exportedFile, to: destination)
        } catch {
            return nil
        }

        var posterName: String?
        if let poster, let data = UIImage(cgImage: poster).jpegData(compressionQuality: 0.8) {
            let file = "\(id.uuidString).jpg"
            if (try? data.write(to: directory.appendingPathComponent(file), options: .atomic)) != nil {
                posterName = file
            }
        }

        let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let record = ReelRecord(id: id, createdAt: Date(), fileName: name, posterName: posterName,
                                isVideo: isVideo, frameCount: frameCount, bytes: bytes, fps: fps)
        records.insert(record, at: 0)
        prune()
        persist()
        return record
    }

    func delete(_ record: ReelRecord) {
        removeFiles(of: record)
        records.removeAll { $0.id == record.id }
        persist()
    }

    /// 上限を超えたぶんを古い順に消す（いちばん新しい 1 本は必ず残す）。設定を変えたときにも呼ぶ。
    func prune() {
        let limit = Prefs.reelHistory
        var changed = false
        while records.count > limit || (totalBytes > Self.byteLimit && records.count > 1) {
            guard let oldest = records.popLast() else { break }
            removeFiles(of: oldest)
            changed = true
        }
        if changed { persist() }
    }

    private func removeFiles(of record: ReelRecord) {
        try? FileManager.default.removeItem(at: url(for: record))
        if let poster = posterURL(for: record) { try? FileManager.default.removeItem(at: poster) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? decoder.decode([ReelRecord].self, from: data)) ?? []
        records = loaded
            .filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
