import Combine
import LockedCameraCapture
import QuartzCore
import SwiftUI
import UIKit

/// 「いつ・どのコマを残すか」を決める係。
/// - 静止を検知 → その瞬間の前後の振り幅からランダムに 1 コマ（暗すぎるコマは残さない）
/// - 何も撮れないままアプリがバックグラウンドへ → 立ち去り際にバッファから 1 コマ
///   （アプリ内で一覧やリールを開いただけでは立ち去り扱いにしない）
/// - 鏡が見えなくなったらバッファは必ず捨てる（映像は溜め込まない）
/// - 「次に撮るまでの間隔」は鏡が見えている間だけ進む
@MainActor
final class SliceDirector: ObservableObject {
    let engine = CameraEngine()
    let store = SliceStore()
    let reels = ReelArchive()

    /// 直近に保存されたスライス（「＋1」の合図用）。
    @Published private(set) var lastSaved: Slice?
    @Published private(set) var savedTick = 0

    private struct Pending {
        let id = UUID()
        let pressedAt: TimeInterval
        let date: Date
        let source: Slice.Source
        let pre: Double
        let post: Double
    }

    private let detector = StillnessDetector()
    private var pending: [Pending] = []
    private var sessionStartedAt: TimeInterval?
    private var slicesThisSession = 0
    private var lastAutoAt: TimeInterval = 0
    private var cancellables: Set<AnyCancellable> = []

    init() {
        Prefs.register()
        detector.onStill = { [weak self] in self?.handleStill() }
        // コマごとのブレ具合を、静止検知と同じセンサーから渡す
        let detector = self.detector
        engine.motionProvider = { detector.latestRotation }
        // engine の変化（ズームや顔検出）を画面に伝える。
        engine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        Task { await self.watchLockedCaptures() }
    }

    // MARK: 画面の出入り

    private var sceneActive = false
    private var mirrorVisible = true
    private var lastDriftAt: TimeInterval = 0
    /// アプリ内で一覧・リール・設定を開いた時刻。その間は間隔のカウントを止める。
    private var hiddenAt: TimeInterval?

    /// アプリが前面かどうか。
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        reconcile()
    }

    /// 鏡の画面が見えているかどうか（一覧や設定を開いている間は撮らない）。
    func setMirrorVisible(_ visible: Bool) {
        let now = CACurrentMediaTime()
        if !visible, mirrorVisible {
            hiddenAt = now
        } else if visible, !mirrorVisible, let hiddenAt {
            // 開いていた時間ぶん、前回の自動撮影を後ろへずらす（＝カウントを止めていたことにする）
            lastAutoAt += now - hiddenAt
            self.hiddenAt = nil
        }
        mirrorVisible = visible
        reconcile()
    }

    private func reconcile() {
        if sceneActive && mirrorVisible {
            becomeActive()
        } else {
            // 立ち去りスライスは、アプリ自体がバックグラウンドへ行くときだけ
            resignActive(leavingApp: !sceneActive)
        }
    }

    private func becomeActive() {
        guard sessionStartedAt == nil else { return }
        sessionStartedAt = CACurrentMediaTime()
        slicesThisSession = 0
        // 抽選は「後」の秒数が過ぎてから行うので、前後ぶん＋余裕を持っておく。
        engine.buffer.keepSeconds = max(Prefs.preWindow + Prefs.postWindow + 1.5, 6.0)
        engine.start()
        detector.sensitivity = StillnessDetector.Sensitivity(rawValue: Prefs.sensitivity) ?? .normal
        detector.start()
    }

    /// 鏡が見えなくなる瞬間。アプリがバックグラウンドへ行くときは、ここが「バックグラウンド処理」の実体。
    private func resignActive(leavingApp: Bool) {
        guard let startedAt = sessionStartedAt else { return }
        sessionStartedAt = nil
        detector.stop()

        // 抽選待ちのものは、いま手元にあるコマの範囲で確定させる。
        for item in pending { resolve(item) }
        pending.removeAll()

        // 一度も撮れていなければ、立ち去りスライス。
        // 通知センターを覗いただけ、のような出入りで増えすぎないよう 1 分に 1 枚まで。
        let now = CACurrentMediaTime()
        let lingered = now - startedAt
        if leavingApp, Prefs.driftSlice, slicesThisSession == 0, lingered > 1.5, now - lastDriftAt > 60, !engine.isFrozen {
            let candidates = engine.buffer.driftCandidates()
            if !candidates.isEmpty {
                lastDriftAt = now
                slicesThisSession += 1
                choose(from: candidates) { [weak self] frame in
                    self?.save(frame: frame, source: .drift, offset: nil, date: Date())
                }
            }
        }

        // 映像は持ち越さない。
        if engine.isFrozen { engine.setFrozen(false) }
        engine.buffer.clear()
        engine.stop()
    }

    // MARK: 撮る

    private func handleStill() {
        guard Prefs.autoSlice, sessionStartedAt != nil, !engine.isFrozen else { return }
        guard engine.faceVisible, !engine.tooDark else { return }
        let now = CACurrentMediaTime()
        guard now - lastAutoAt >= Prefs.cooldown else { return }
        lastAutoAt = now
        schedule(source: .still)
    }

    private func schedule(source: Slice.Source) {
        guard sessionStartedAt != nil, !engine.isFrozen else { return }
        let item = Pending(pressedAt: CACurrentMediaTime(), date: Date(), source: source,
                           pre: Prefs.preWindow, post: Prefs.postWindow)
        pending.append(item)
        // 「後」の振り幅ぶん待ってから選ぶ。
        let wait = item.post + 0.15
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self else { return }
            guard let index = self.pending.firstIndex(where: { $0.id == item.id }) else { return }
            self.pending.remove(at: index)
            self.resolve(item)
        }
    }

    private func resolve(_ item: Pending) {
        let candidates = engine.buffer.candidates(from: item.pressedAt - item.pre,
                                                  to: item.pressedAt + item.post)
        guard !candidates.isEmpty else { return }
        // 採点は少し時間がかかるので、数えるのは先に（立ち去りスライスと二重にならないよう）
        slicesThisSession += 1
        choose(from: candidates) { [weak self] frame in
            let offset = frame.time - item.pressedAt
            self?.save(frame: frame, source: item.source, offset: offset,
                       date: item.date.addingTimeInterval(offset))
        }
    }

    /// 候補を採点してくじを引く（顔の検出をするのでメインスレッドの外で）。
    /// アプリがバックグラウンドへ行く途中でも終わるよう、少しだけ猶予をもらう。
    private func choose(from candidates: [SurpriseBuffer.Frame],
                        then done: @escaping @MainActor (SurpriseBuffer.Frame) -> Void) {
        let bias = CandidBias(rawValue: Prefs.candidBias) ?? .strong
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
        Task.detached(priority: .userInitiated) {
            let frame = CandidScorer.choose(candidates, bias: bias)
            await MainActor.run {
                if let frame { done(frame) }
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            }
        }
    }

    private func save(frame: SurpriseBuffer.Frame, source: Slice.Source, offset: Double?, date: Date) {
        guard let slice = store.add(jpeg: frame.jpeg, date: date, source: source, offset: offset) else { return }
        lastSaved = slice
        savedTick += 1
    }

    // MARK: ロック中に撮ったぶんの取り込み

    private func watchLockedCaptures() async {
        for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
            switch update {
            case .initial(let urls):
                // 起動時点ですでにたまっていたぶん
                for url in urls { await ingestLockedSession(at: url) }
            case .added(let url):
                await ingestLockedSession(at: url)
            default:
                break
            }
        }
    }

    private func ingestLockedSession(at url: URL) async {
        importLockedContent(at: url)
        try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: url)
    }

    private func importLockedContent(at directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files where file.pathExtension.lowercased() == "jpg" {
            guard let data = try? Data(contentsOf: file) else { continue }
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            // ファイル名は "<UUID>_<offset>.jpg"
            let parts = file.deletingPathExtension().lastPathComponent.split(separator: "_")
            let offset = parts.count > 1 ? Double(parts[1]) : nil
            _ = store.add(jpeg: data, date: created, source: .locked, offset: offset)
        }
    }

    // MARK: デバッグ

    #if DEBUG
    /// シミュレータ等でリール作りを試すためのダミー。
    func seedDemoSlices(count: Int = 24) {
        let size = CGSize(width: 540, height: 960)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        for i in 0..<count {
            let hue = CGFloat(i) / CGFloat(count)
            let image = renderer.image { ctx in
                let colors = [UIColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1).cgColor,
                              UIColor(hue: fmod(hue + 0.12, 1), saturation: 0.6, brightness: 0.55, alpha: 1).cgColor]
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                UIColor.white.withAlphaComponent(0.9).setFill()
                let wobble = CGFloat((i * 37) % 60) - 30
                ctx.cgContext.fillEllipse(in: CGRect(x: 150 + wobble, y: 300 - wobble, width: 240, height: 300))
            }
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let date = Calendar.current.date(byAdding: .day, value: -(count - i), to: Date()) ?? Date()
            _ = store.add(jpeg: data, date: date, source: .still, offset: Double.random(in: -3...3))
        }
    }
    #endif
}
