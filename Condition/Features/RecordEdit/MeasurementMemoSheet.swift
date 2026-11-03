// 複数回測定シートのメモ（測定場所・機器／メモ1／メモ2／注意フラグ）を入力するシート
// 環境・睡眠と同じく、記録画面には1行の要約だけを置き、入力はこのシートで行う

import SwiftUI

/// 複数回測定のメモ欄の値
struct MeasurementMemo: Equatable {
    var equipment: String = ""
    var note1: String = ""
    var note2: String = ""
    var caution: Bool = false

    /// 測定場所・機器の最大文字数
    static let equipmentMaxLength = 100

    var hasAnyValue: Bool {
        !equipment.isEmpty || !note1.isEmpty || !note2.isEmpty || caution
    }

    /// 記録画面の行に出す要約（入力済みの文字の項目だけを並べる。注意フラグはアイコンで示す）
    var summary: String {
        var parts: [String] = []
        for text in [equipment, note1, note2] {
            // 改行は1行の要約では読みにくいので空白にする
            let line = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !line.isEmpty { parts.append(line) }
        }
        return parts.joined(separator: "  /  ")
    }
}

/// 記録画面に置くメモの行
struct MeasurementMemoRow: View {
    let memo: MeasurementMemo
    let action: () -> Void

    var body: some View {
        RecordAuxRow(
            titleKey: "record.memo.section",
            systemImage: "note.text",
            summary: memo.hasAnyValue ? memo.summary : String(localized: "sleep.notEntered"),
            hasValue: memo.hasAnyValue,
            helpKey: "record.memo.help",
            // 注意フラグはシート内のトグルと同じオレンジの旗で示す
            summarySymbol: memo.caution ? "flag.fill" : nil,
            summarySymbolColor: .orange,
            action: action
        )
    }
}

/// メモを入力するシート
struct MeasurementMemoSheet: View {
    /// 測定場所・機器の候補（記録画面と共有する）
    let candidateStore: EquipmentCandidateStore
    let onDone: (MeasurementMemo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MeasurementMemo
    @FocusState private var focusEquipment: Bool
    @FocusState private var focusNote1: Bool
    @FocusState private var focusNote2: Bool
    /// 候補選択直後にIMEが未確定文字を書き戻すのを防ぐ
    @State private var pendingEquipmentSelection: String?
    /// 内容に合わせたシートの高さ（ナビバーと下部セーフエリアを含む）
    @State private var sheetHeight: CGFloat = 360

    init(
        memo: MeasurementMemo,
        candidateStore: EquipmentCandidateStore,
        onDone: @escaping (MeasurementMemo) -> Void
    ) {
        self.candidateStore = candidateStore
        self.onDone = onDone
        _draft = State(initialValue: memo)
    }

    /// 入力語へ一致する候補（入力中だけ出す）
    private var shownCandidates: [String] {
        guard focusEquipment else { return [] }
        return candidateStore.shownCandidates(matching: draft.equipment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    equipmentField
                    // 候補は入力欄の直下に並べ、タップで入力する
                    if !shownCandidates.isEmpty {
                        candidateList
                    }
                }
                Section {
                    AZMemoEditor(
                        placeholder: "record.memo1",
                        text: $draft.note1,
                        isFocused: $focusNote1
                    )
                    AZMemoEditor(
                        placeholder: "record.memo2",
                        text: $draft.note2,
                        isFocused: $focusNote2
                    )
                }
                Section {
                    Toggle(isOn: $draft.caution) {
                        HStack(spacing: 6) {
                            if draft.caution {
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text("record.cautionFlag")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // 中身の高さ＋上下の余白（ナビバー・セーフエリア）をシートの高さにする。
            // 候補の表示やメモの行数で高さが変わっても追従する
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            } action: { _, height in
                if 0 < height { sheetHeight = height }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        // 記録画面のメモ行と共通のアイコンで表示する
                        Image(systemName: "note.text")
                        Text("record.memo.section")
                    }
                    .font(.headline)
                    // シートのタイトルは通常のラベル色にする（他のシートと揃える）
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("record.memo.section"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    // 環境シートと同じ下向き矢印で閉じる。反映は onDisappear に任せ、スワイプで閉じた場合と揃える
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel(Text("action.close"))
                }
            }
        }
        // 中身に合わせた高さで開き、長いメモは大きいシートへ逃がす
        .presentationDetents([.height(sheetHeight), .large])
        .presentationDragIndicator(.visible)
        // 下の記録画面と区別できるよう、紙の色に近い茶色を淡く混ぜる
        .presentationBackground(Color.azTintedSheetBackground(.systemBrown))
        // 閉じ方によらず入力を反映する（閉じるボタン・スワイプのどちらでも同じ）
        .onDisappear { onDone(normalized(draft)) }
    }

    // MARK: 測定場所・機器

    private var equipmentField: some View {
        HStack(spacing: 8) {
            TextField("record.device", text: $draft.equipment)
                .focused($focusEquipment)
                .onChange(of: focusEquipment) { _, isFocused in
                    // 再入力時は候補選択の保留値を解除する
                    if isFocused { pendingEquipmentSelection = nil }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { focusEquipment = false }
                .onChange(of: draft.equipment) { _, newValue in
                    // IMEの遅延書き戻しより候補選択を優先する
                    if let pending = pendingEquipmentSelection {
                        if newValue == pending {
                            pendingEquipmentSelection = nil
                        } else {
                            draft.equipment = pending
                        }
                        return
                    }
                    if MeasurementMemo.equipmentMaxLength < newValue.count {
                        draft.equipment = String(newValue.prefix(MeasurementMemo.equipmentMaxLength))
                        return
                    }
                    // 末尾改行を除去
                    let trimmed = newValue.replacingOccurrences(
                        of: "\n+$", with: "", options: .regularExpression
                    )
                    if trimmed != newValue { draft.equipment = trimmed }
                }

            // 入力中だけ内容をまとめて消せるようにする
            if !draft.equipment.isEmpty {
                Button {
                    pendingEquipmentSelection = nil
                    draft.equipment = ""
                    focusEquipment = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("action.clear"))
            }
        }
    }

    private var candidateList: some View {
        AZFlowLayout(spacing: 8, rowSpacing: 6, alignment: .leading, packToFill: true) {
            ForEach(shownCandidates, id: \.self) { candidate in
                Button {
                    selectCandidate(candidate)
                } label: {
                    Text(candidate)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// IMEを閉じてから候補値を確定する
    private func selectCandidate(_ candidate: String) {
        pendingEquipmentSelection = candidate
        focusEquipment = false
        DispatchQueue.main.async {
            draft.equipment = candidate
        }
    }

    /// 保存用に前後の改行を落とす
    private func normalized(_ memo: MeasurementMemo) -> MeasurementMemo {
        var result = memo
        result.equipment = memo.equipment.trimmingCharacters(in: .newlines)
        result.note1 = memo.note1.trimmingCharacters(in: .newlines)
        result.note2 = memo.note2.trimmingCharacters(in: .newlines)
        return result
    }
}
