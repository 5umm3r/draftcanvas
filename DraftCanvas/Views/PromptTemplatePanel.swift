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
            templateContent
            if selectedCategory == .user {
                Divider()
                footer
            }
            Divider()
            categoryTabBar
        }
        .frame(maxWidth: 780)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
    }

    // MARK: - Category Tab Bar

    private var categoryTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(PromptTemplateCategory.allCases) { category in
                        categoryTab(for: category)
                    }
                }
                .padding(.horizontal, 16)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isTemplatePopoverPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }

    private func categoryTab(for category: PromptTemplateCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
                editingTemplateID = nil
                isCreating = false
            }
        } label: {
            Text(category.localizedName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Template Content

    @ViewBuilder
    private var templateContent: some View {
        if selectedCategory == .user {
            userTemplateList
        } else {
            thumbnailSlider
        }
    }

    // MARK: - Thumbnail Slider

    private var thumbnailSlider: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                let items = templatesForSelectedCategory
                if items.isEmpty {
                    Text(String(localized: "テンプレートなし"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(items) { template in
                        templateThumbnailCard(template)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func templateThumbnailCard(_ template: PromptTemplate) -> some View {
        Button {
            viewModel.applyTemplate(template)
        } label: {
            VStack(spacing: 4) {
                Text(template.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 180)
                thumbnailImage(for: template)
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnailImage(for template: PromptTemplate) -> some View {
        if let imageName = template.thumbnailImageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    Image(systemName: template.category.systemImage)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                )
        }
    }

    // MARK: - User Template List

    private var userTemplateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let items = templatesForSelectedCategory
                if items.isEmpty && !isCreating {
                    Text(String(localized: "テンプレートがありません"))
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
        .frame(maxHeight: 280)
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

    // MARK: - Footer

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
