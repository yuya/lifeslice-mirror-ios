import AVKit
import SwiftUI
import UIKit

/// メイン画面。まず鏡であること。
struct MirrorView: View {
    @EnvironmentObject private var director: SliceDirector
    @EnvironmentObject private var engine: CameraEngine
    @EnvironmentObject private var store: SliceStore

    @AppStorage(Prefs.Key.showGuides) private var showGuides = false
    @AppStorage(Prefs.Key.quietMode) private var quietMode = false

    private enum Tool { case zoom, brightness, light }
    private enum LightTone: CaseIterable {
        case warm, neutral, cool
        var color: Color {
            switch self {
            case .warm: return Color(red: 1.0, green: 0.86, blue: 0.70)
            case .neutral: return Color(red: 1.0, green: 0.97, blue: 0.93)
            case .cool: return Color(red: 0.86, green: 0.93, blue: 1.0)
            }
        }
    }

    @State private var tool: Tool?
    @State private var chromeHidden = false
    @State private var lightOn = false
    @State private var lightTone: LightTone = .warm
    @State private var pinchBase: CGFloat?
    @State private var showGallery = false
    @State private var showSettings = false
    @State private var plusOne = false
    @State private var shutterPulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            preview

            if lightOn { lightFrame }
            if showGuides { guides }

            if engine.authorization == .denied || engine.authorization == .restricted {
                notice(title: "カメラが使えません",
                       message: "鏡になるにはカメラへのアクセスが必要です。",
                       button: "設定をひらく") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else if !engine.hasCamera {
                notice(title: "インカメラが見つかりません",
                       message: "シミュレータでは鏡は映りません。実機で試してください。",
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
        }
        .statusBarHidden(chromeHidden)
        .persistentSystemOverlays(chromeHidden ? .hidden : .automatic)
        // カメラコントロール／音量ボタンをシャッターにする
        .onCameraCaptureEvent { event in
            if event.phase == .ended { fireShutter() }
        }
        .onChange(of: director.savedTick) { _, _ in
            guard !quietMode else { return }
            withAnimation(.spring(duration: 0.35)) { plusOne = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation(.easeOut(duration: 0.4)) { plusOne = false }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: quietMode ? 0 : director.savedTick)
        .onChange(of: lightOn) { _, on in ScreenLight.set(on: on) }
        .fullScreenCover(isPresented: $showGallery, onDismiss: { director.setMirrorVisible(true) }) {
            GalleryView()
                .environmentObject(director)
                .environmentObject(store)
                .tint(Theme.accent)
                .fontDesign(.rounded)
        }
        .sheet(isPresented: $showSettings, onDismiss: { director.setMirrorVisible(true) }) {
            SettingsView()
                .environmentObject(director)
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

    private var lightFrame: some View {
        Rectangle()
            .strokeBorder(lightTone.color, lineWidth: 56)
            .blur(radius: 3)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var guides: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                path.move(to: CGPoint(x: 0, y: geo.size.height * 0.45))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.45))
            }
            .stroke(.white.opacity(0.55), lineWidth: 0.75)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
            Text("LifeSlice")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            Spacer()
            if engine.isFrozen {
                Label("とめています", systemImage: "pause.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassCapsule()
            }
            Spacer()
            ToolButton(symbol: "gearshape.fill") {
                director.setMirrorVisible(false)
                showSettings = true
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    // MARK: 下

    private var bottomTray: some View {
        VStack(spacing: 14) {
            if let tool {
                toolPanel(tool)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ToolButton(symbol: "plus.magnifyingglass",
                               text: engine.zoom > 1.04 ? String(format: "%.1f×", engine.zoom) : nil,
                               isOn: tool == .zoom) { toggle(.zoom) }
                    ToolButton(symbol: "sun.max.fill", isOn: tool == .brightness) { toggle(.brightness) }
                    ToolButton(symbol: lightOn ? "lightbulb.fill" : "lightbulb", isOn: lightOn) { toggle(.light) }
                    ToolButton(symbol: engine.isFrozen ? "play.fill" : "pause.fill", isOn: engine.isFrozen) {
                        engine.setFrozen(!engine.isFrozen)
                    }
                    ToolButton(symbol: "plus.viewfinder", isOn: showGuides) { showGuides.toggle() }
                }
            }

            HStack {
                galleryButton
                Spacer()
                shutterButton
                Spacer()
                modeSwitch
            }
            .padding(.horizontal, 26)
        }
        .padding(.bottom, 14)
    }

    private func toggle(_ next: Tool) {
        withAnimation(.snappy(duration: 0.25)) {
            if next == .light {
                // 1 回目で点灯＋色選び、パネルが出ている状態でもう一度押すと消灯
                if !lightOn {
                    lightOn = true
                    tool = .light
                } else if tool == .light {
                    lightOn = false
                    tool = nil
                } else {
                    tool = .light
                }
            } else {
                tool = (tool == next) ? nil : next
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
            case .brightness:
                Image(systemName: "sun.min.fill")
                Slider(value: Binding(get: { Double(engine.exposureBias) },
                                      set: { engine.setExposureBias(Float($0)) }),
                       in: -2...2)
                Image(systemName: "sun.max.fill")
            case .light:
                Text("ライトの色").font(.subheadline.weight(.semibold))
                Spacer()
                ForEach(Array(LightTone.allCases.enumerated()), id: \.offset) { _, tone in
                    Button {
                        lightTone = tone
                    } label: {
                        Circle()
                            .fill(tone.color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white, lineWidth: lightTone == tone ? 2.5 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 54)
        .glassPanel(cornerRadius: 27)
        .padding(.horizontal, 22)
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

                if plusOne {
                    Text("+1")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.accent, in: .capsule)
                        .offset(x: 12, y: -12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("スライス一覧、\(store.slices.count) 枚")
    }

    private var shutterButton: some View {
        Button(action: fireShutter) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                Circle().fill(.white).frame(width: 60, height: 60)
                    .scaleEffect(shutterPulse ? 0.86 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("シャッター")
    }

    private var modeSwitch: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                engine.mode = engine.mode == .mirror ? .trueView : .mirror
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(engine.mode.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(engine.mode == .trueView ? Theme.accent : .white)
            .frame(width: 52, height: 52)
            .glassButton()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("左右の切り替え、いまは\(engine.mode.label)")
    }

    private func fireShutter() {
        director.shutter()
        // 押した手応えだけ返す。どのコマが残るかは教えない。
        withAnimation(.easeOut(duration: 0.08)) { shutterPulse = true }
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeOut(duration: 0.15)) { shutterPulse = false }
        }
    }
}
