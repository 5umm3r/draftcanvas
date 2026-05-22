# scripts/add_phase4_test_files.rb
require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)
test_target = project.targets.find { |t| t.name == 'DraftCanvasTests' }
test_group = project.main_group['DraftCanvasTests']

abort "DraftCanvasTests not found" unless test_target && test_group

# テストSwiftファイル追加
unless test_group.files.any? { |f| f.path.include?('MaterialExtractorPipelineTests') }
  test_ref = test_group.new_file('MaterialExtractorPipelineTests.swift')
  test_ref.set_source_tree('<group>')
  test_target.add_file_references([test_ref])
  puts "Added MaterialExtractorPipelineTests.swift"
end

# PNG リソース追加
resources_phase = test_target.resources_build_phase
unless resources_phase.files.any? { |f| f.file_ref&.path&.include?('test_color_patches') }
  res_group = test_group.find_subpath('Resources', true)
  res_group.set_source_tree('<group>')
  png_ref = res_group.new_file('DraftCanvasTests/Resources/test_color_patches.png')
  png_ref.set_source_tree('<group>')
  resources_phase.add_file_reference(png_ref)
  puts "Added test_color_patches.png"
end

project.save
puts "Done."
