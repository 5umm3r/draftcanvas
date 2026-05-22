require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'DraftCanvas' }
main_group = project.main_group['DraftCanvas']
view_group = main_group['Views']

abort "Already run: Canvas group already exists" if view_group&.find_subpath('Canvas')

# Canvas サブグループ作成
canvas_group = view_group.find_subpath('Canvas', true)
canvas_group.set_source_tree('<group>')

canvas_files = %w[
  CanvasEntry.swift
  CanvasCardLayout.swift
  ContentView+CanvasArea.swift
  ContentView+CanvasCards.swift
  ContentView+CanvasMarquee.swift
  ItemThumbnailView.swift
  JobPreviewView.swift
  MultiDragPreview.swift
  CheckerboardView.swift
  AutoScrollerAnchor.swift
  CardFramePreferenceKey.swift
]

refs = canvas_files.map do |f|
  ref = canvas_group.new_file("Views/Canvas/#{f}")
  ref.set_source_tree('<group>')
  ref
end
target.add_file_references(refs)

# 旧ファイル削除
old_ref = view_group&.files&.find { |f| f.path.end_with?('ContentView+Canvas.swift') }
if old_ref
  bf = target.source_build_phase.files.find { |f| f.file_ref == old_ref }
  bf&.remove_from_project
  old_ref.remove_from_project
  puts "Removed ContentView+Canvas.swift"
end

project.save
puts "Done. Phase 3 pbxproj updated. Added #{refs.size} files."
