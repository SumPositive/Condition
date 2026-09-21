// SymptomPickerSheet.swift
// 内蔵辞書から症状・薬を選ぶシート。選んだ時点でタグリストへ追加される

import SwiftUI

struct SymptomPickerSheet: View {
    let kind: SymptomTagKind
    /// 選択済みの ID。タグの見た目に反映する（症状は1件、薬は記録側で複数持てる）
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
                        tagCloud(userDefinedTags.map {
                            ($0.id, kind == .symptom ? $0.symptomDisplayName : $0.medicineDisplayName)
                        })
                    } header: {
                        Text("symptom.picker.userDefined")
                    }
                }

                switch kind {
                case .symptom:
                    ForEach(filteredSymptomGroups, id: \.category.id) { group in
                        Section {
                            tagCloud(group.entries.map { ($0.id, $0.localizedName) })
                        } header: {
                            Label(
                                NSLocalizedString(group.category.labelKey, comment: ""),
                                systemImage: group.category.icon
                            )
                        }
                    }
                case .medicine:
                    Section {
                        tagCloud(filteredMedicines.map { ($0.id, $0.localizedName) })
                    } header: {
                        Text("medicine.picker.presets")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: Text("symptom.picker.search"))
            .navigationTitle(kind == .symptom ? "symptom.edit.title" : "medicine.picker.navTitle")
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

    /// セクションの中身をタグの折り返し並びで出す。
    /// 1行1項目のリストだと縦に伸びて一覧性が落ちるため、記録画面のタグ行と見た目を揃える
    @ViewBuilder
    private func tagCloud(_ items: [(id: String, title: String)]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.id) { item in
                SymptomTagChip(
                    title: item.title,
                    color: kind == .symptom ? .accentColor : .blue,
                    isSelected: selectedIDs.contains(item.id)
                ) {
                    onSelect(item.id)
                    // 症状・薬ともタップしたら閉じて反映する。
                    // 薬の複数選択は記録画面のタグ行で行う
                    dismiss()
                }
            }
        }
        .padding(.vertical, 4)
        // タグ自体がボタンなので、行全体のタップ領域は無効にする
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

        // 「花粉症」のようにプリセットや追加済みのタグと同じ名前が打たれたら、
        // 新しい ID は作らず既存のものを選ぶ。別IDで重複すると集計まで割れてしまう
        let matched = existingID(forName: name)
        let id = matched ?? SymptomTag.newUserDefinedID()
        // 辞書に当たったときは名前を上書きしない（ローカライズ名のまま使う）
        let customName = matched == nil ? name : ""

        switch kind {
        case .symptom:
            var list = settings.symptomTags
            list.add(id: id, customName: customName)
            settings.symptomTags = list
        case .medicine:
            var list = settings.medicineTags
            list.add(id: id, customName: customName)
            settings.medicineTags = list
        }
        newTagName = ""
        showAddField = false
        newTagFocused = false
        onSelect(id)
        dismiss()
    }

    /// 入力された名前に対応する既存の ID。辞書とタグリストの両方を見る
    private func existingID(forName name: String) -> String? {
        let list = kind == .symptom ? settings.symptomTags : settings.medicineTags
        // 先に自分で追加済みのタグを見る（辞書名を上書きしている場合もあるため）
        let target = SymptomTagMatching.normalized(name)
        if let tag = list.tags.first(where: {
            let display = kind == .symptom ? $0.symptomDisplayName : $0.medicineDisplayName
            return SymptomTagMatching.normalized(display) == target
        }) {
            return tag.id
        }
        return kind == .symptom
            ? SymptomCatalog.matchingID(forName: name)
            : MedicineCatalog.matchingID(forName: name)
    }
}
