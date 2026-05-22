require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'DraftCanvas' }
main_group = project.main_group['DraftCanvas']

abort "DraftCanvas target not found" unless target
abort "Already run: MaterialExtraction group already exists" if main_group.find_subpath('MaterialExtraction')

# MaterialExtraction グループ作成
me_group = main_group.find_subpath('MaterialExtraction', true)
me_group.set_source_tree('<group>')

top_files = %w[MaterialExtractor.swift MaterialExtractionError.swift MaterialExtractor+Types.swift]
top_refs = top_files.map do |f|
  ref = me_group.new_file("MaterialExtraction/#{f}")
  ref.set_source_tree('<group>')
  ref
end

pipeline_group = me_group.find_subpath('Pipeline', true)
pipeline_group.set_source_tree('<group>')
pipeline_files = %w[ExtractionPipeline.swift UnionFind.swift]
pipeline_refs = pipeline_files.map do |f|
  ref = pipeline_group.new_file("MaterialExtraction/Pipeline/#{f}")
  ref.set_source_tree('<group>')
  ref
end

stages_group = pipeline_group.find_subpath('Stages', true)
stages_group.set_source_tree('<group>')
stage_files = %w[
  ExtractionStage.swift
  VisionInstancesStage.swift
  CCAInstancesStage.swift
  BoundingBoxStage.swift
  GroupSmallNearbyStage.swift
  MergeByIoUStage.swift
]
stage_refs = stage_files.map do |f|
  ref = stages_group.new_file("MaterialExtraction/Pipeline/Stages/#{f}")
  ref.set_source_tree('<group>')
  ref
end

all_refs = top_refs + pipeline_refs + stage_refs
target.add_file_references(all_refs)

# 旧 MaterialExtractor.swift を削除 (既に rm 済みだがpbxprojから除去)
old_ref = main_group.files.find { |f| f.path == 'MaterialExtractor.swift' }
if old_ref
  bf = target.source_build_phase.files.find { |f| f.file_ref == old_ref }
  bf&.remove_from_project
  old_ref.remove_from_project
  puts "Removed MaterialExtractor.swift"
end

project.save
puts "Done. Phase 4 pbxproj updated. Added #{all_refs.size} files."
