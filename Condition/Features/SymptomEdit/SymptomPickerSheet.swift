// SymptomPickerSheet.swift
// 内蔵辞書から症状・薬を選ぶシート。選んだ時点でタグリストへ追加される

import SwiftUI

struct SymptomPickerSheet: View {
    let kind: SymptomTagKind
    /// 選択済みの ID。タグの見た目に反映する（症状は1件、薬は記録側で複数持てる）
    let selectedIDs: Set<String>
    /// タップされた ID を返す。タグリストへの追加は呼び出し側で行う。
    /// 対処は選択/解除のトグルとして呼ばれる
    let onSelect: (String) -> Void

    /// 症状は1件だけなので選んだ時点で閉じる。
    /// 対処は複数選べるので、続けて選べるよう開いたままにする
    private var closesOnSelect: Bool { kind == .symptom }

    @Environment(\.dismiss) private var dismiss
    @State private var newTagName = ""
    /// 編集中のタグ ID。nil なら追加モード。
    /// 別シートを開かず、この欄がそのまま編集欄に変わる
    @State private var editingTagID: String? = nil
    @FocusState private var newTagFocused: Bool

    /// いま編集中か。見出しとボタンの文言を切り替える
    private var isEditing: Bool { editingTagID != nil }
    /// 上限に達して追加できなかったときに出す案内
    @State private var showTagLimitAlert = false

    private var settings: AppSettings { AppSettings.shared }

    /// シートの背景。記録画面の上に症状/対処シートが重なるので、
    /// 下の画面と同じ灰色だとどれを操作しているのか分からなくなる。
    /// 色相でシートの種類が分かるように、標準の灰色へ淡く色を混ぜる
    private var sheetBackground: Color {
        .azTintedSheetBackground(kind == .symptom ? .tintColor : .systemOrange)
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
                                .onSubmit { commitTag() }
                                // 保存時に黙って切ると入力した名前と違うものが登録されるので、
                                // 入力の時点で上限を超えさせない
                                .onChange(of: newTagName) { _, value in
                                    if value.count > SymptomLimits.tagNameMaxLength {
                                        newTagName = String(value.prefix(SymptomLimits.tagNameMaxLength))
                                    }
                                }
                            // 編集中は「変更」、それ以外は「追加」。欄はひとつのまま役割が変わる
                            // List の行に置く Button は borderless を明示する。
                            // 既定のままだと行全体のタップとして扱われ、
                            // 同じ行に複数あるとどれも反応しなくなる
                            Button(isEditing ? "action.update" : "action.add") { commitTag() }
                                .buttonStyle(.borderless)
                                .disabled(trimmedNewTagName.isEmpty)
                        }

                        // 編集を始めたら、やめる手段も同じ場所に出す
                        if isEditing {
                            Button("symptom.picker.editCancel", role: .cancel) { endEditing() }
                                .buttonStyle(.borderless)
                        }

                        // 入力中に似た項目を出す。
                        // 同じものを別名で作ってしまう前に気づけるようにする。
                        // 編集中は「似た名前」を出しても選び直す意味がないので出さない
                        if !isEditing, !suggestions.isEmpty {
                            tagCloud(suggestions)
                        }
                    } header: {
                        // 見出しは症状・対処で共通。編集中だけ役割を言い換える
                        Text(isEditing ? "symptom.picker.editTag" : "symptom.picker.findOrAdd")
                    } footer: {
                        // 使い方は先頭のヘルプで伝えているので、ここは候補の説明だけにする
                        if !isEditing, !suggestions.isEmpty {
                            Text("symptom.picker.suggestions")
                        }
                    }

                    // 症状・対処とも、プリセットとユーザー追加を同じ1つの列に混ぜ、
                    // 直近に使った順で並べる。分類で分けると、実際に使う症状が
                    // 数個しかない個人利用では見出しばかりで探しにくかった
                    Section {
                        tagCloud(pickerItems)
                    }
                }
                .listStyle(.insetGrouped)
                // 背景はシート全体で1枚にしたいので List 自身の背景は消す
                .scrollContentBackground(.hidden)
                // タグを選ぼうとスクロールしたらキーボードを引き下げる。
                // 名前を打ったあと一覧を見たい場面が多く、いちいち閉じるのが手間になる
                .scrollDismissesKeyboard(.immediately)
            }
            // 選択はこのシートだけで行うので、タイトルも「選ぶ」と言い切る
            .navigationTitle(kind == .symptom ? "symptom.picker.title" : "remedy.picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 入力欄の外をタップして閉じる方式は、List の行内ボタンと
                // タップを奪い合って「変更」が効かなくなるので採らない。
                // キーボードの上に閉じる手段を置き、スクロールでも下がるようにする
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        newTagFocused = false
                    } label: {
                        // 文字より、下向きにしまう動きがそのまま分かる絵にする
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel(Text("action.done"))
                }
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
                if !closesOnSelect {
                    // 複数選ぶシートは自動で閉じないので、終わりを示すボタンを置く。
                    // 選択はタップした時点で記録へ反映済みなので、ここは閉じるだけ。
                    // そのため下スワイプやナビの閉じるで抜けても結果は同じになる
                    // （「完了」を押さないと取り消される、という作りにはしない）
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("action.done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert(
            Text(String(
                format: String(localized: "symptom.picker.tagLimit"),
                SymptomLimits.maxTagsPerList
            )),
            isPresented: $showTagLimitAlert
        ) {
            Button("action.close", role: .cancel) {}
        }
        // ナビゲーションバーの下まで色を回すため、背景はシート側に指定する
        .presentationBackground(sheetBackground)
        // 症状・対処とも辞書が縦に長いので、最初から全画面で出す
        .presentationDetents([.large])
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
                    // プリセットもユーザー追加も、長押しで同じ編集欄に載せる。
                    // 削除は用意しない（過去の記録が名前を参照しているため）
                    onLongPress: { beginEditing(id: item.id, title: item.title) }
                ) {
                    onSelect(item.id)
                    // 症状は1件だけなので選んだら閉じる。
                    // 対処はここが唯一の選択場所になったので、閉じずに続けて選べるようにする
                    if closesOnSelect { dismiss() }
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

    /// 一覧に出す項目。辞書とユーザー追加をひとつのマスタとして扱い、
    /// 直近に使った順で並べる（未使用は辞書の登録順、ユーザー追加はその後）。
    /// 症状・対処で同じ規則にする
    private var pickerItems: [(id: String, title: String)] {
        let list = kind == .symptom ? settings.symptomTags : settings.medicineTags
        let catalogIDs: [String] = kind == .symptom
            ? SymptomCatalog.visibleIDs
            : MedicineCatalog.all.map(\.id)

        // 辞書の登録順を覚えておき、未使用タグの並びに使う
        let catalogOrder = Dictionary(
            uniqueKeysWithValues: catalogIDs.enumerated().map { ($1, $0) }
        )
        var ids = catalogIDs
        // 辞書に無いユーザー追加分を足す（一度でも使ったものは必ず見えるようにする）。
        //
        // ただし「辞書から消えた ID」は出さない。自分で名前を付けたタグは
        // customName を持つので出せるが、プリセットだった ID は名前の引き先が
        // 無くなっており、そのまま並べると "hayFever" のような生の ID が見えてしまう
        let known = Set(ids)
        ids += list.orderedIncludingHidden
            .filter { tag in
                guard !known.contains(tag.id) else { return false }
                if !tag.customName.isEmpty { return true }
                return kind == .symptom
                    ? SymptomCatalog.entry(for: tag.id) != nil
                    : MedicineCatalog.entry(for: tag.id) != nil
            }
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
                let tag = list.tag(for: id)
                let name = kind == .symptom
                    ? (tag?.symptomDisplayName
                        ?? SymptomCatalog.entry(for: id)?.localizedName ?? id)
                    : (tag?.medicineDisplayName
                        ?? MedicineCatalog.entry(for: id)?.localizedName ?? id)
                return (id, name)
            }
    }

    // MARK: - ユーザー追加

    // MARK: 追加・編集

    /// 長押しされたタグを編集欄に載せる。プリセットとユーザー追加を区別しない
    private func beginEditing(id: String, title: String) {
        editingTagID = id
        newTagName = title
        newTagFocused = true
    }

    private func endEditing() {
        editingTagID = nil
        newTagName = ""
        newTagFocused = false
    }

    /// 「追加」または「変更」。編集中かどうかで動きを振り分ける
    private func commitTag() {
        if let editingTagID {
            updateTag(id: editingTagID)
        } else {
            addUserDefinedTag()
        }
    }

    /// 既存タグの名前と分類を書き換える。プリセットも同じ経路で直せる
    private func updateTag(id: String) {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }

        switch kind {
        case .symptom:
            var list = settings.symptomTags
            list.upsertName(id: id, to: name)
            settings.symptomTags = list
        case .medicine:
            var list = settings.medicineTags
            list.upsertName(id: id, to: name)
            settings.medicineTags = list
        }
        endEditing()
    }

    private func addUserDefinedTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }

        // 「花粉症」のようにプリセットや追加済みのタグと同じ名前が打たれたら、
        // 新しい ID は作らず既存のものを選ぶ。別IDで重複すると集計まで割れてしまう
        let matched = existingID(forName: name)
        let id = matched ?? SymptomTag.newUserDefinedID()
        // 辞書に当たったときは名前を上書きしない（ローカライズ名のまま使う）
        let customName = matched == nil ? name : ""

        // 上限に達していたら足さずに知らせる。黙って消えるのが一番困る
        switch kind {
        case .symptom:
            var list = settings.symptomTags
            guard list.add(id: id, customName: customName) else {
                showTagLimitAlert = true
                return
            }
            settings.symptomTags = list
        case .medicine:
            var list = settings.medicineTags
            guard list.add(id: id, customName: customName) else {
                showTagLimitAlert = true
                return
            }
            settings.medicineTags = list
        }
        newTagName = ""
        newTagFocused = false
        onSelect(id)
        if closesOnSelect { dismiss() }
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
