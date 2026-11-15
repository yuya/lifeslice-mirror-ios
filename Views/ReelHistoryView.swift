import AVKit
import ImageIO
import SwiftUI
import UIKit

/// 履歴の 1 マス。表紙（1 コマ目）と形式を見せる。
struct ReelPoster: View {
    let record: ReelRecord
    let posterURL: URL?
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                ZStack {
                    Theme.card
                    if let image {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay(alignment: .topLeading) {
                Text(record.isVideo ? "MP4" : "GIF")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.paper, in: .rect(cornerRadius: 4))
                    .padding(5)
            }
            .overlay(alignment: .bottomLeading) {
                Text(record.createdAt.formatted(.dateTime.month(.defaultDigits).day().locale(L10n.locale)))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .padding(5)
            }
            .contentShape(.rect)
            .task(id: record.id) {
                guard let posterURL else { return }
                image = await Task.detached(priority: .utility) { () -> UIImage? in
                    guard let cg = ImageLoader.downsampled(url: posterURL, maxPixel: 300) else { return nil }
                    return UIImage(cgImage: cg)
                }.value
            }
    }
}

/// 履歴のリールを再生して、シェア・保存・削除する。
struct ReelPlayerSheet: View {
    let record: ReelRecord
    @EnvironmentObject private var reels: ReelArchive
    @Environment(\.dismiss) private var dismiss
    @State private var savedToPhotos: Bool?
    @State private var confirmDelete = false

    private var info: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(record.bytes), countStyle: .file)
        return "\(record.isVideo ? "MP4" : "GIF")・" + L("%d コマ・%@", record.frameCount, size)
    }

    var body: some View {
        let url = reels.url(for: record)
        VStack(spacing: 14) {
            ZStack {
                Color.black
                if record.isVideo {
                    LoopingVideoView(url: url)
                } else {
                    AnimatedGIFView(url: url)
                }
            }
            .clipShape(.rect(cornerRadius: 22))
            .padding(.horizontal, 16)
            .padding(.top, 20)

            VStack(spacing: 4) {
                Text(record.createdAt.formatted(.dateTime.year().month().day().hour().minute().locale(L10n.locale)))
                    .font(.headline)
                Text(info)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ShareLink(item: url) {
                    Label(L("共有"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                Button {
                    Task { savedToPhotos = await PhotoAlbum.save(fileURL: url, isVideo: record.isVideo) }
                } label: {
                    Label(savedToPhotos == true ? L("保存済み") : L("写真に保存"),
                          systemImage: savedToPhotos == true ? "checkmark" : "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(savedToPhotos == true)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel(L("捨てる"))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .confirmationDialog(L("このリールを捨てますか？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("捨てる"), role: .destructive) {
                reels.delete(record)
                dismiss()
            }
        }
    }
}

// MARK: - 再生

/// GIF をそのままのタイミングで再生する（ImageIO にコマ送りを任せる）。
private final class GIFPlayer: ObservableObject {
    @Published var frame: CGImage?
    private var stopped = true

    func start(_ url: URL) {
        guard stopped else { return }
        stopped = false
        _ = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] _, image, stop in
            guard let self, !self.stopped else {
                stop.pointee = true
                return
            }
            self.frame = image
        }
    }

    func stop() { stopped = true }
}

private struct AnimatedGIFView: View {
    let url: URL
    @StateObject private var player = GIFPlayer()

    var body: some View {
        Group {
            if let frame = player.frame {
                Image(decorative: frame, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .onAppear { player.start(url) }
        .onDisappear { player.stop() }
    }
}

/// MP4 を音なしで繰り返し再生する。
private final class LoopingPlayer: ObservableObject {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    func start(_ url: URL) {
        if looper == nil {
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.isMuted = true
        }
        player.play()
    }
}

private struct LoopingVideoView: View {
    let url: URL
    @StateObject private var model = LoopingPlayer()

    var body: some View {
        VideoPlayer(player: model.player)
            .onAppear { model.start(url) }
            .onDisappear { model.player.pause() }
    }
}
