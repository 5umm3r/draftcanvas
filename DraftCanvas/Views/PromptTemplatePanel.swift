import SwiftUI

struct PromptTemplatePanel: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var selectedTab = 0
    @State private var editingTemplateID: UUID?
    @State private var editName = ""
    @State private var editPrompt = ""
    @State private var isCreating = false
    @State private var newName = ""
    @State private var newPrompt = ""

    private var builtInTemplates: [PromptTemplate] {
        viewModel.templates.filter(\.isBuiltIn)
    }

    private var userTemplates: [PromptTemplate] {
        viewModel.templates.filter { !$0.isBuiltIn }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
            if selectedTab == 1 {
                Divider()
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
    }

    private var header: some View {
        HStack {
            Text("テンプレート")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isTemplatePopoverPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            Text("プリセット").tag(0)
            Text("マイテンプレート").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: selectedTab) { _, _ in
            editingTemplateID = nil
            isCreating = false
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let items = selectedTab == 0 ? builtInTemplates : userTemplates
                if items.isEmpty && selectedTab == 1 {
                    Text("テンプレートがありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(items) { template in
                        if editingTemplateID == template.id {
                            editRow(template: template)
                        } else {
                            templateRow(template: template)
                        }
                        if template.id != items.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }

                if isCreating {
                    Divider().padding(.leading, 16)
                    createRow
                }
            }
        }
    }

    private func templateRow(template: PromptTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(template.promptText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 6) {
                Button(String(localized: "適用")) {
                    viewModel.applyTemplate(template)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !template.isBuiltIn {
                    Menu {
                        Button(String(localized: "編集")) {
                            editName = template.name
                            editPrompt = template.promptText
                            withAnimation(.easeInOut(duration: 0.15)) {
                                editingTemplateID = template.id
                            }
                        }
                        Button(String(localized: "削除"), role: .destructive) {
                            viewModel.deleteTemplate(template)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func editRow(template: PromptTemplate) -> some View {
        VStack(spacing: 8) {
            TextField(String(localized: "テンプレート名"), text: $editName)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            TextEditor(text: $editPrompt)
                .font(.caption)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
            HStack {
                Spacer()
                Button(String(localized: "キャンセル")) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        editingTemplateID = nil
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(String(localized: "保存")) {
                    viewModel.updateTemplate(template, name: editName, promptText: editPrompt)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        editingTemplateID = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty || editPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var createRow: some View {
        VStack(spacing: 8) {
            TextField(String(localized: "テンプレート名"), text: $newName)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            TextEditor(text: $newPrompt)
                .font(.caption)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
            HStack {
                Spacer()
                Button(String(localized: "キャンセル")) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCreating = false
                        newName = ""
                        newPrompt = ""
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(String(localized: "追加")) {
                    viewModel.addTemplate(name: newName, promptText: newPrompt)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCreating = false
                        newName = ""
                        newPrompt = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    editingTemplateID = nil
                    isCreating = true
                    newName = ""
                    newPrompt = ""
                }
            } label: {
                Label(String(localized: "新規作成"), systemImage: "plus")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .disabled(isCreating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
