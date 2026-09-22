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
                                // 保存時に黙って切ると入力した名前と違うものが登録されるので、
                                // 入力の時点で上限を超えさせない
                                .onChange(of: newTagName) { _, value in
                                    if value.count > SymptomLimits.tagNameMaxLength {
                                        newTagName = String(value.prefix(SymptomLimits.tagNameMaxLength))
                                    }
                                }
                            Button("action.add") { addUserDefinedTag() }
                                .disabled(trimmedNewTagName.isEmpty)
                        }
                        // 入力中に似た項目を出す。
                        // 同じものを別名で作ってしまう前に気づけるようにする
                        if !suggestions.isEmpty {
                            tagCloud(suggestions)
                        }
                    } header: {
                        Text("symptom.picker.addOwn")
                    } footer: {
                        if !suggestions.isEmpty {
                            Text("symptom.picker.suggestions")
                        }
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
                    ForEach(symptomGroups, id: \.category.id) { group in
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
                    // 薬と薬以外はカプセルの色で見分けられるので、
                    // 見出しで分けず1つにまとめて並べる（スクロールが短くなる）
                    Section {
                        tagCloud(allMedicines.map { ($0.id, $0.localizedName) })
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(kind == .symptom ? "symptom.edit.title" : "symptom.section.remedy")
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
        // .sheet では App の dynamicTypeSize が届かないことがあるため明示する
        .azAppFontScale()
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
                    color: chipColor(for: item.id),
                    isSelected: selectedIDs.contains(item.id),
                    tintsWhenUnselected: kind == .medicine
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

    /// 症状はアクセント色、対処は薬／薬以外で色を分ける
    private func chipColor(for id: String) -> Color {
        guard kind == .medicine else { return .accentColor }
        return MedicineCatalog.isMedicine(id)
            ? DateOptColorOption.color(for: "blue")
            : DateOptColorOption.color(for: "orange")
    }

    /// 入力中の文字に似た候補（辞書＋追加済みタグ）。
    /// すでに選択済みのものは出さない
    private var suggestions: [(id: String, title: String)] {
        let input = trimmedNewTagName
        guard input.count >= 1 else { return [] }

        var seen = Set<String>()
        var result: [(id: String, title: String)] = []

        // 先に自分で追加したタグ（辞書に無い名前を使っている可能性があるため）
        let list = kind == .symptom ? settings.symptomTags : settings.medicineTags
        for tag in list.orderedIncludingHidden where tag.isUserDefined {
            let name = kind == .symptom ? tag.symptomDisplayName : tag.medicineDisplayName
            guard SymptomTagMatching.normalized(name)
                .contains(SymptomTagMatching.normalized(input)) else { continue }
            if seen.insert(tag.id).inserted { result.append((tag.id, name)) }
        }
        // 次に内蔵辞書
        switch kind {
        case .symptom:
            for entry in SymptomCatalog.suggestions(forInput: input) where seen.insert(entry.id).inserted {
                result.append((entry.id, entry.localizedName))
            }
        case .medicine:
            for entry in MedicineCatalog.suggestions(forInput: input) where seen.insert(entry.id).inserted {
                result.append((entry.id, entry.localizedName))
            }
        }
        return Array(result.prefix(6))
    }

    // MARK: - 一覧

    private var trimmedNewTagName: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var symptomGroups: [(category: SymptomCategory, entries: [SymptomCatalogEntry])] {
        SymptomCatalog.groupedByCategory
    }

    private var allMedicines: [MedicineCatalogEntry] {
        MedicineCatalog.all
    }

    private var userDefinedTags: [SymptomTag] {
        let list = kind == .symptom ? settings.symptomTags : settings.medicineTags
        // 非表示にしたものもここには出す。選び直せば markUsed で表示へ戻る
        return list.orderedIncludingHidden.filter(\.isUserDefined)
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
