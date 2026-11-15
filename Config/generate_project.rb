#!/usr/bin/env ruby
# LifeSliceMirror.xcodeproj を作り直すスクリプト（CocoaPods の xcodeproj gem を使用）。
# ふだんは同梱の .xcodeproj をそのまま開けばよく、ファイルを足したときは Xcode 上で追加すれば十分です。
#   gem install xcodeproj && ruby Config/generate_project.rb
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
DEPLOY = '26.0'
BUNDLE = 'app.lifeslice.mirror'

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
    refs["#{dir}/#{name}"] = group.new_file(name)
  end
end

swift = ->(dir) { refs.select { |k, _| k.start_with?("#{dir}/") && k.end_with?('.swift') }.values }

app.add_file_references(swift['App'] + swift['Shared'] + swift['Camera'] + swift['Store'] + swift['Reel'] + swift['Views'])
app.add_resources([refs['App/Assets.xcassets']])

widgets.add_file_references(swift['Widgets'] + swift['Shared'])

capture.add_file_references(swift['CaptureExtension'] +
                            [refs['Camera/CameraEngine.swift'], refs['Camera/SurpriseBuffer.swift'],
                             refs['Shared/MirrorCaptureIntent.swift']])

# --- ビルド設定 ---
common = {
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOY,
  'SWIFT_VERSION' => '5.0',
  'TARGETED_DEVICE_FAMILY' => '1',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_TEAM' => '',
  'MARKETING_VERSION' => '1.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
}

camera_reason = '鏡として映すため、そして不意打ちの 1 コマを残すためにカメラを使います。'
photos_reason = 'スライスや書き出したリールを「LifeSlice Mirror」アルバムに保存するために使います。'

per_target = {
  app => {
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'CODE_SIGN_ENTITLEMENTS' => 'Config/App.entitlements',
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
    'INFOPLIST_KEY_CFBundleDisplayName' => 'LifeSlice',
    'SKIP_INSTALL' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  },
}

per_target.each do |target, settings|
  target.build_configurations.each do |config|
    config.build_settings.merge!(common).merge!(settings)
    config.build_settings.delete('INFOPLIST_FILE') if target == app
  end
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
project.root_object.development_region = 'ja'
project.root_object.known_regions = %w[ja en Base]

project.save
puts "wrote #{path}"
