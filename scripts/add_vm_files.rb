require 'xcodeproj'

project_path = File.join(__dir__, '..', 'ImageCreator.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'ImageCreator' }
main_group = project.main_group['ImageCreator']

# ViewModel group
vm_group = main_group.find_subpath('ViewModel', true)
vm_group.set_source_tree('<group>')

vm_files = %w[
  ImageCreatorViewModel+Computed.swift
  ImageCreatorViewModel+Projects.swift
  ImageCreatorViewModel+Generation.swift
  ImageCreatorViewModel+Account.swift
  ImageCreatorViewModel+ItemActions.swift
  ImageCreatorViewModel+PromptEnhance.swift
  ImageCreatorViewModel+Items.swift
  ImageCreatorViewModel+Export.swift
  ImageCreatorViewModel+Vectorize.swift
  ImageCreatorViewModel+Attachments.swift
  ImageCreatorViewModel+CanvasImport.swift
]

refs = vm_files.map do |f|
  ref = vm_group.new_file("ViewModel/#{f}")
  ref.set_source_tree('<group>')
  ref
end

# ExportNaming.swift (in ImageCreator group root)
export_naming_ref = main_group.new_file('ExportNaming.swift')
export_naming_ref.set_source_tree('<group>')

target.add_file_references(refs + [export_naming_ref])

project.save
puts "Done. Added #{refs.size + 1} files."
