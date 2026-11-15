import SwiftUI
import UIKit

/// たまったスライスの一覧。ここからリール作りへ。
struct GalleryView: View {
    @EnvironmentObject private var store: SliceStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.Key.reelThreshold) private var threshold = 12

    @State private var selected: Slice?
    @State private var showStudio = false

    private struct Month: Identifiable {
        let id: Date
        let title: String
        let slices: [Slice]
    }

    private var months: [Month] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.slices) { slice -> DateComponents in
            calendar.dateComponents([.year, .month], from: slice.date)
        }
        return grouped
            .compactMap { key, value -> (Date, [Slice])? in
                guard let date = calendar.date(from: key) else { return nil }
                return (date, value.sorted { $0.date > $1.date })
            }
            .sorted { $0.0 > $1.0 }
            .map { entry in
                Month(id: entry.0,
                      title: entry.0.formatted(.dateTime.year().month(.wide).locale(L10n.locale)),
                      slices: entry.1)
            }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    reelCard
                        .padding(.horizontal, 16)

                    if store.slices.isEmpty {
                        emptyState
                    }

                    ForEach(months) { month in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(month.title).font(.headline)
                                Text("\(month.slices.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(month.slices) { slice in
                                    cell(slice)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Theme.ink)
            .navigationTitle(L("スライス"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("鏡にもどる"), systemImage: "chevron.down") { dismiss() }
                }
            }
            .sheet(item: $selected) { slice in
                SlicePagerView(startAt: slice)
                    .environmentObject(store)
                    .tint(Theme.accent)
                    .fontDesign(.rounded)
            }
            .navigationDestination(isPresented: $showStudio) {
                ReelStudioView()
                    .environmentObject(store)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func cell(_ slice: Slice) -> some View {
        Button {
            selected = slice
        } label: {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay(SliceThumb(slice: slice, url: store.url(for: slice)))
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("\(Calendar.current.component(.day, from: slice.date))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                        .padding(5)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var reelCard: some View {
        let count = store.slices.count
        let ready = count >= threshold
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("slices")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if ready {
                Text(L("もう十分たまってます。ぱらぱら動かしてみましょう。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showStudio = true
                } label: {
                    Label(L("リールにする"), systemImage: "film.stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else {
                ProgressView(value: Double(count), total: Double(max(threshold, 1)))
                    .tint(Theme.accent)
                Text(L("あと %d 枚でリールが作れます。鏡を見るたびに勝手にたまります。", threshold - count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 24))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "face.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(L("まだ 1 枚もありません"))
                .font(.headline)
            Text(L("いつもどおり鏡として使ってください。\n止まった瞬間の前後から、こっそり 1 コマもらいます。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
        .padding(.horizontal, 30)
    }
}

/// 1 枚を大きく見る。左右スワイプで前後のスライスへ。
struct SlicePagerView: View {
    @EnvironmentObject private var store: SliceStore
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID
    @State private var confirmDelete = false

    init(startAt slice: Slice) {
        _currentID = State(initialValue: slice.id)
    }

    /// 一覧と同じく新しい順。
    private var ordered: [Slice] { store.slices.reversed() }
    private var current: Slice? { store.slices.first { $0.id == currentID } }

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $currentID) {
                ForEach(ordered) { slice in
                    SlicePage(url: store.url(for: slice))
                        .padding(.horizontal, 16)
                        .tag(slice.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .padding(.top, 20)

            if let current {
                VStack(spacing: 4) {
                    Text(current.date.formatted(.dateTime.year().month().day().weekday().hour().minute()
                        .locale(L10n.locale)))
                        .font(.headline)
                    Text(current.caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let index = ordered.firstIndex(where: { $0.id == current.id }) {
                        Text("\(index + 1) / \(ordered.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 12) {
                    ShareLink(item: store.url(for: current)) {
                        Label(L("共有"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(L("捨てる"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .confirmationDialog(L("このスライスを捨てますか？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("捨てる"), role: .destructive) { deleteCurrent() }
        }
    }

    private func deleteCurrent() {
        guard let current, let index = ordered.firstIndex(where: { $0.id == current.id }) else { return }
        // 捨てたあとは隣のスライスへ。最後の 1 枚なら閉じる。
        let list = ordered
        let neighbor = index + 1 < list.count ? list[index + 1] : (index > 0 ? list[index - 1] : nil)
        store.delete(current)
        if let neighbor {
            currentID = neighbor.id
        } else {
            dismiss()
        }
    }
}

private struct SlicePage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.clear
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 22))
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            let target = url
            image = await Task.detached { () -> UIImage? in
                guard let cg = ImageLoader.downsampled(url: target, maxPixel: 1600) else { return nil }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}
