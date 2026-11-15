import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var director: SliceDirector
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.Key.preWindow) private var preWindow = 1.5
    @AppStorage(Prefs.Key.postWindow) private var postWindow = 1.5
    @AppStorage(Prefs.Key.autoSlice) private var autoSlice = true
    @AppStorage(Prefs.Key.driftSlice) private var driftSlice = true
    @AppStorage(Prefs.Key.cooldown) private var cooldown = 30.0
    @AppStorage(Prefs.Key.sensitivity) private var sensitivity = 1
    @AppStorage(Prefs.Key.saveToPhotos) private var saveToPhotos = false
    @AppStorage(Prefs.Key.quietMode) private var quietMode = false
    @AppStorage(Prefs.Key.showGuides) private var showGuides = false
    @AppStorage(Prefs.Key.reelThreshold) private var reelThreshold = 12

    @State private var photosDenied = false

    private var windowSummary: String {
        if preWindow < 0.05 && postWindow < 0.05 {
            return "振り幅ゼロ。押した瞬間がそのまま残ります。"
        }
        return String(format: "押した瞬間の %.1f 秒前 〜 %.1f 秒後のどこか 1 コマが残ります。どれになるかは毎回くじ引きです。",
                      preWindow, postWindow)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("前")
                            Spacer()
                            Text(String(format: "−%.1f 秒", preWindow)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $preWindow, in: 0...3, step: 0.1)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("後")
                            Spacer()
                            Text(String(format: "＋%.1f 秒", postWindow)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $postWindow, in: 0...3, step: 0.1)
                    }
                } header: {
                    Text("不意打ちの振り幅")
                } footer: {
                    Text(windowSummary)
                }

                Section {
                    Toggle("止まったら自動で撮る", isOn: $autoSlice)
                    if autoSlice {
                        Picker("止まった判定", selection: $sensitivity) {
                            ForEach(StillnessDetector.Sensitivity.allCases) { item in
                                Text(item.label).tag(item.rawValue)
                            }
                        }
                        Picker("次に撮るまでの間隔", selection: $cooldown) {
                            Text("10秒").tag(10.0)
                            Text("30秒").tag(30.0)
                            Text("1分").tag(60.0)
                            Text("5分").tag(300.0)
                        }
                    }
                    Toggle("止まらなくても 1 枚もらう", isOn: $driftSlice)
                } header: {
                    Text("勝手にたまる仕組み")
                } footer: {
                    Text("顔が映った状態で手が止まると自動で撮ります。一度も撮れないまま閉じたときは、開いていた間の映像から適当に 1 コマだけ残します。残さなかった映像はその場で捨てています。")
                }

                Section {
                    Toggle("写真アプリにも保存", isOn: $saveToPhotos)
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
                    Text("保存")
                } footer: {
                    Text("スライスはいつもアプリの中に残ります。オンにすると、写真アプリの「\(PhotoAlbum.title)」アルバムにも同じものを入れます。")
                }

                Section("鏡") {
                    Toggle("撮れたことを知らせない", isOn: $quietMode)
                    Toggle("ガイド線", isOn: $showGuides)
                }

                Section {
                    Stepper("\(reelThreshold) 枚たまったら", value: $reelThreshold, in: 4...60)
                        .onChange(of: reelThreshold) { _, _ in director.store.publishToWidget() }
                } header: {
                    Text("リールが作れるようになる枚数")
                }

                #if DEBUG
                Section("開発用") {
                    Button("ダミーのスライスを 24 枚つくる") { director.seedDemoSlices() }
                }
                #endif
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("写真へのアクセスが許可されていません", isPresented: $photosDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("設定アプリで写真へのアクセスを許可すると使えます。")
            }
        }
        .preferredColorScheme(.dark)
    }
}
