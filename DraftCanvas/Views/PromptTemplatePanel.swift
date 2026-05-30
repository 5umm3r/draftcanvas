import SwiftUI

struct PromptTemplatePanel: View {
    @ObservedObject var viewModel: DraftCanvasViewModel
    @State private var selectedCategory: PromptTemplateCategory = .style
    @State private var editingTemplateID: UUID?
    @State private var editName = ""
    @State private var editPrompt = ""
    @State private var isCreating = false
    @State private var newName = ""
    @State private var newPrompt = ""

    private var templatesForSelectedCategory: [PromptTemplate] {
        viewModel.templates.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                categoryList
                Divider()
                templateList
            }
            if selectedCategory == .user {
                Divider()
                footer
            }
        }
        .frame(maxWidth: 780)
        .frame(maxHeight: 380)
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

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(PromptTemplateCategory.allCases) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = category
                            editingTemplateID = nil
                            isCreating = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: category.systemImage)
                                .font(.system(size: 12))
                                .frame(width: 16)
                            Text(category.localizedName)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(selectedCategory == category
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(selectedCategory == category
                            ? Color.accentColor
                            : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 200)
        .background(Color.primary.opacity(0.02))
    }

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let items = templatesForSelectedCategory
                if items.isEmpty {
                    Text(selectedCategory == .user
                        ? String(localized: "テンプレートがありません")
                        : String(localized: "テンプレートなし"))
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

                if selectedCategory == .user && isCreating {
                    Divider().padding(.leading, 16)
                    createRow
                }
            }
        }
    }

    private func templateRow(template: PromptTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(template.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
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
