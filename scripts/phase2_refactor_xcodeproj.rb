require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'DraftCanvas' }
main_group = project.main_group['DraftCanvas']

# 既存の Editors グループがあれば abort (冪等性)
abort "Already run: Editors group already exists" if main_group.find_subpath('Editors')

# Editors グループ作成
editors_group = main_group.find_subpath('Editors', true)
editors_group.set_source_tree('<group>')

# NOTE: Sketch/ と InpaintingMask/ の Swift ファイルは Task 6 で作成する。
# このスクリプト実行後は Xcode で赤い参照になるが Task 6 完了後に解消する。
{
  'Crop'           => %w[CropEditorSheet.swift CropCanvasView.swift CropCanvasNSView.swift],
  'Sketch'         => %w[SketchEditorSheet.swift SketchCanvasView.swift SketchCanvasNSView.swift],
  'InpaintingMask' => %w[InpaintMode.swift InpaintingMaskEditorSheet.swift MaskCanvasView.swift MaskCanvasNSView.swift],
}.each do |dir, files|
  group = editors_group.find_subpath(dir, true)
  group.set_source_tree('<group>')
  refs = files.map do |f|
    ref = group.new_file("Editors/#{dir}/#{f}")
    ref.set_source_tree('<group>')
    ref
  end
  target.add_file_references(refs)
end

# 旧ファイル削除
%w[CropEditor.swift SketchEditor.swift InpaintingMaskEditor.swift].each do |old|
  ref = main_group.files.find { |f| f.path == old }
  next unless ref
  bf = target.source_build_phase.files.find { |f| f.file_ref == ref }
  bf&.remove_from_project
  ref.remove_from_project
  puts "Removed #{old}"
end

# テストファイル追加
test_target = project.targets.find { |t| t.name == 'DraftCanvasTests' }
test_group = project.main_group['DraftCanvasTests']
abort "DraftCanvasTests target not found" unless test_target
abort "DraftCanvasTests group not found" unless test_group
abort "Already added: CropEditorMathTests already in project" if test_group.files.any? { |f| f.path.include?('CropEditorMathTests') }
test_ref = test_group.new_file('CropEditorMathTests.swift')
test_ref.set_source_tree('<group>')
test_target.add_file_references([test_ref])

project.save
puts "Done. Phase 2 pbxproj updated."
