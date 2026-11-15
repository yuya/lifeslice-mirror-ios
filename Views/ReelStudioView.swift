import SwiftUI
import UIKit

/// リール作り。上がプレビュー、下が選択肢。見たままが書き出される。
struct ReelStudioView: View {
    @EnvironmentObject private var store: SliceStore

    enum Range: String, CaseIterable, Identifiable {
        case recent30, recent100, thisMonth, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent30: return "直近30枚"
            case .recent100: return "直近100枚"
            case .thisMonth: return "今月"
            case .all: return "ぜんぶ"
            }
        }
    }

    /// プレビューで回すコマ数の上限（書き出しは全コマ）。
    private static let previewLimit = 60

    @State private var options = ReelOptions()
    @State private var range: Range = .recent30
    @State private var frames: [UIImage] = []
    @State private var rendering = false
    @State private var exporting = false
    @State private var exportProgress = 0.0
    @State private var exported: ExportedReel?
    @State private var errorMessage: String?

    struct ExportedReel: Identifiable {
        let id = UUID()
        let url: URL
        let isVideo: Bool
        let bytes: Int
        let frameCount: Int
    }

    private var chosen: [Slice] {
        let all = store.slices
        switch range {
        case .recent30: return Array(all.suffix(30))
        case .recent100: return Array(all.suffix(100))
        case .thisMonth:
            return all.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
        case .all: return all
        }
    }

    private func sources(_ slices: [Slice]) -> [ReelRenderer.Source] {
        slices.map { .init(url: store.url(for: $0), date: $0.date) }
    }

    /// 見た目に関わる設定だけを束ねたキー（速度と形式はプレビューの描き直しが要らない）。
    private struct RenderKey: Equatable {
        var options: ReelOptions
        var ids: [UUID]
    }

    private var renderKey: RenderKey {
        var visual = options
        visual.speed = .normal
        visual.format = .gif
        return RenderKey(options: visual, ids: chosen.suffix(Self.previewLimit).map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea
            Divider().overlay(.white.opacity(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ChipRow(title: "どこからどこまで", items: Range.allCases, selection: $range) { $0.label }
                    ChipRow(title: "はやさ", items: ReelOptions.Speed.allCases, selection: $options.speed) { $0.label }
                    ChipRow(title: "色数", items: ReelOptions.ColorDepth.allCases, selection: $options.colors) { $0.label }
                    if options.colors != .full {
                        ChipRow(title: "ディザ（色のまぜ方）", items: DitherMode.allCases, selection: $options.dither) { $0.label }
                    }
                    ChipRow(title: "フィルタ", items: ReelOptions.Filter.allCases, selection: $options.filter) { $0.label }
                    ChipRow(title: "日付の書き方", items: ReelOptions.StampFormat.allCases, selection: $options.stampFormat) { $0.label }
                    if options.stampFormat != .none {
                        ChipRow(title: "フォント", items: ReelOptions.StampFont.allCases, selection: $options.stampFont) { $0.label }
                        ChipRow(title: "日付の色", items: ReelOptions.StampStyle.allCases, selection: $options.stampStyle) { $0.label }
                        ChipRow(title: "日付の位置", items: ReelOptions.StampLayout.allCases, selection: $options.stampLayout) { $0.label }
                    }
                    ChipRow(title: "かたち", items: ReelOptions.Aspect.allCases, selection: $options.aspect) { $0.label }
                    ChipRow(title: "大きさ（小さいほど軽くてチープ）", items: ReelOptions.Size.allCases, selection: $options.size) { $0.label }
                    ChipRow(title: "形式", items: ReelOptions.Format.allCases, selection: $options.format) { $0.label }
                }
                .padding(.vertical, 18)
            }
            exportBar
        }
        .background(Theme.ink)
        .navigationTitle("リール")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: renderKey) { await renderPreview() }
        .sheet(item: $exported) { reel in
            ExportedReelSheet(reel: reel)
                .presentationDetents([.medium])
                .tint(Theme.accent)
                .fontDesign(.rounded)
        }
        .alert("書き出せませんでした", isPresented: Binding(get: { errorMessage != nil },
                                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: プレビュー

    private var previewArea: some View {
        ZStack {
            Color.black
            if frames.isEmpty {
                if rendering {
                    ProgressView()
                } else {
                    Text("この範囲にスライスがありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / options.speed.fps)) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate * options.speed.fps)
                    Image(uiImage: frames[tick % frames.count])
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                }
                .padding(.vertical, 10)
                .opacity(rendering ? 0.5 : 1)
            }
        }
        .frame(height: 330)
        .overlay(alignment: .bottomTrailing) {
            if chosen.count > Self.previewLimit {
                Text("プレビューは直近 \(Self.previewLimit) コマ")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: .capsule)
                    .padding(10)
            }
        }
    }

    private func renderPreview() async {
        // 連打されても最後の選択だけ描く
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }
        let slices = Array(chosen.suffix(Self.previewLimit))
        guard !slices.isEmpty else {
            frames = []
            rendering = false
            return
        }
        rendering = true
        let renderer = ReelRenderer(sources: sources(slices), options: options)
        let work = Task.detached(priority: .userInitiated) { () -> [UIImage] in
            var result: [UIImage] = []
            result.reserveCapacity(renderer.frameCount)
            for index in 0..<renderer.frameCount {
                if Task.isCancelled { return [] }
                if let cg = renderer.frame(at: index) { result.append(UIImage(cgImage: cg)) }
            }
            return result
        }
        let rendered = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        if Task.isCancelled { return }
        frames = rendered
        rendering = false
    }

    // MARK: 書き出し

    private var exportBar: some View {
        VStack(spacing: 8) {
            if exporting {
                ProgressView(value: exportProgress)
                    .tint(Theme.accent)
            }
            Button {
                Task { await export() }
            } label: {
                Text(exporting ? "書き出し中…" : "\(chosen.count) コマを \(options.format.label) にする")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(exporting || chosen.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.ink)
    }

    private func export() async {
        let slices = chosen
        guard !slices.isEmpty else { return }
        exporting = true
        exportProgress = 0
        let renderer = ReelRenderer(sources: sources(slices), options: options)
        let isVideo = options.format == .mp4
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try await renderer.export { value in
                    Task { @MainActor in exportProgress = value }
                }
            }.value
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            exported = ExportedReel(url: url, isVideo: isVideo, bytes: bytes, frameCount: slices.count)
        } catch {
            errorMessage = error.localizedDescription
        }
        exporting = false
    }
}

/// 書き出し後のシェア画面。
private struct ExportedReelSheet: View {
    let reel: ReelStudioView.ExportedReel
    @State private var savedToPhotos: Bool?

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(reel.bytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("できました")
                .font(.title2.bold())
            Text("\(reel.frameCount) コマ・\(sizeText)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            ShareLink(item: reel.url) {
                Label("シェアする", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)

            Button {
                Task { savedToPhotos = await PhotoAlbum.save(fileURL: reel.url, isVideo: reel.isVideo) }
            } label: {
                Label(savedLabel, systemImage: savedToPhotos == true ? "checkmark" : "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(savedToPhotos == true)
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }

    private var savedLabel: String {
        switch savedToPhotos {
        case .some(true): return "「\(PhotoAlbum.title)」に保存しました"
        case .some(false): return "保存できませんでした（写真へのアクセスを確認）"
        case .none: return "写真に保存"
        }
    }
}
