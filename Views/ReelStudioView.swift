import SwiftUI
import UIKit

/// リール作り。上がプレビュー、下が選択肢。見たままが書き出される。
/// 書き出したときの設定は覚えておき、次に開いたときの初期値にする。
struct ReelStudioView: View {
    @EnvironmentObject private var store: SliceStore
    @EnvironmentObject private var reels: ReelArchive
    @Environment(\.returnToMirror) private var returnToMirror

    enum Range: String, CaseIterable, Identifiable {
        case recent30, recent100, month, period, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent30: return L("直近30枚")
            case .recent100: return L("直近100枚")
            case .month: return L("月でえらぶ")
            case .period: return L("期間でえらぶ")
            case .all: return L("ぜんぶ")
            }
        }
    }

    struct MonthChoice: Identifiable, Equatable {
        let id: Date        // その月の 1 日
        let label: String
    }

    /// プレビューで回すコマ数の上限（書き出しは全コマ）。
    private static let previewLimit = 60

    @State private var options = ReelOptions.loadLast()
    @State private var range = Range(rawValue: UserDefaults.standard.string(forKey: Prefs.Key.lastReelRange) ?? "") ?? .recent30
    /// えらんだ月（nil のときはスライスがあるいちばん新しい月）
    @State private var month: Date?
    @State private var periodFrom = Date()
    @State private var periodTo = Date()
    @State private var periodReady = false

    @State private var frames: [UIImage] = []
    @State private var tab: Tab = .colors
    /// 見本タイル（キーは "colors.c256" のように 種類.値）
    @State private var tileImages: [String: UIImage] = [:]
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

    // MARK: 範囲

    private var monthChoices: [MonthChoice] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for slice in store.slices {
            if let start = calendar.dateInterval(of: .month, for: slice.date)?.start {
                counts[start, default: 0] += 1
            }
        }
        return counts.keys.sorted(by: >).map { start in
            let name = start.formatted(.dateTime.year().month(.wide).locale(L10n.locale))
            return MonthChoice(id: start, label: L("%@（%d）", name, counts[start] ?? 0))
        }
    }

    private var activeMonth: Date? { month ?? monthChoices.first?.id }

    private var chosen: [Slice] {
        let all = store.slices
        let calendar = Calendar.current
        switch range {
        case .recent30: return Array(all.suffix(30))
        case .recent100: return Array(all.suffix(100))
        case .month:
            guard let target = activeMonth else { return [] }
            return all.filter { calendar.isDate($0.date, equalTo: target, toGranularity: .month) }
        case .period:
            let start = calendar.startOfDay(for: min(periodFrom, periodTo))
            let lastDay = calendar.startOfDay(for: max(periodFrom, periodTo))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return all.filter { $0.date >= start && $0.date < end }
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
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tabContent
                }
                .padding(.vertical, 16)
            }
            exportBar
        }
        .background(Theme.ink)
        .navigationTitle(L("リール"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("鏡にもどる")) { returnToMirror() }
            }
        }
        .onAppear(perform: preparePeriod)
        .task(id: renderKey) { await renderPreview() }
        .task(id: tileKey) { await renderTiles() }
        .sheet(item: $exported) { reel in
            ExportedReelSheet(reel: reel) {
                // シートを閉じてから、一覧ごと閉じて鏡へ
                exported = nil
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    returnToMirror()
                }
            }
            .presentationDetents([.height(470)])
            .tint(Theme.accent)
            .fontDesign(.rounded)
        }
        .alert(L("書き出せませんでした"), isPresented: Binding(get: { errorMessage != nil },
                                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: タブ

    enum Tab: String, CaseIterable, Identifiable {
        case range, colors, filter, date, output
        var id: String { rawValue }
        var title: String {
            switch self {
            case .range: return L("範囲")
            case .colors: return L("色数")
            case .filter: return L("フィルタ")
            case .date: return L("日付")
            case .output: return L("出力")
            }
        }
    }

    private func currentValue(of tab: Tab) -> String {
        switch tab {
        case .range: return range.label
        case .colors: return options.colors.label
        case .filter: return options.filter.label
        case .date: return options.stampFormat.label
        case .output: return "\(options.format.label)・\(options.size.width)"
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { item in
                let on = item == tab
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tab = item }
                } label: {
                    VStack(spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        Text(currentValue(of: item))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(on ? Theme.ink.opacity(0.7) : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Theme.ink : .white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.horizontal, 2)
                    .background(on ? Theme.paper : .clear, in: .rect(cornerRadius: 14))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .range:
            rangeSection
        case .colors:
            TileGrid(title: L("色数"), items: ReelOptions.ColorDepth.allCases, selection: $options.colors,
                     label: { $0.label }, image: { tileImages["colors." + $0.rawValue] })
            if options.colors != .full {
                ChipRow(title: L("ディザ（色のまぜ方）"), items: DitherMode.allCases, selection: $options.dither) { $0.label }
            }
            sampleNote
        case .filter:
            TileGrid(title: L("フィルタ"), items: ReelOptions.Filter.allCases, selection: $options.filter,
                     label: { $0.label }, image: { tileImages["filter." + $0.rawValue] })
            sampleNote
        case .date:
            ChipRow(title: L("日付の書き方"), items: ReelOptions.StampFormat.allCases, selection: $options.stampFormat) { $0.label }
            if options.stampFormat != .none {
                TileGrid(title: L("日付の色"), items: ReelOptions.StampStyle.allCases, selection: $options.stampStyle,
                         label: { $0.label }, image: { tileImages["stamp." + $0.rawValue] })
                ChipRow(title: L("フォント"), items: ReelOptions.StampFont.allCases, selection: $options.stampFont) { $0.label }
                ChipRow(title: L("日付の位置"), items: ReelOptions.StampLayout.allCases, selection: $options.stampLayout) { $0.label }
            }
        case .output:
            ChipRow(title: L("はやさ"), items: ReelOptions.Speed.allCases, selection: $options.speed) { $0.label }
            ChipRow(title: L("かたち"), items: ReelOptions.Aspect.allCases, selection: $options.aspect) { $0.label }
            ChipRow(title: L("大きさ（小さいほど軽くてチープ）"), items: ReelOptions.Size.allCases, selection: $options.size) { $0.label }
            ChipRow(title: L("形式"), items: ReelOptions.Format.allCases, selection: $options.format) { $0.label }
        }
    }

    private var sampleNote: some View {
        Text(L("見本は、えらんだ範囲のいちばん新しいスライスで作っています。"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
    }

    // MARK: 見本タイル

    /// タイルを描き直すきっかけ。そのタブで並べている項目そのものは、どれを選んでも見本は変わらないので外す。
    private struct TileKey: Equatable {
        var tab: Tab
        var options: ReelOptions
        var sampleID: UUID?
    }

    private var tileSample: Slice? { chosen.last ?? store.slices.last }

    private var tileKey: TileKey {
        var o = options
        o.speed = .normal
        o.format = .gif
        o.size = .tiny
        o.aspect = .classic
        switch tab {
        case .colors: o.colors = .full
        case .filter: o.filter = .none
        case .date: o.stampStyle = .camcorder
        case .range, .output: break
        }
        return TileKey(tab: tab, options: o, sampleID: tileSample?.id)
    }

    private func renderTiles() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
        if Task.isCancelled { return }
        guard let sample = tileSample else { return }
        let source = ReelRenderer.Source(url: store.url(for: sample), date: sample.date)
        let base = tileKey.options

        var variants: [(String, ReelOptions)] = []
        switch tab {
        case .colors:
            for item in ReelOptions.ColorDepth.allCases {
                var o = base; o.colors = item
                variants.append(("colors." + item.rawValue, o))
            }
        case .filter:
            for item in ReelOptions.Filter.allCases {
                var o = base; o.filter = item
                variants.append(("filter." + item.rawValue, o))
            }
        case .date:
            guard base.stampFormat != .none else { return }
            for item in ReelOptions.StampStyle.allCases {
                // 色の違いが見えるよう、見本だけ日付を大きく中央に置く
                var o = base; o.stampStyle = item; o.stampLayout = .centerBig
                variants.append(("stamp." + item.rawValue, o))
            }
        case .range, .output:
            return
        }

        let work = Task.detached(priority: .userInitiated) { () -> [String: UIImage] in
            var out: [String: UIImage] = [:]
            for (key, o) in variants {
                if Task.isCancelled { return [:] }
                let renderer = ReelRenderer(sources: [source], options: o)
                if let cg = renderer.frame(at: 0) { out[key] = UIImage(cgImage: cg) }
            }
            return out
        }
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        if Task.isCancelled { return }
        tileImages.merge(result) { _, new in new }
    }

    // MARK: 範囲のえらび方

    @ViewBuilder
    private var rangeSection: some View {
        ChipRow(title: L("どこからどこまで"), items: Range.allCases, selection: $range) { $0.label }

        if range == .month {
            let choices = monthChoices
            if let first = choices.first {
                ChipRow(title: L("どの月"),
                        items: choices,
                        selection: Binding(
                            get: { choices.first { $0.id == activeMonth } ?? first },
                            set: { month = $0.id })) { $0.label }
            }
        }

        if range == .period {
            VStack(spacing: 10) {
                DatePicker(L("この日から"), selection: $periodFrom, in: ...Date(), displayedComponents: .date)
                DatePicker(L("この日まで"), selection: $periodTo, in: ...Date(), displayedComponents: .date)
            }
            .font(.subheadline.weight(.semibold))
            .environment(\.locale, L10n.locale)
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .padding(.horizontal, 20)
        }
    }

    /// 期間の初期値は「最初のスライスの日 〜 今日」。
    private func preparePeriod() {
        guard !periodReady else { return }
        periodReady = true
        periodFrom = store.slices.first?.date ?? Date()
        periodTo = Date()
    }

    // MARK: プレビュー

    private var previewArea: some View {
        ZStack {
            Color.black
            if frames.isEmpty {
                if rendering {
                    ProgressView()
                } else {
                    Text(L("この範囲にスライスがありません"))
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
        .frame(height: 260)
        .overlay(alignment: .bottomTrailing) {
            if chosen.count > Self.previewLimit {
                Text(L("プレビューは直近 %d コマ", Self.previewLimit))
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
                Text(exporting ? L("書き出し中…") : L("%d コマを %@ にする", chosen.count, options.format.label))
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
        let used = options
        let renderer = ReelRenderer(sources: sources(slices), options: used)
        let isVideo = used.format == .mp4
        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> (URL, CGImage?) in
                let url = try await renderer.export { value in
                    Task { @MainActor in exportProgress = value }
                }
                // 履歴の表紙用に 1 コマ目も渡す
                return (url, renderer.frame(at: 0))
            }.value

            // 次回のために、いまの設定を覚えておく
            used.saveAsLast()
            UserDefaults.standard.set(range.rawValue, forKey: Prefs.Key.lastReelRange)

            // 履歴に入れる（入れられなかったら一時ファイルのまま見せる）
            if let record = reels.add(exportedFile: result.0, poster: result.1, isVideo: isVideo,
                                      frameCount: slices.count, fps: used.speed.fps) {
                exported = ExportedReel(url: reels.url(for: record), isVideo: isVideo,
                                        bytes: record.bytes, frameCount: slices.count)
            } else {
                let bytes = (try? result.0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                exported = ExportedReel(url: result.0, isVideo: isVideo, bytes: bytes, frameCount: slices.count)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        exporting = false
    }
}

/// 書き出し後のシェア画面。いちばん下に、鏡へまっすぐ戻るボタンを置く。
private struct ExportedReelSheet: View {
    let reel: ReelStudioView.ExportedReel
    let onBackToMirror: () -> Void
    @State private var savedToPhotos: Bool?

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(reel.bytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text(L("できました"))
                .font(.title2.bold())
            Text(L("%d コマ・%@", reel.frameCount, sizeText))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ShareLink(item: reel.url) {
                Label(L("シェアする"), systemImage: "square.and.arrow.up")
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

            Button(action: onBackToMirror) {
                Label(L("鏡にもどる"), systemImage: "arrow.uturn.backward")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.white)

            Text(L("このリールは一覧の「これまでのリール」にも残っています。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }

    private var savedLabel: String {
        switch savedToPhotos {
        case .some(true): return L("「%@」に保存しました", PhotoAlbum.title)
        case .some(false): return L("保存できませんでした（写真へのアクセスを確認）")
        case .none: return L("写真に保存")
        }
    }
}

/// 見本の絵で 1 つ選ぶタイルの並び（3 列）。絵がまだ無いときは名前だけの枠を出す。
private struct TileGrid<Item: Identifiable & Equatable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    let image: (Item) -> UIImage?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    let selected = item == selection
                    Button {
                        selection = item
                    } label: {
                        VStack(spacing: 6) {
                            Color.clear
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                .overlay {
                                    ZStack {
                                        Theme.card
                                        if let picture = image(item) {
                                            Image(uiImage: picture)
                                                .interpolation(.none)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            ProgressView().controlSize(.small)
                                        }
                                    }
                                }
                                .clipShape(.rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(selected ? Theme.paper : .clear, lineWidth: 3)
                                }
                            Text(label(item))
                                .font(.system(size: 13, weight: selected ? .heavy : .semibold, design: .rounded))
                                .foregroundStyle(selected ? Theme.paper : .white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(item))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 20)
    }
}
