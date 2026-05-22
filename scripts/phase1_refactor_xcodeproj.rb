require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'DraftCanvas' }
main_group = project.main_group['DraftCanvas']

# 冪等性ガード: 2回実行すると重複 PBXFileReference が作成されてプロジェクトが壊れるため、
# Models グループが既に存在する場合は中断する。
abort "Already run: Models group already exists in project" if main_group.find_subpath('Models')

# Models グループ作成
# NOTE: このスクリプト実行時点では DraftCanvas/Models/ と DraftCanvas/Stores/ の
# Swift ファイルはまだ存在しない。Xcode は赤い参照を表示するが、
# 後続の Task 2/3 でファイルが作成されれば参照エラーは解消する。
models_group = main_group.find_subpath('Models', true)
models_group.set_source_tree('<group>')

# CodexTypes.swift: CodexImageResult, CodexTurnResult (Models.swift L941-952 より抽出)
model_files = %w[
  AppAppearance.swift
  CodexModel.swift
  GenerationAspectRatio.swift
  GenerationRequest.swift
  GenerationJob.swift
  AttachedImage.swift
  ProjectInputs.swift
  CanvasSortOrder.swift
  Project.swift
  FilteringProject.swift
  ProjectItem.swift
  SidebarSelection.swift
  ProjectNaming.swift
  PreferredSaveFolderStore.swift
  CodexTypes.swift
  AccountKind.swift
  DraftCanvasError.swift
  RateLimitConfirmation.swift
  CompletionSoundOption.swift
]

model_refs = model_files.map do |f|
  ref = models_group.new_file("Models/#{f}")
  ref.set_source_tree('<group>')
  ref
end
target.add_file_references(model_refs)

# Stores グループ作成
stores_group = main_group.find_subpath('Stores', true)
stores_group.set_source_tree('<group>')

store_files = %w[ProjectStore.swift ProjectStore+Snapshot.swift]
store_refs = store_files.map do |f|
  ref = stores_group.new_file("Stores/#{f}")
  ref.set_source_tree('<group>')
  ref
end
target.add_file_references(store_refs)

# Models.swift を削除
old_ref = main_group.files.find { |f| f.path == 'Models.swift' }
if old_ref
  bf = target.source_build_phase.files.find { |f| f.file_ref == old_ref }
  bf&.remove_from_project
  old_ref.remove_from_project
  puts "Removed Models.swift"
end

project.save
puts "Done. Added #{model_refs.size + store_refs.size} source files to pbxproj."
