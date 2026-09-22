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
    /// 編集中のタグ（長押しで開く）
    @State private var editingTag: EditingTag? = nil

    struct EditingTag: Identifiable {
        let id: String
        var name: String
    }
    @FocusState private var newTagFocused: Bool

    private var settings: AppSettings { AppSettings.shared }

    /// シートの背景。記録画面の上に症状/対処シート、その上にタグ編集シートと
    /// 3枚重なるので、下の画面と同じ灰色だとどれを操作しているのか分からなくなる。
    /// 色相でシートの種類が分かるように、標準の灰色へ淡く色を混ぜる
    private var sheetBackground: Color {
        let tint: UIColor = kind == .symptom ? .tintColor : .systemOrange
        // ライト/ダークそれぞれで解決してから混ぜる。
        // 固定色を薄く敷くとダークモードで白っぽく浮いてしまうため
        return Color(UIColor { traits in
            let base = UIColor.systemGroupedBackground.resolvedColor(with: traits)
            let top = tint.resolvedColor(with: traits)
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
            base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
            let amount: CGFloat = 0.07
            return UIColor(
                red: br + (tr - br) * amount,
                green: bg + (tg - bg) * amount,
                blue: bb + (tb - bb) * amount,
                alpha: ba
            )
        })
    }

    var body: some View {
        NavigationStack {
            // タップと長押しの使い分けは見ただけでは分からないので先頭で伝える。
            // List の中に置くと insetGrouped が独立したセクション扱いにして
            // 上下に大きな余白を入れてしまうため、List の外に出して余白を自分で決める
            VStack(spacing: 0) {
                BeginnerHelpBanner(
                    hintKey: "picker.help.usage.hint",
                    messageKey: "picker.help.usage",
                    storageKey: "helpDismissed.picker.usage",
                    compact: true,
                    tight: true,
                    iconLeading: true
                )
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

                List {
                    // 入力欄は常に出しておく。ツールバーの (+) を押してから入力欄が現れる
                    // 二段構えだと、辞書に無い症状を足せること自体が見つけにくかった
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
                        // 自分で足したものは、足した場所と同じセクションに置く。
                        // 症状は11分類で並ぶため、どの分類にも属さない追加分はここが定位置になる。
                        // 対処は分類を持たないので、下でプリセットと同じ列に混ぜる
                        if kind == .symptom, !userDefinedTags.isEmpty {
                            tagCloud(userDefinedTags.map { ($0.id, $0.symptomDisplayName) })
                        }
                    } header: {
                        Text(kind == .symptom ? "symptom.picker.newSymptom" : "symptom.picker.newRemedy")
                    } footer: {
                        // 使い方は先頭のヘルプで伝えているので、ここは候補の説明だけにする
                        if !suggestions.isEmpty {
                            Text("symptom.picker.suggestions")
                        }
                    }

                    switch kind {
                    case .symptom:
                        ForEach(symptomGroups, id: \.category.id) { group in
                            Section {
                                tagCloud(group.entries.map { ($0.id, symptomName(for: $0)) })
                            } header: {
                                Label(
                                    NSLocalizedString(group.category.labelKey, comment: ""),
                                    systemImage: group.category.icon
                                )
                            }
                        }
                    case .medicine:
                        // ユーザー追加分もプリセットと同じ列に混ぜ、直近に使った順で並べる
                        Section {
                            tagCloud(remedyItems)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // 背景はシート全体で1枚にしたいので List 自身の背景は消す
                .scrollContentBackground(.hidden)
            }
            .sheet(item: $editingTag) { target in
                TagEditSheet(kind: kind, tagID: target.id)
            }
            .navigationTitle(kind == .symptom ? "symptom.edit.title" : "symptom.section.remedy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 下向き矢印はシートを下へ閉じる操作と向きが一致する。
                    // 文字を省けるぶん、タイトルとタグに幅を回せる
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel(Text("action.close"))
                }
            }
        }
        // ナビゲーションバーの下まで色を回すため、背景はシート側に指定する
        .presentationBackground(sheetBackground)
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
                    color: .accentColor,
                    isSelected: selectedIDs.contains(item.id),
                    // プリセットも含めて長押しで名前を直せる。
                    // 削除は用意しない（過去の記録が名前を参照しているため）
                    onLongPress: { editingTag = EditingTag(id: item.id, name: item.title) }
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
                result.append((entry.id, symptomName(for: entry)))
            }
        case .medicine:
            for entry in MedicineCatalog.suggestions(forInput: input) where seen.insert(entry.id).inserted {
                let name = settings.medicineTags.tag(for: entry.id)?.medicineDisplayName
                    ?? entry.localizedName
                result.append((entry.id, name))
            }
        }
        return Array(result.prefix(6))
    }

    /// 症状の表示名。上書きがあればそれを使う（プリセットも名前を直せるため）
    private func symptomName(for entry: SymptomCatalogEntry) -> String {
        settings.symptomTags.tag(for: entry.id)?.symptomDisplayName ?? entry.localizedName
    }

    // MARK: - 一覧

    private var trimmedNewTagName: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var symptomGroups: [(category: SymptomCategory, entries: [SymptomCatalogEntry])] {
        SymptomCatalog.groupedByCategory
    }

    /// 対処の一覧。辞書とユーザー追加をまとめ、直近に使った順に並べる。
    /// 使っていないものは辞書の登録順（よく使うものが前に来るよう並べてある）
    private var remedyItems: [(id: String, title: String)] {
        let list = settings.medicineTags
        // 辞書の登録順を覚えておき、未使用タグの並びに使う
        let catalogOrder = Dictionary(
            uniqueKeysWithValues: MedicineCatalog.all.enumerated().map { ($1.id, $0) }
        )
        var ids = MedicineCatalog.all.map(\.id)
        // 辞書に無いユーザー追加分を足す
        ids += list.orderedIncludingHidden
            .filter { $0.isUserDefined }
            .map(\.id)

        return ids
            .sorted { lhs, rhs in
                let l = list.tag(for: lhs)?.lastUsedAt
                let r = list.tag(for: rhs)?.lastUsedAt
                switch (l, r) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    // 未使用どうしは辞書の登録順。ユーザー追加は辞書に無いので末尾へ
                    return (catalogOrder[lhs] ?? Int.max) < (catalogOrder[rhs] ?? Int.max)
                }
            }
            .map { id in
                // 上書き名があればそれを優先する（プリセットも名前を直せるため）。
                // タグリストに無い項目は辞書の名前を使う
                let name = list.tag(for: id)?.medicineDisplayName
                    ?? MedicineCatalog.entry(for: id)?.localizedName
                    ?? id
                return (id, name)
            }
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
