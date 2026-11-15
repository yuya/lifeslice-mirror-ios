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
        let id: String
        let title: String
        let slices: [Slice]
    }

    private var months: [Month] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        let grouped = Dictionary(grouping: store.slices) { slice -> DateComponents in
            calendar.dateComponents([.year, .month], from: slice.date)
        }
        return grouped
            .compactMap { key, value -> (Date, [Slice])? in
                guard let date = calendar.date(from: key) else { return nil }
                return (date, value.sorted { $0.date > $1.date })
            }
            .sorted { $0.0 > $1.0 }
            .map { Month(id: formatter.string(from: $0.0), title: formatter.string(from: $0.0), slices: $0.1) }
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
            .navigationTitle("スライス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("鏡にもどる", systemImage: "chevron.down") { dismiss() }
                }
            }
            .sheet(item: $selected) { slice in
                SliceDetailView(slice: slice)
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
                    Text(slice.date, format: .dateTime.day())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                        .padding(5)
                }
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
                Text("もう十分たまってます。ぱらぱら動かしてみましょう。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showStudio = true
                } label: {
                    Label("リールにする", systemImage: "film.stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else {
                ProgressView(value: Double(count), total: Double(max(threshold, 1)))
                    .tint(Theme.accent)
                Text("あと \(threshold - count) 枚でリールが作れます。鏡を見るたびに勝手にたまります。")
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
            Text("まだ 1 枚もありません")
                .font(.headline)
            Text("いつもどおり鏡として使ってください。\n止まった瞬間の前後から、こっそり 1 コマもらいます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
        .padding(.horizontal, 30)
    }
}

/// 1 枚を大きく見る。
struct SliceDetailView: View {
    let slice: Slice
    @EnvironmentObject private var store: SliceStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Theme.card
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .clipShape(.rect(cornerRadius: 22))
            .padding(.horizontal, 16)
            .padding(.top, 20)

            VStack(spacing: 4) {
                Text(slice.date, format: .dateTime.year().month().day().weekday().hour().minute())
                    .font(.headline)
                Text(slice.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ShareLink(item: store.url(for: slice)) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("捨てる", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .confirmationDialog("このスライスを捨てますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("捨てる", role: .destructive) {
                store.delete(slice)
                dismiss()
            }
        }
        .task {
            let url = store.url(for: slice)
            image = await Task.detached { () -> UIImage? in
                guard let cg = ImageLoader.downsampled(url: url, maxPixel: 1600) else { return nil }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}
