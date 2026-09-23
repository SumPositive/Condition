// SymptomEditView.swift
// 症状メモの記録シート（新規・編集）

import SwiftUI
import SwiftData

struct SymptomEditView: View {

    let mode: SymptomEditViewModel.Mode
    var onModifiedChanged: ((Bool) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SymptomEditViewModel
    @State private var showSymptomPicker = false
    @State private var showMedicinePicker = false
    /// キャンセルの二段タップ（測定シートと同じ作法）。
    /// 1回目で赤くなり、2秒以内にもう一度押すと破棄する
    @State private var isCancelArmed = false
    @State private var cancelArmTask: Task<Void, Never>? = nil
    @State private var showEnvironmentSheet = false
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    /// 保存後に「続けて記録」で2件目を作るかの確認
    @State private var showContinueSheet = false
    @FocusState private var noteFocused: Bool

    private var settings: AppSettings { AppSettings.shared }

    init(mode: SymptomEditViewModel.Mode, onModifiedChanged: ((Bool) -> Void)? = nil) {
        self.mode = mode
        self.onModifiedChanged = onModifiedChanged
        _vm = State(initialValue: SymptomEditViewModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                symptomSection
                noteSection
            }
            // メモを打ったあと下へスクロールしたらキーボードを引き下げる。
            // 複数行入力なので、指の動きに追従する .interactively にする
            // （測定シートのメモ欄と同じ扱い）
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Label はツールバー内だとアイコンだけに畳まれることがあるので、
                    // HStack で並べて必ずアイコンと文字の両方を出す
                    HStack(spacing: 4) {
                        Image(systemName: "at.badge.plus")
                        Text("symptom.edit.title")
                    }
                    .font(.headline)
                    // シートのタイトルは通常のラベル色にする（他のシートと揃える）
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize()
                    // アイコンと文字が別々に読み上げられないよう1つにまとめる
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("symptom.edit.title"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        handleCancelTapped()
                    } label: {
                        Text("action.cancel")
                            .font(vm.isModified ? .caption2 : .body)
                            .foregroundColor(isCancelArmed ? .white : .primary)
                            .padding(.horizontal, vm.isModified ? 6 : 0)
                            .padding(.vertical, vm.isModified ? 3 : 0)
                            .background {
                                if isCancelArmed {
                                    Capsule().fill(Color.red)
                                }
                            }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.save") { saveAndDismiss() }
                        .disabled(!vm.canSave)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showSymptomPicker) {
                SymptomPickerSheet(
                    kind: .symptom,
                    selectedIDs: vm.symptomID.isEmpty ? [] : [vm.symptomID]
                ) { id in
                    addToTagList(id: id, kind: .symptom)
                    vm.symptomID = id
                }
            }
            .sheet(isPresented: $showMedicinePicker) {
                SymptomPickerSheet(
                    kind: .medicine,
                    selectedIDs: Set(vm.medicineIDs)
                ) { id in
                    addToTagList(id: id, kind: .medicine)
                    // シートが唯一の選択場所になったので、もう一度押したら外せるようにする
                    vm.toggleMedicine(id)
                }
            }
            .sheet(isPresented: $showStartPicker) {
                DatePickerSheet(date: Binding(
                    get: { vm.startAt }, set: { vm.startAt = $0 }
                )) {
                    // 開始を遅らせて終了より後になったら終了も合わせる
                    if vm.hasEnded, vm.endAt < vm.startAt {
                        vm.endAt = vm.startAt
                    }
                }
            }
            .sheet(isPresented: $showEndPicker) {
                DatePickerSheet(date: Binding(
                    get: { vm.endAt }, set: { vm.endAt = $0 }
                )) {}
            }
            .sheet(isPresented: $showEnvironmentSheet) {
                EnvironmentEditView(
                    snapshot: vm.environment,
                    recordDate: vm.startAt
                ) { updated in
                    vm.environment = updated
                }
            }
            // 未保存の変更があるときはスワイプで閉じさせない（測定シートと同じ）。
            // 破棄はキャンセルの二段タップでのみ行う
            .interactiveDismissDisabled(vm.isModified)
            .onChange(of: vm.isModified) { _, newValue in onModifiedChanged?(newValue) }
            .onDisappear { cancelArmTask?.cancel() }
        }
        // .sheet では App の dynamicTypeSize が届かないことがあるため明示する
        .azAppFontScale()
    }

    // MARK: - 日時

    private var dateSection: some View {
        Section {
            LabeledContent("symptom.startAt") {
                dateButton(date: vm.startAt) { showStartPicker = true }
            }

            // 「終息 / スイッチ / 日時」を1行に収める。
            // OFF のうちは日時を出さない（入力できない値を見せない）
            HStack(spacing: 8) {
                Text("symptom.progress.finished")
                Toggle("", isOn: Binding(
                    get: { vm.hasEnded },
                    set: { vm.setHasEnded($0) }
                ))
                .labelsHidden()
                // ヘルプはスイッチの真横に置く（1行を専有させない）。
                // ONにしたあとは説明が要らないのでOFFの間だけ出す。
                // tight 指定で 19pt まで小さくしてあり、Toggle（31pt）より低いので
                // 出し分けても行の高さは変わらない
                if !vm.hasEnded {
                    BeginnerHelpBanner(
                        "symptom.help.ended",
                        storageKey: "helpDismissed.symptom.ended",
                        compact: true,
                        tight: true
                    )
                }
                Spacer(minLength: 4)
                if vm.hasEnded {
                    dateButton(date: vm.endAt) { showEndPicker = true }
                }
            }

            if vm.hasInvalidRange {
                Label("symptom.error.endBeforeStart", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            environmentRow
        }
    }

    /// 測定シートの日時ボタンと同じ見た目・同じ日時書式にする
    private func dateButton(date: Date, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(Self.dateTimeFormatter.string(from: date))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .font(.callout)
        }
    }

    /// 測定シートと同じ書式（曜日つきの年月日＋時刻）
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMdEjmm")
        return f
    }()

    // MARK: - 症状・程度・対処

    /// 症状とその程度、とった対処は一続きの入力なので1つのセクションに収める。
    /// 見出しは行のラベルと同じ語になってしまうため置かない
    private var symptomSection: some View {
        Section {
            // 選択済みのものだけを出し、選び直しはシートで行う。
            // 記録画面にも候補を並べると、シートと二段構えになって
            // 「どちらで選ぶのか」が分かりにくかった
            selectionRow(
                title: "symptom.section.symptom",
                chips: selectedSymptomChips
            ) {
                showSymptomPicker = true
            }

            // 程度は症状に付く値なので同じセクションに置く。
            // 既定の minOptionWidth(96) は4択だと折り返すが、実際に要る幅は
            // 最長の「中くらい」でも約92pt なので下げて1行に収める
            AZAdaptiveRadioRow(
                options: SymptomSeverity.selectableCases,
                selection: Binding(
                    get: { vm.severity },
                    set: { vm.severity = $0 }
                ),
                minOptionWidth: 56,
                horizontalPadding: 10,
                optionSpacing: 2
            ) {
                Text("symptom.severity")
                    .font(.subheadline)
            } label: { level in
                Text(LocalizedStringKey(level.labelKey))
            }

            selectionRow(
                title: "symptom.section.remedy",
                chips: selectedMedicineChips
            ) {
                showMedicinePicker = true
            }
        }
    }

    /// 選択中の症状。1件だけなので0個か1個になる
    private var selectedSymptomChips: [(id: String, title: String, color: Color)] {
        guard !vm.symptomID.isEmpty else { return [] }
        let tag = settings.symptomTags.tag(for: vm.symptomID) ?? SymptomTag(id: vm.symptomID)
        return [(tag.id, tag.symptomDisplayName, tag.symptomColor)]
    }

    /// 選択中の対処。記録に入っている順（選んだ順）で出す
    private var selectedMedicineChips: [(id: String, title: String, color: Color)] {
        vm.medicineIDs.map { id in
            let tag = settings.medicineTags.tag(for: id) ?? SymptomTag(id: id)
            return (id, tag.medicineDisplayName, Color.accentColor)
        }
    }

    // MARK: - 選択行

    /// 「見出し ＋ 選択済みのタグ ＋ ＞」の1セル。タップでシートを開く。
    /// タグは表示専用（解除もシート側で行う）なので、セル全体を1つのボタンにする
    private func selectionRow(
        title: LocalizedStringKey,
        chips: [(id: String, title: String, color: Color)],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                if chips.isEmpty {
                    Text("symptom.select.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    // 選択済みは右寄せで折り返す。多いと縦に伸びるが、
                    // 省略するより「何を選んだか」が分かるほうを優先する
                    FlowLayout(spacing: 6, alignment: .trailing) {
                        ForEach(chips, id: \.id) { chip in
                            Text(chip.title)
                                .lineLimit(1)
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(chip.color)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .azFullWidthRow()
    }

    // MARK: - メモ

    private var noteSection: some View {
        Section {
            AZMemoEditor(
                placeholder: "symptom.note.placeholder",
                // 上限は定数から埋める（文言と実装がずれないようにする）
                placeholderText: String(
                    format: String(localized: "symptom.note.placeholder"),
                    SymptomLimits.noteMaxLength
                ),
                text: Binding(
                    get: { vm.note },
                    // 保存時に黙って切ると打った文と違うものが残るので、入力の時点で止める
                    set: { vm.note = String($0.prefix(SymptomLimits.noteMaxLength)) }
                ),
                isFocused: $noteFocused
            )
            // 上限が近いときだけ残り文字数を出す（常時出すと邪魔になる）
            if vm.note.count >= SymptomLimits.noteMaxLength - 30 {
                Text(String(
                    format: String(localized: "symptom.note.remaining"),
                    SymptomLimits.noteMaxLength - vm.note.count
                ))
                .font(.caption)
                .foregroundStyle(vm.note.count >= SymptomLimits.noteMaxLength ? .orange : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } header: {
            Text("symptom.section.note")
        }
    }

    // MARK: - 環境（天候・室内・端末気圧）

    /// 中身は測定記録と共用の環境シートに置く。
    /// 記録画面には現在の要約と、開くためのボタンだけを出す。
    /// 発症・終息と同じ「その時の状況」なので日時セクションに並べる
    private var environmentRow: some View {
        HStack(spacing: 8) {
            // ヘルプは Button の中に入れるとタップが親に吸われるので外に出す
            Text("environment.title")
            BeginnerHelpBanner(
                "symptom.help.environment",
                storageKey: "helpDismissed.symptom.environment",
                compact: true,
                tight: true
            )
            Spacer(minLength: 4)
            Text(environmentSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        // ラベルや余白を含めた行全体で開けるようにする。
        // Button で包まず onTapGesture にするのは、中にある (?) の
        // タップを親へ吸わせないため（Button なら (?) が先に受け取る）
        .contentShape(Rectangle())
        .onTapGesture { showEnvironmentSheet = true }
        .azFullWidthRow()
    }

    /// ボタンに出す要約。未入力なら促す文言にする
    private var environmentSummary: String {
        let snapshot = vm.environment
        var parts: [String] = []
        if snapshot.source.isPresent, snapshot.temp_10c != 0 {
            parts.append(String(format: "%.1f℃", Double(snapshot.temp_10c) / 10))
        }
        if snapshot.pressure_10hpa > 0 {
            parts.append(String(format: "%.0fhPa", Double(snapshot.pressure_10hpa) / 10))
        }
        if snapshot.isIndoorTempSet {
            parts.append(String(
                format: String(localized: "environment.summary.indoor"),
                Double(snapshot.indoorTemp_10c) / 10
            ))
        }
        return parts.isEmpty ? String(localized: "environment.summary.empty")
            : parts.joined(separator: "  ")
    }

    // MARK: - キャンセル

    /// 未変更ならそのまま閉じる。変更があるときは1回目で赤くし、
    /// 2秒以内の2回目で破棄する（誤タップで入力を失わないため）
    private func handleCancelTapped() {
        guard vm.isModified else {
            dismiss()
            return
        }
        if isCancelArmed {
            clearCancelArmed()
            dismiss()
            return
        }
        isCancelArmed = true
        cancelArmTask?.cancel()
        cancelArmTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { isCancelArmed = false }
        }
    }

    private func clearCancelArmed() {
        cancelArmTask?.cancel()
        cancelArmTask = nil
        isCancelArmed = false
    }

    // MARK: - 保存

    private func saveAndDismiss() {
        guard vm.save(in: context) != nil else { return }
        onModifiedChanged?(false)
        dismiss()
    }

    /// 辞書から選ばれたタグをタグリストへ入れる
    private func addToTagList(id: String, kind: SymptomTagKind) {
        switch kind {
        case .symptom:
            var list = settings.symptomTags
            list.add(id: id)
            settings.symptomTags = list
        case .medicine:
            var list = settings.medicineTags
            list.add(id: id)
            settings.medicineTags = list
        }
    }
}
