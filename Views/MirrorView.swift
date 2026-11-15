import AVKit
import SwiftUI
import UIKit

/// メイン画面。まず鏡であること。撮影ボタンは置かない（スライスは勝手にたまる）。
struct MirrorView: View {
    @EnvironmentObject private var director: SliceDirector
    @EnvironmentObject private var engine: CameraEngine
    @EnvironmentObject private var store: SliceStore
    @EnvironmentObject private var reels: ReelArchive

    @AppStorage(Prefs.Key.quietMode) private var quietMode = false
    @Environment(\.scenePhase) private var scenePhase

    private enum Tool { case zoom, brightness }

    @State private var tool: Tool?
    @State private var chromeHidden = false
    @State private var lightOn = false
    @State private var flash = false
    @State private var pinchBase: CGFloat?
    @State private var showGallery = false
    @State private var showSettings = false
    @State private var plusOne = false
    @State private var modeToast: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            preview

            if engine.authorization == .denied || engine.authorization == .restricted {
                notice(title: L("カメラが使えません"),
                       message: L("鏡になるにはカメラへのアクセスが必要です。"),
                       button: L("設定をひらく")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else if !engine.hasCamera {
                notice(title: L("インカメラが見つかりません"),
                       message: L("シミュレータでは鏡は映りません。実機で試してください。"),
                       button: nil, action: {})
            }

            if !chromeHidden {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomTray
                }
                .transition(.opacity)
            }

            // 撮れた合図。Photo Booth のように一瞬だけ画面を白くする。
            Color.white
                .opacity(flash ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .statusBarHidden(chromeHidden)
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
        // カメラコントロール／音量ボタンは「一時停止」の切り替え（撮影ではない）
        .onCameraCaptureEvent { event in
            if event.phase == .ended { engine.setFrozen(!engine.isFrozen) }
        }
        .onChange(of: director.savedTick) { _, _ in
            guard !quietMode else { return }
            flash = true
            Task {
                try? await Task.sleep(nanoseconds: 70_000_000)
                withAnimation(.easeOut(duration: 0.45)) { flash = false }
            }
            withAnimation(.spring(duration: 0.35)) { plusOne = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation(.easeOut(duration: 0.4)) { plusOne = false }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: quietMode ? 0 : director.savedTick)
        .onChange(of: lightOn) { _, on in ScreenLight.set(on: on) }
        // アプリを離れている間は画面の明るさを元に戻し、戻ってきたら点け直す
        .onChange(of: scenePhase) { _, phase in ScreenLight.set(on: lightOn && phase == .active) }
        .onDisappear { ScreenLight.set(on: false) }
        .fullScreenCover(isPresented: $showGallery, onDismiss: { director.setMirrorVisible(true) }) {
            GalleryView()
                .environmentObject(director)
                .environmentObject(store)
                .environmentObject(reels)
                .environment(\.returnToMirror, { showGallery = false })
                .tint(Theme.accent)
                .fontDesign(.rounded)
        }
        .sheet(isPresented: $showSettings, onDismiss: { director.setMirrorVisible(true) }) {
            SettingsView()
                .environmentObject(director)
                .environmentObject(reels)
                .tint(Theme.accent)
                .fontDesign(.rounded)
        }
    }

    // MARK: 鏡

    private var preview: some View {
        CameraPreview(engine: engine)
            // プレビューは標準で鏡像。「相手から」は左右を戻す。
            .scaleEffect(x: engine.mode == .trueView ? -1 : 1, y: 1)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if tool != nil { tool = nil } else { chromeHidden.toggle() }
                }
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? engine.zoom
                        pinchBase = base
                        engine.setZoom(base * value.magnification)
                    }
                    .onEnded { _ in pinchBase = nil }
            )
    }

    private func notice(title: String, message: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let button {
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .glassPanel()
        .padding(32)
    }

    // MARK: 上

    private var topBar: some View {
        HStack {
            Text("LifeSlice Mirror")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            Spacer()
            ToolButton(symbol: "gearshape.fill") {
                director.setMirrorVisible(false)
                showSettings = true
            }
        }
        .overlay {
            // 状態のひとこと（一時停止中／左右を切り替えた直後）
            if engine.isFrozen {
                statusCapsule(L("とめています"), symbol: "pause.fill")
            } else if let modeToast {
                statusCapsule(modeToast, symbol: "arrow.left.and.right")
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func statusCapsule(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassCapsule()
            .allowsHitTesting(false)
    }

    // MARK: 下

    private var bottomTray: some View {
        VStack(spacing: 12) {
            if let tool {
                toolPanel(tool)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                galleryButton
                Spacer(minLength: 0)
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ToolButton(symbol: "plus.magnifyingglass",
                                   text: engine.zoom > 1.04 ? String(format: "%.1f×", engine.zoom) : nil,
                                   isOn: tool == .zoom) { toggle(.zoom) }
                        ToolButton(symbol: "sun.max.fill",
                                   isOn: tool == .brightness || abs(engine.exposureBias) > 0.05) { toggle(.brightness) }
                        ToolButton(symbol: lightOn ? "lightbulb.fill" : "lightbulb", isOn: lightOn) { lightOn.toggle() }
                        ToolButton(symbol: engine.isFrozen ? "play.fill" : "pause.fill", isOn: engine.isFrozen) {
                            engine.setFrozen(!engine.isFrozen)
                        }
                        ToolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
                                   isOn: engine.mode == .trueView) { flipMode() }
                            .accessibilityLabel(L("左右の切り替え、いまは%@", engine.mode.label))
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 14)
    }

    private func toggle(_ next: Tool) {
        withAnimation(.snappy(duration: 0.25)) {
            tool = (tool == next) ? nil : next
        }
    }

    private func flipMode() {
        engine.mode = engine.mode == .mirror ? .trueView : .mirror
        let label = engine.mode.label
        withAnimation(.easeOut(duration: 0.15)) { modeToast = label }
        Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            // その間にもう一度切り替えていたら、新しいほうの表示を消さない
            if modeToast == label {
                withAnimation(.easeOut(duration: 0.3)) { modeToast = nil }
            }
        }
    }

    @ViewBuilder
    private func toolPanel(_ tool: Tool) -> some View {
        HStack(spacing: 12) {
            switch tool {
            case .zoom:
                Image(systemName: "minus.magnifyingglass")
                Slider(value: Binding(get: { engine.zoom }, set: { engine.setZoom($0) }),
                       in: 1...max(1.01, engine.maxZoom))
                Image(systemName: "plus.magnifyingglass")
                resetButton(isDefault: engine.zoom < 1.01) { engine.setZoom(1) }
            case .brightness:
                Image(systemName: "sun.min.fill")
                Slider(value: Binding(get: { Double(engine.exposureBias) },
                                      set: { engine.setExposureBias(Float($0)) }),
                       in: -2...2)
                Image(systemName: "sun.max.fill")
                resetButton(isDefault: abs(engine.exposureBias) < 0.01) { engine.setExposureBias(0) }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 54)
        .glassPanel(cornerRadius: 27)
        .padding(.horizontal, 16)
    }

    /// スライダーを初期値に戻すボタン。すでに初期値のときは薄く表示する。
    private func resetButton(isDefault: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isDefault ? .white.opacity(0.35) : Theme.accent)
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(isDefault)
        .accessibilityLabel(L("初期値に戻す"))
    }

    private var galleryButton: some View {
        Button {
            director.setMirrorVisible(false)
            showGallery = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let latest = store.latest {
                        SliceThumb(slice: latest, url: store.url(for: latest), maxPixel: 200)
                    } else {
                        ZStack {
                            Theme.card
                            Image(systemName: "square.stack")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                .padding(6)

                if plusOne {
                    Text("+1")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.accent, in: .capsule)
                        .offset(x: 8, y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("スライス一覧、%d 枚", store.slices.count))
    }
}
