import Foundation
import Photos

/// 写真ライブラリの「LifeSlice Mirror」アルバムへの保存。
enum PhotoAlbum {
    static let title = "LifeSlice Mirror"
    private static let albumIDKey = "photos.albumID"

    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// スライス 1 枚を保存（失敗しても黙って諦める。アプリ内には必ず残っている）。
    static func save(imageData: Data, date: Date) {
        guard isAuthorized else { return }
        perform { album in
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: imageData, options: nil)
            request.creationDate = date
            add(request.placeholderForCreatedAsset, to: album)
        }
    }

    /// 書き出したリール（GIF / MP4）を保存。
    static func save(fileURL: URL, isVideo: Bool) async -> Bool {
        guard await requestAccess() else { return false }
        return await withCheckedContinuation { continuation in
            perform({ album in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: isVideo ? .video : .photo, fileURL: fileURL, options: nil)
                add(request.placeholderForCreatedAsset, to: album)
            }, completion: { ok in
                continuation.resume(returning: ok)
            })
        }
    }

    // MARK: 内部

    private static func perform(_ body: @escaping (PHAssetCollection?) -> Void,
                                completion: ((Bool) -> Void)? = nil) {
        ensureAlbum { album in
            PHPhotoLibrary.shared().performChanges({
                body(album)
            }, completionHandler: { ok, _ in
                completion?(ok)
            })
        }
    }

    private static func add(_ placeholder: PHObjectPlaceholder?, to album: PHAssetCollection?) {
        guard let placeholder, let album,
              let change = PHAssetCollectionChangeRequest(for: album) else { return }
        change.addAssets([placeholder] as NSArray)
    }

    private static func existingAlbum() -> PHAssetCollection? {
        if let id = UserDefaults.standard.string(forKey: albumIDKey),
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return album
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }

    private static func ensureAlbum(_ then: @escaping (PHAssetCollection?) -> Void) {
        if let album = existingAlbum() {
            then(album)
            return
        }
        var placeholderID: String?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholderID = request.placeholderForCreatedAssetCollection.localIdentifier
        }, completionHandler: { ok, _ in
            guard ok, let id = placeholderID else {
                then(nil)
                return
            }
            UserDefaults.standard.set(id, forKey: albumIDKey)
            then(PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject)
        })
    }
}
