# LifeSlice Mirror

鏡として使っているだけで、不意打ちの 1 コマが勝手にたまっていく iPhone アプリ。
たまったらぱらぱら動く GIF / MP4（リール）にして見返す・シェアする。

- 対応: iOS 26 以降 / iPhone / Xcode 26
- 外部ライブラリなし（SwiftUI + AVFoundation + Vision + CoreMotion + WidgetKit）

## 最初にやること

1. `Config/Local.xcconfig` を作って、自分の Team ID と Bundle ID を書く（このファイルは git に入りません）

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   LS_BUNDLE_ID = com.example.lifeslice
   ```

   拡張の Bundle ID（`.widgets` / `.capture`）と App Group（`group.<LS_BUNDLE_ID>`）は自動でそろいます。
2. `LifeSliceMirror.xcodeproj` を Xcode 26 で開く（設定の更新を勧められたら従って OK）
3. 実機を選んで Run（シミュレータにはインカメラが無いので鏡は映りません。
   設定画面の「ダミーのスライスを 24 枚つくる」でリール作りだけは試せます）

Xcode の画面で Team を選んでも動きますが、その場合 `project.pbxproj` に差分が出ます。
App Group が使えなくてもアプリ本体は動きます（ウィジェットに最新スライスが出ないだけ）。

## 言語

- 日本語と英語。iPhone が日本語なら日本語、それ以外は英語で始まる
- iPhone の「設定 > アプリ > LifeSlice > 言語」でも、アプリ内の設定でも切り替えられる
- 画面の文言はコード中に日本語で書き、英語は `Shared/L10n.swift` の対応表から引く。
  文言を足したら対応表にも 1 行足す（無ければ日本語のまま出る）
- システムが直接読む文言（権限の説明、コントロール名）は `Config/Localization/`

## アイコン

- いまのアプリアイコンは `Config/IconOptions/icon-A.svg`（モノトーンの線画）。ほかの案も同じフォルダにある
- ロック画面の「線画アイコン」ウィジェットは `Shared/FaceMark.swift` が同じ絵を線で描いている

## ビルドについての注意

このコードは Xcode でのビルド確認ができない環境で書いています（構文チェックと、減色ロジックの動作確認まで）。
初回ビルドでエラーが出たら、エラー文をそのまま貼ってもらえれば直します。
あやしい順に:

1. `CaptureExtension/`（ロック中の撮影。LockedCameraCapture まわり）
   → ここだけ通らない場合は LifeSliceCapture ターゲットを消し、
   `SliceDirector.swift` の `watchLockedCaptures` 関連を消せば残りは独立して動きます
2. `App/Theme.swift` のガラス表現（`glassEffect`）と `MirrorView` の `GlassEffectContainer`
3. `Camera/CameraEngine.swift` のカメラコントロール（`AVCaptureSystemZoomSlider`）

## 仕組み

| やりたいこと | 実装 |
| --- | --- |
| シャッター前後 ±1.5 秒からランダムに 1 コマ | `SurpriseBuffer` が直近 6 秒を 8fps・JPEG でメモリ保持。押してから「後」の秒数だけ待ち、範囲内のランダムな時刻にいちばん近いコマを保存（`SliceDirector.resolve`）。振り幅は設定で前後それぞれ 0〜3 秒 |
| 止まった瞬間に自動で撮る | `StillnessDetector`（ジャイロ＋加速度）が静止を検知、かつ Vision で顔が映っているときだけ、シャッターと同じ抽選を行う。連発防止の間隔つき |
| 止まらない人にも 1 枚 | アプリが前面でなくなる瞬間（`SliceDirector.resignActive`）に、そのとき持っているバッファから 1 コマ。iOS はバックグラウンドでカメラを動かせないので、これが実質のバックグラウンド処理 |
| 容量を増やさない | 映像ファイルは作らない。バッファはメモリのみで、鏡を離れるたびに破棄。残るのは選ばれた JPEG だけ |
| 写真アプリにも保存 | 設定でオンにすると「LifeSlice Mirror」アルバムへ（`PhotoAlbum`） |
| リール | `ReelRenderer` が 切り抜き → フィルタ → 日付スタンプ → 減色 を 1 コマずつ。プレビューと書き出しは同じ処理 |
| 256 色などの減色 | `Quantizer`。全コマ共通パレット（median cut）＋ ディザ 3 種。GIF も MP4 も同じ見た目になる |
| ウィジェット | ホーム: 最新スライス（小・中）／ロック画面: 線画アイコン、枚数（円・四角・1 行）／コントロール: 鏡をひらく |
| カメラコントロール | アプリ内ではシャッター（`onCameraCaptureEvent`）と軽押しズーム。ロック中の起動は LifeSliceCapture 拡張 |

## 入っていないもの

- 動画モード（能動的に動画を撮る機能）。今回は静止画スライスのみ
- プレビュー映像そのものへの色調整・背景ぼかし（明るさは露出補正、ライトは画面の明るさを最大にするだけ）
- iPad / 横向き

## フォルダ

```
App/               アプリの入口、共通の見た目、アイコン
Views/             鏡・スライス一覧・リール・設定
Camera/            カメラ、不意打ちバッファ、静止検知
Store/             スライスの保存、写真アルバム、撮る判断（SliceDirector）
Reel/              リールの選択肢、描画、減色、GIF/MP4 書き出し
Shared/            アプリと拡張で共有（App Group、起動インテント）
Widgets/           ウィジェット拡張
CaptureExtension/  ロック中キャプチャ拡張
Config/            Info.plist、entitlements、署名設定、言語別ファイル、アイコン案（SVG）、プロジェクト生成スクリプト
```
