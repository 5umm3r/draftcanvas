require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'DraftCanvas' }
main_group = project.main_group['DraftCanvas']

# ViewModel group
vm_group = main_group.find_subpath('ViewModel', true)
vm_group.set_source_tree('<group>')

vm_files = %w[
  DraftCanvasViewModel+Computed.swift
  DraftCanvasViewModel+Projects.swift
  DraftCanvasViewModel+Generation.swift
  DraftCanvasViewModel+Account.swift
  DraftCanvasViewModel+ItemActions.swift
  DraftCanvasViewModel+PromptEnhance.swift
  DraftCanvasViewModel+Items.swift
  DraftCanvasViewModel+Export.swift
  DraftCanvasViewModel+Vectorize.swift
  DraftCanvasViewModel+Attachments.swift
  DraftCanvasViewModel+CanvasImport.swift
]

refs = vm_files.map do |f|
  ref = vm_group.new_file("ViewModel/#{f}")
  ref.set_source_tree('<group>')
  ref
end

# ExportNaming.swift (in DraftCanvas group root)
export_naming_ref = main_group.new_file('ExportNaming.swift')
export_naming_ref.set_source_tree('<group>')

target.add_file_references(refs + [export_naming_ref])

project.save
puts "Done. Added #{refs.size + 1} files."
