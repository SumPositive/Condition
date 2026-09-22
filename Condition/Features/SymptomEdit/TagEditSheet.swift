// TagEditSheet.swift
// 自分で追加したタグの名前と種別を直すシート
//
// 削除は用意しない。過去の記録が ID で名前を参照しているため、
// 消すと一覧に UUID が出てしまう（外したいときは記録画面のタグ行から選び直す）。

import SwiftUI

struct TagEditSheet: View {

    let kind: SymptomTagKind
    let tagID: String

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var nameFocused: Bool
    /// 中身の実測高さ。シートの高さを内容ぴったりに合わせるために使う
    @State private var contentHeight: CGFloat = 0

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        NavigationStack {
            // Form だとグループ枠の余白で縦に伸び、キーボードが出たときに
            // 入力欄が隠れやすい。項目は名前ひとつなので素の並びで詰める
            VStack(alignment: .leading, spacing: 12) {
                TextField("symptom.picker.newName", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    // 保存時に黙って切らず、入力の時点で止める
                    .onChange(of: name) { _, value in
                        if value.count > SymptomLimits.tagNameMaxLength {
                            name = String(value.prefix(SymptomLimits.tagNameMaxLength))
                        }
                    }
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // 名前を変えると1言語ぶんだけ保存され、端末の言語を変えても
                // その名前のままになる。戻せることを示しておく
                if !isUserDefined {
                    Text("tag.edit.presetNote")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 辞書にある項目だけ、上書きをやめて既定名へ戻せる
                if !isUserDefined, hasCustomName {
                    Button("tag.edit.reset", role: .destructive) { resetName() }
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                contentHeight = height
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("tag.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.done") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
        // 内容ぴったりの高さにすると、キーボードの上に入力欄と
        // ナビゲーションバーの完了ボタンが両方見える
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        // 下の症状/対処シートは淡く色を混ぜた灰色。ここは白のままにして、
        // 一番手前の層であることが色の違いで分かるようにする
        .presentationBackground(Color(.systemBackground))
        .azAppFontScale()
    }

    /// シートの高さ。実測した中身にナビゲーションバー（44pt）を足す。
    /// 実測前（0）は文字サイズを上げたときでも収まる控えめな初期値を使う
    private var sheetHeight: CGFloat {
        let measured = contentHeight > 0 ? contentHeight : 120
        return min(max(measured + 44, 140), 420)
    }

    private var isUserDefined: Bool { SymptomTag.isUserDefinedID(tagID) }

    /// 既定名から変えてあるか（戻すボタンの出し分けに使う）
    private var hasCustomName: Bool {
        let list = kind == .symptom ? settings.symptomTags : settings.medicineTags
        return !(list.tag(for: tagID)?.customName.isEmpty ?? true)
    }

    private func resetName() {
        switch kind {
        case .symptom:
            var list = settings.symptomTags
            list.resetName(id: tagID)
            settings.symptomTags = list
        case .medicine:
            var list = settings.medicineTags
            list.resetName(id: tagID)
            settings.medicineTags = list
        }
        dismiss()
    }

    private func load() {
        let list = kind == .symptom ? settings.symptomTags : settings.medicineTags
        // まだ一度も使っていないプリセットはタグリストに無い。
        // その場合は辞書の名前を初期値にする（空欄のまま出さない）
        if let tag = list.tag(for: tagID) {
            name = kind == .symptom ? tag.symptomDisplayName : tag.medicineDisplayName
        } else {
            name = defaultName
        }
        nameFocused = true
    }

    /// 辞書に載っている既定の名前。辞書に無ければ ID をそのまま返す
    private var defaultName: String {
        switch kind {
        case .symptom:  return SymptomCatalog.entry(for: tagID)?.localizedName ?? tagID
        case .medicine: return MedicineCatalog.entry(for: tagID)?.localizedName ?? tagID
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 既定名のまま完了したときは上書きを残さない。
        // 残すと「戻す」ボタンが不要に出るうえ、端末の言語を変えても
        // その言語の名前に切り替わらなくなる
        let isDefault = !isUserDefined && trimmed == defaultName

        switch kind {
        case .symptom:
            var list = settings.symptomTags
            // まだ一度も使っていないプリセットはタグリストに無いので、
            // 先に登録しないと rename が何もせず名前が保存されない
            list.add(id: tagID)
            if isDefault {
                list.resetName(id: tagID)
            } else {
                list.rename(id: tagID, to: trimmed)
            }
            settings.symptomTags = list
        case .medicine:
            var list = settings.medicineTags
            list.add(id: tagID)
            if isDefault {
                list.resetName(id: tagID)
            } else {
                list.rename(id: tagID, to: trimmed)
            }
            settings.medicineTags = list
        }
        dismiss()
    }
}

