// SymptomPickerSheet.swift
// 内蔵辞書から症状・薬を選ぶシート。選んだ時点でタグリストへ追加される

import SwiftUI

struct SymptomPickerSheet: View {
    let kind: SymptomTagKind
    /// 選択済みの ID（症状は1件、薬は複数）
    let selectedIDs: Set<String>
    /// 選択された ID を返す。タグリストへの追加は呼び出し側で行う
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var newTagName = ""
    @State private var showAddField = false
    @FocusState private var newTagFocused: Bool

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        NavigationStack {
            List {
                if showAddField {
                    Section {
                        HStack {
                            TextField("symptom.picker.newName", text: $newTagName)
                                .focused($newTagFocused)
                                .submitLabel(.done)
                                .onSubmit { addUserDefinedTag() }
                            Button("action.add") { addUserDefinedTag() }
                                .disabled(trimmedNewTagName.isEmpty)
                        }
                    } header: {
                        Text("symptom.picker.addOwn")
                    }
                }

                // ユーザーが追加したタグは辞書に無いので独立したセクションで出す
                if !userDefinedTags.isEmpty {
                    Section {
                        ForEach(userDefinedTags) { tag in
                            row(
                                id: tag.id,
                                title: kind == .symptom ? tag.symptomDisplayName : tag.medicineDisplayName
                            )
                        }
                    } header: {
                        Text("symptom.picker.userDefined")
                    }
                }

                switch kind {
                case .symptom:
                    ForEach(filteredSymptomGroups, id: \.category.id) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                row(id: entry.id, title: entry.localizedName)
                            }
                        } header: {
                            Label(
                                NSLocalizedString(group.category.labelKey, comment: ""),
                                systemImage: group.category.icon
                            )
                        }
                    }
                case .medicine:
                    Section {
                        ForEach(filteredMedicines) { entry in
                            row(id: entry.id, title: entry.localizedName)
                        }
                    } header: {
                        Text("medicine.picker.presets")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: Text("symptom.picker.search"))
            .navigationTitle(kind == .symptom ? "symptom.picker.title" : "medicine.picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddField = true
                        newTagFocused = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("symptom.picker.addOwn"))
                }
            }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(id: String, title: String) -> some View {
        Button {
            onSelect(id)
            // 症状は1件しか選べないので、選んだら閉じる。薬は続けて選べるよう開いたままにする
            if kind == .symptom { dismiss() }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if selectedIDs.contains(id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - 絞り込み

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewTagName: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ text: String) -> Bool {
        guard !trimmedSearch.isEmpty else { return true }
        return text.localizedCaseInsensitiveContains(trimmedSearch)
    }

    private var filteredSymptomGroups: [(category: SymptomCategory, entries: [SymptomCatalogEntry])] {
        SymptomCatalog.groupedByCategory.compactMap { group in
            let entries = group.entries.filter { matches($0.localizedName) }
            return entries.isEmpty ? nil : (category: group.category, entries: entries)
        }
    }

    private var filteredMedicines: [MedicineCatalogEntry] {
        MedicineCatalog.all.filter { matches($0.localizedName) }
    }

    private var userDefinedTags: [SymptomTag] {
        let list = kind == .symptom ? settings.symptomTags : settings.medicineTags
        return list.ordered
            .filter(\.isUserDefined)
            .filter { matches(kind == .symptom ? $0.symptomDisplayName : $0.medicineDisplayName) }
    }

    // MARK: - ユーザー追加

    private func addUserDefinedTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }
        let id = SymptomTag.newUserDefinedID()
        switch kind {
        case .symptom:
            var list = settings.symptomTags
            list.add(id: id, customName: name)
            settings.symptomTags = list
        case .medicine:
            var list = settings.medicineTags
            list.add(id: id, customName: name)
            settings.medicineTags = list
        }
        newTagName = ""
        showAddField = false
        newTagFocused = false
        onSelect(id)
        if kind == .symptom { dismiss() }
    }
}
