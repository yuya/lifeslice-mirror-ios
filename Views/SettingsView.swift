import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var director: SliceDirector
    @EnvironmentObject private var reels: ReelArchive
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.Key.preWindow) private var preWindow = 3.0
    @AppStorage(Prefs.Key.postWindow) private var postWindow = 3.0
    @AppStorage(Prefs.Key.autoSlice) private var autoSlice = true
    @AppStorage(Prefs.Key.driftSlice) private var driftSlice = true
    @AppStorage(Prefs.Key.cooldown) private var cooldown = 30.0
    @AppStorage(Prefs.Key.sensitivity) private var sensitivity = 1
    @AppStorage(Prefs.Key.candidBias) private var candidBias = 2
    @AppStorage(Prefs.Key.saveToPhotos) private var saveToPhotos = false
    @AppStorage(Prefs.Key.quietMode) private var quietMode = false
    @AppStorage(Prefs.Key.reelThreshold) private var reelThreshold = 12
    @AppStorage(Prefs.Key.reelHistory) private var reelHistory = 8
    @AppStorage(Prefs.Key.language) private var language = "system"

    @State private var photosDenied = false

    private var windowSummary: String {
        if preWindow < 0.05 && postWindow < 0.05 {
            return L("振り幅ゼロ。止まった瞬間がそのまま残ります。")
        }
        return L("止まった瞬間の %.1f 秒前 〜 %.1f 秒後のどこか 1 コマが残ります。どれになるかは毎回くじ引きです。",
                 preWindow, postWindow)
    }

    private func cooldownLabel(_ seconds: Double) -> String {
        seconds >= 60 ? L("%d分", Int(seconds / 60)) : L("%d秒", Int(seconds))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("前"))
                            Spacer()
                            Text(L("−%.1f 秒", preWindow)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $preWindow, in: 0...Prefs.windowLimit, step: 0.5)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("後"))
                            Spacer()
                            Text(L("＋%.1f 秒", postWindow)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $postWindow, in: 0...Prefs.windowLimit, step: 0.5)
                    }
                } header: {
                    Text(L("不意打ちの振り幅"))
                } footer: {
                    Text(windowSummary)
                }

                Section {
                    Picker(L("隙のある顔"), selection: $candidBias) {
                        ForEach(CandidBias.allCases) { item in
                            Text(item.label).tag(item.rawValue)
                        }
                    }
                } header: {
                    Text(L("どのコマが選ばれやすいか"))
                } footer: {
                    Text(L("振り幅の中から、ブレている・目を閉じている・口が開いている・首が傾いているコマほど当たりやすくします。あくまでくじ引きなので、キメ顔が選ばれることもあります。"))
                }

                Section {
                    Toggle(L("止まったら自動で撮る"), isOn: $autoSlice)
                    if autoSlice {
                        Picker(L("止まった判定"), selection: $sensitivity) {
                            ForEach(StillnessDetector.Sensitivity.allCases) { item in
                                Text(item.label).tag(item.rawValue)
                            }
                        }
                        Picker(L("次に撮るまでの間隔"), selection: $cooldown) {
                            ForEach(Prefs.cooldownChoices, id: \.self) { seconds in
                                Text(cooldownLabel(seconds)).tag(seconds)
                            }
                        }
                    }
                    Toggle(L("止まらなくても 1 枚もらう"), isOn: $driftSlice)
                } header: {
                    Text(L("勝手にたまる仕組み"))
                } footer: {
                    Text(L("顔が映った状態で手が止まると自動で撮ります。一度も撮れないまま閉じたときは、開いていた間の映像から適当に 1 コマだけ残します。顔のあたりが暗いコマ、カメラを開いた直後のコマは残しません。残さなかった映像はその場で捨てています。"))
                }

                Section {
                    Toggle(L("写真アプリにも保存"), isOn: $saveToPhotos)
                        .onChange(of: saveToPhotos) { _, on in
                            guard on else { return }
                            Task {
                                if await PhotoAlbum.requestAccess() == false {
                                    saveToPhotos = false
                                    photosDenied = true
                                }
                            }
                        }
                } header: {
                    Text(L("保存"))
                } footer: {
                    Text(L("スライスはいつもアプリの中に残ります。オンにすると、写真アプリの「%@」アルバムにも同じものを入れます。", PhotoAlbum.title))
                }

                Section {
                    Toggle(L("撮れたことを知らせない"), isOn: $quietMode)
                } header: {
                    Text(L("鏡"))
                } footer: {
                    Text(L("ふだんは撮れた瞬間に画面が一瞬白く光ります。"))
                }

                Section {
                    Stepper(L("%d 枚たまったら", reelThreshold), value: $reelThreshold, in: 4...60)
                        .onChange(of: reelThreshold) { _, _ in director.store.publishToWidget() }
                } header: {
                    Text(L("リールが作れるようになる枚数"))
                }

                Section {
                    Picker(L("残す本数"), selection: $reelHistory) {
                        ForEach(Prefs.reelHistoryChoices, id: \.self) { count in
                            Text(L("%d 本", count)).tag(count)
                        }
                    }
                    .onChange(of: reelHistory) { _, _ in reels.prune() }
                } header: {
                    Text(L("リールの履歴"))
                } footer: {
                    Text(L("書き出したリールをアプリ内に残します。本数を超えたぶんと、合計が %@ を超えたぶんは古い順に消えます。いまは %d 本・%@ です。",
                           ByteCountFormatter.string(fromByteCount: Int64(ReelArchive.byteLimit), countStyle: .file),
                           reels.records.count,
                           ByteCountFormatter.string(fromByteCount: Int64(reels.totalBytes), countStyle: .file)))
                }

                Section {
                    Picker(L("言語"), selection: $language) {
                        Text(L("iPhone の設定に合わせる")).tag("system")
                        Text("日本語").tag("ja")
                        Text("English").tag("en")
                    }
                    Button(L("iPhone の設定アプリで変える")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text(L("言語"))
                } footer: {
                    Text(L("ウィジェットとロック画面の表示は iPhone の設定に従います。"))
                }

                #if DEBUG
                Section(L("開発用")) {
                    Button(L("ダミーのスライスを 24 枚つくる")) { director.seedDemoSlices() }
                }
                #endif
            }
            .navigationTitle(L("設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("閉じる")) { dismiss() }
                }
            }
            .alert(L("写真へのアクセスが許可されていません"), isPresented: $photosDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(L("設定アプリで写真へのアクセスを許可すると使えます。"))
            }
        }
        .preferredColorScheme(.dark)
    }
}
