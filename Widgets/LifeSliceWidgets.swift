import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct LifeSliceWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestSliceWidget()
        SliceCountWidget()
        MirrorControl()
    }
}

// MARK: - データ

struct SliceEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
    let image: UIImage?
}

struct SliceProvider: TimelineProvider {
    func placeholder(in context: Context) -> SliceEntry {
        SliceEntry(date: Date(), state: WidgetState(count: 8, lastDate: Date(), reelThreshold: 12), image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SliceEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SliceEntry>) -> Void) {
        // アプリ側が保存のたびに reloadAllTimelines を呼ぶので、ここは 1 枚だけでよい。
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> SliceEntry {
        var image: UIImage?
        if let url = AppGroup.widgetLatestImageURL, let data = try? Data(contentsOf: url) {
            image = UIImage(data: data)
        }
        return SliceEntry(date: Date(), state: WidgetState.load(), image: image)
    }
}

private let accent = Color(red: 0.94, green: 0.36, blue: 0.24)
private let paper = Color(red: 0.96, green: 0.94, blue: 0.90)
private let ink = Color(red: 0.09, green: 0.085, blue: 0.08)

// MARK: - ホーム画面：最新のスライス

struct LatestSliceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestSlice", provider: SliceProvider()) { entry in
            LatestSliceView(entry: entry)
        }
        .configurationDisplayName("さっきの自分")
        .description("いちばん新しいスライスを表示します。タップで鏡がひらきます。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct LatestSliceView: View {
    let entry: SliceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 0) {
                    photo
                    summary
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                photo
                    .overlay(alignment: .bottomLeading) {
                        Text("\(entry.state.count)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .padding(12)
                    }
            }
        }
        .containerBackground(ink, for: .widget)
    }

    @ViewBuilder
    private var photo: some View {
        if let image = entry.image {
            Color.clear
                .overlay(Image(uiImage: image).resizable().scaledToFill())
                .clipped()
        } else {
            ZStack {
                paper
                Image(systemName: "face.dashed")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(ink.opacity(0.7))
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(entry.state.count)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("slices")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            Text(entry.state.remainingToReel == 0 ? "リールが作れます" : "リールまであと \(entry.state.remainingToReel)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
        }
    }
}

// MARK: - ロック画面：枚数

struct SliceCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SliceCount", provider: SliceProvider()) { entry in
            SliceCountView(entry: entry)
        }
        .configurationDisplayName("スライスの数")
        .description("たまった枚数と、リールまでの残り。タップで鏡がひらきます。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SliceCountView: View {
    let entry: SliceEntry
    @Environment(\.widgetFamily) private var family

    private var progress: Double {
        let threshold = max(entry.state.reelThreshold, 1)
        return min(1, Double(entry.state.count) / Double(threshold))
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "face.smiling")
                } currentValueLabel: {
                    Text("\(entry.state.count)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryInline:
                Label("\(entry.state.count) slices", systemImage: "face.smiling")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("LifeSlice", systemImage: "face.smiling")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("\(entry.state.count) slices")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text(entry.state.remainingToReel == 0 ? "リールが作れます" : "リールまであと \(entry.state.remainingToReel)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - コントロール（コントロールセンター／ロック画面下部／カメラコントロール）

struct MirrorControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.lifeslice.mirror.control") {
            ControlWidgetButton(action: MirrorCaptureIntent()) {
                Label("鏡をひらく", systemImage: "face.smiling")
            }
        }
        .displayName("LifeSlice Mirror")
        .description("鏡をすぐひらきます。")
    }
}
