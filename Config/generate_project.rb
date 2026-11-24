#!/usr/bin/env ruby
# LifeSliceMirror.xcodeproj を作り直すスクリプト（CocoaPods の xcodeproj gem を使用）。
# ふだんは同梱の .xcodeproj をそのまま開けばよく、ファイルを足したときは Xcode 上で追加すれば十分です。
#   gem install xcodeproj && ruby Config/generate_project.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
DEPLOY = '26.0'
BUNDLE = '$(LS_BUNDLE_ID)' # 実際の値は Config/Signing.xcconfig（＋ Local.xcconfig）

path = File.join(ROOT, 'LifeSliceMirror.xcodeproj')
FileUtils.rm_rf(path)
project = Xcodeproj::Project.new(path)

app = project.new_target(:application, 'LifeSliceMirror', :ios, DEPLOY, nil, :swift)
widgets = project.new_target(:app_extension, 'LifeSliceWidgets', :ios, DEPLOY, nil, :swift)
capture = project.new_target(:app_extension, 'LifeSliceCapture', :ios, DEPLOY, nil, :swift)

# ロック中キャプチャは ExtensionKit 形式の拡張
capture.product_type = 'com.apple.product-type.extensionkit-extension'
capture.product_reference.explicit_file_type = 'wrapper.extensionkit-extension'

# gem が自動で足す SDK 固定パスのフレームワーク参照は不要（自動リンクに任せる）
[app, widgets, capture].each { |t| t.frameworks_build_phase.clear }
project.frameworks_group.clear

# --- ファイル ---
refs = {}
%w[App Shared Camera Store Reel Views Widgets CaptureExtension Config].each do |dir|
  group = project.main_group.new_group(dir, dir)
  Dir.children(File.join(ROOT, dir)).sort.each do |name|
    next if name.start_with?('.')
    next if File.directory?(File.join(ROOT, dir, name)) && !name.end_with?('.xcassets')
    refs["#{dir}/#{name}"] = group.new_file(name)
  end
end

# 言語別のファイル（en / ja）。lproj があることで、iPhone の設定アプリにも言語の切り替えが出る。
loc_group = project.main_group.new_group('Localization', 'Config/Localization')
localized = %w[Localizable.strings InfoPlist.strings].map do |name|
  variant = loc_group.new_variant_group(name)
  %w[en ja].each do |lang|
    ref = variant.new_reference("#{lang}.lproj/#{name}")
    ref.name = lang
  end
  variant
end

swift = ->(dir) { refs.select { |k, _| k.start_with?("#{dir}/") && k.end_with?('.swift') }.values }

app.add_file_references(swift['App'] + swift['Shared'] + swift['Camera'] + swift['Store'] + swift['Reel'] + swift['Views'])
# Symbols.xcassets はコントロール用のカスタムシンボル。アプリ本体とウィジェットの両方に入れる。
app.add_resources([refs['App/Assets.xcassets'], refs['Shared/Symbols.xcassets']])

widgets.add_file_references(swift['Widgets'] + swift['Shared'])
widgets.add_resources([refs['Shared/Symbols.xcassets']])

capture.add_file_references(swift['CaptureExtension'] + swift['Shared'] +
                            [refs['Camera/CameraEngine.swift'], refs['Camera/SurpriseBuffer.swift'],
                             refs['Camera/StillnessDetector.swift']])

[app, widgets, capture].each do |target|
  localized.each { |variant| target.resources_build_phase.add_file_reference(variant) }
end

# --- ビルド設定 ---
common = {
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOY,
  'SWIFT_VERSION' => '5.0',
  'TARGETED_DEVICE_FAMILY' => '1',
  'CODE_SIGN_STYLE' => 'Automatic',
  'MARKETING_VERSION' => '1.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
}

# 既定（英語）。日本語は Config/Localization/ja.lproj/InfoPlist.strings
camera_reason = 'The camera is used to work as a mirror and to keep one surprise frame.'
photos_reason = 'Used to save slices and exported reels to the LifeSlice Mirror album.'

per_target = {
  app => {
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'CODE_SIGN_ENTITLEMENTS' => 'Config/App.entitlements',
    'INFOPLIST_FILE' => 'Config/App-Info.plist',   # 自動生成分に URL スキームを足す
    'ENABLE_PREVIEWS' => 'YES',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'LifeSlice',
    'INFOPLIST_KEY_NSCameraUsageDescription' => camera_reason,
    'INFOPLIST_KEY_NSPhotoLibraryUsageDescription' => photos_reason,
    'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription' => photos_reason,
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
    'INFOPLIST_KEY_UIStatusBarStyle' => 'UIStatusBarStyleLightContent',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
  },
  widgets => {
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE}.widgets",
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'CODE_SIGN_ENTITLEMENTS' => 'Config/Widgets.entitlements',
    'INFOPLIST_FILE' => 'Config/Widgets-Info.plist',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'LifeSlice',
    'SKIP_INSTALL' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  },
  capture => {
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE}.capture",
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => 'Config/Capture-Info.plist',
    'INFOPLIST_KEY_NSCameraUsageDescription' => camera_reason,   # ロック中の鏡もカメラを使うので必須
    'INFOPLIST_KEY_CFBundleDisplayName' => 'LifeSlice',
    'SKIP_INSTALL' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  },
}

per_target.each do |target, settings|
  target.build_configurations.each do |config|
    config.build_settings.merge!(common).merge!(settings)
  end
end

# 署名の値は xcconfig から。プロジェクトを作り直しても各自の Team / Bundle ID が消えない。
project.build_configurations.each do |config|
  config.base_configuration_reference = refs['Config/Signing.xcconfig']
end

# --- 拡張の埋め込み ---
[widgets, capture].each { |ext| app.add_dependency(ext) }

embed_plugins = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed_plugins.symbol_dst_subfolder_spec = :plug_ins
build_file = embed_plugins.add_file_reference(widgets.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

embed_exkit = app.new_copy_files_build_phase('Embed ExtensionKit Extensions')
embed_exkit.dst_subfolder_spec = '16'
embed_exkit.dst_path = '$(EXTENSIONS_FOLDER_PATH)'
build_file = embed_exkit.add_file_reference(capture.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.root_object.attributes['LastSwiftUpdateCheck'] = '2600'
project.root_object.attributes['LastUpgradeCheck'] = '2600'
# 開発言語は英語。日本語以外の端末では英語になる。
project.root_object.development_region = 'en'
project.root_object.known_regions = %w[en ja Base]

project.save
puts "wrote #{path}"
