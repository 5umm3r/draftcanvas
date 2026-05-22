require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'DraftCanvasTests' }
abort "DraftCanvasTests target not found" unless test_target

test_group = project.main_group['DraftCanvasTests']
abort "DraftCanvasTests group not found" unless test_group

# 冪等性ガード
if test_group.files.any? { |f| f.path == 'ProjectStoreSnapshotTests.swift' }
  abort "Already added: ProjectStoreSnapshotTests.swift already in project"
end

test_ref = test_group.new_file('ProjectStoreSnapshotTests.swift')
test_ref.set_source_tree('<group>')
test_target.add_file_references([test_ref])

project.save
puts "Done. Added ProjectStoreSnapshotTests.swift to DraftCanvasTests."
