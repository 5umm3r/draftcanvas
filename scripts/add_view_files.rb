require 'xcodeproj'

project_path = File.join(__dir__, '..', 'DraftCanvas.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'DraftCanvas' }
main_group = project.main_group['DraftCanvas']

view_group = main_group.find_subpath('Views', true)
view_group.set_source_tree('<group>')

view_files = %w[
  ProjectRow.swift
  GenerationDetailPopover.swift
  ItemDetailPopover.swift
  ErrorToastView.swift
  DetailRow.swift
  AccountPopover.swift
  LogWindow.swift
  GenerationProgressView.swift
  VectorizingOverlay.swift
  PromptTextView.swift
  StatusBadge.swift
  CanvasZoomControl.swift
  AttachedImageThumbnail.swift
  PopoverButton.swift
  GenerationCountPopover.swift
  ContentView+TopBar.swift
  ContentView+Sidebar.swift
  ContentView+Canvas.swift
  ContentView+PromptPanel.swift
]

refs = view_files.map do |f|
  ref = view_group.new_file("Views/#{f}")
  ref.set_source_tree('<group>')
  ref
end

target.add_file_references(refs)

project.save
puts "Done. Added #{refs.size} view files."
