// SymptomEditView.swift
// 症状メモの記録シート（新規・編集）

import SwiftUI
import SwiftData

struct SymptomEditView: View {

    var onModifiedChanged: ((Bool) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: SymptomEditViewModel
    @State private var showSymptomPicker = false
    @State private var showMedicinePicker = false
    @State private var showTriggerPicker = false
    /// 未保存の変更を取り消す確認
    @State private var showDiscardConfirmation = false
    @State private var showEnvironmentSheet = false
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var didEnterBackground = false
    @State private var showStaleDateAlert = false
    /// 保存後に同時発生した2件目を記録するかの確認
    @State private var showContinueAlert = false
    @FocusState private var noteFocused: Bool

    private var settings: AppSettings { AppSettings.shared }

    init(mode: SymptomEditViewModel.Mode, onModifiedChanged: ((Bool) -> Void)? = nil) {
        self.onModifiedChanged = onModifiedChanged
        _vm = State(initialValue: SymptomEditViewModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                symptomSection
                noteSection
                if isEditingRecord {
                    continuationSection
                }
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
                    Button("action.cancel") {
                        handleCancelTapped()
                    }
                    // 未保存の内容は標準の確認ダイアログから取り消す
                    .confirmationDialog(
                        "action.cancel",
                        isPresented: $showDiscardConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("action.discard", role: .destructive) { dismiss() }
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
            .sheet(isPresented: $showTriggerPicker) {
                SymptomPickerSheet(
                    kind: .trigger,
                    selectedIDs: Set(vm.triggerIDs)
                ) { id in
                    addToTagList(id: id, kind: .trigger)
                    vm.toggleTrigger(id)
                }
            }
            .sheet(isPresented: $showStartPicker) {
                DatePickerSheet(date: Binding(
                    get: { vm.startAt }, set: { vm.startAt = $0 }
                )) {
                    // 開始を遅らせて終了より後になったら終了も合わせる
                    if vm.progressState == .completedKnown, vm.endAt < vm.startAt {
                        vm.endAt = vm.startAt
                    }
                }
            }
            .sheet(isPresented: $showEndPicker) {
                DatePickerSheet(date: Binding(
                    get: { vm.endAt }, set: { vm.endAt = $0 }
                ), onUnknown: {
                    vm.setEndDateUnknown()
                }) {
                    vm.setEndDateKnown()
                }
            }
            .sheet(isPresented: $showEnvironmentSheet) {
                EnvironmentEditView(
                    snapshot: vm.environment,
                    recordDate: vm.startAt
                ) { updated in
                    // 環境シートは閉じるたびに結果を返すので、開いただけでも
                    // ここが呼ばれる。値が変わっていなければ代入しない
                    // （代入すると markModified が走り、キャンセル時に
                    // 変更取り消しの確認が表示されてしまう）
                    if updated != vm.environment { vm.environment = updated }
                }
            }
            .alert("record.datetime.stale.title", isPresented: $showStaleDateAlert) {
                Button("record.datetime.stale.useNow") { useCurrentDateAfterForeground() }
                Button("record.datetime.stale.keep", role: .cancel) {}
            } message: {
                Text("record.datetime.stale.message")
            }
            .alert("symptom.continue.title", isPresented: $showContinueAlert) {
                Button("symptom.continue.addAnother") { prepareContinuation() }
                Button("action.close", role: .cancel) { dismiss() }
            } message: {
                Text("symptom.continue.message")
            }
            // 未保存の変更があるときはスワイプで閉じさせない
            .interactiveDismissDisabled(vm.isModified)
            .onChange(of: vm.isModified) { _, newValue in onModifiedChanged?(newValue) }
            // 新規シートがバックグラウンドから戻り、日時が30分以上ずれていれば確認する
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    didEnterBackground = true
                case .active:
                    guard didEnterBackground else { return }
                    didEnterBackground = false
                    if isNewRecord,
                       ForegroundRecordDateCheck.needsConfirmation(recordDate: vm.startAt) {
                        showStaleDateAlert = true
                    }
                default:
                    break
                }
            }
        }
        // .sheet では App の dynamicTypeSize が届かないことがあるため明示する
        .azAppFontScale()
    }

    // MARK: - 日時

    private var isNewRecord: Bool {
        if case .addNew = vm.mode { return true }
        return false
    }

    private var isEditingRecord: Bool {
        if case .edit = vm.mode { return true }
        return false
    }

    /// 発症日時を現在へ更新し、必要なら終息日時も合わせる
    private func useCurrentDateAfterForeground() {
        let now = Date()
        vm.startAt = now
        if vm.progressState == .completedKnown, vm.endAt < now {
            vm.endAt = now
        }
    }

    private var dateSection: some View {
        Section {
            LabeledContent("symptom.startAt") {
                dateButton(date: vm.startAt) { showStartPicker = true }
            }

            // 終息の有無を従来どおりスイッチで選び、日時不明はカレンダーから指定する
            HStack(spacing: 8) {
                Text("symptom.progress.finished")
                Toggle("", isOn: Binding(
                    get: { vm.hasEnded },
                    set: { vm.setHasEnded($0) }
                ))
                .labelsHidden()
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
                    if vm.progressState == .completedUnknown {
                        Button { showEndPicker = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "smallcircle.filled.circle")
                                Text("action.unknown")
                            }
                        }
                    } else {
                        dateButton(date: vm.endAt) { showEndPicker = true }
                    }
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

    /// アイコンの幅を日時へ譲り、発症・終息日時を読みやすく表示する
    private func dateButton(date: Date, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(Self.dateTimeFormatter.string(from: date))
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 測定シートと同じ書式（曜日つきの年月日＋時刻）
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMdEjmm")
        return f
    }()

    // MARK: - 症状・程度・対処

    /// 症状とその程度、直前の状況、とった対処は一続きの入力なので1つのセクションに収める。
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

            // 発症の手前にあった状況は、対処より時間的に前なので上に置く
            // 空欄は未選択とし、思い当たらない場合も通常のタグとして選ぶ
            selectionRow(
                title: "symptom.section.trigger",
                chips: selectedTriggerChips,
                emptyKey: "trigger.select.unselected",
                help: ("symptom.help.trigger", "helpDismissed.symptom.trigger")
            ) {
                showTriggerPicker = true
            }

            selectionRow(
                title: "symptom.section.remedy",
                chips: selectedMedicineChips,
                help: ("symptom.help.remedy", "helpDismissed.symptom.remedy")
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

    /// 選択中の直前の状況。記録に入っている順（選んだ順）で出す。
    /// 対処（アクセント色）と見分けられるよう、選択シートのタグと同じ色にする
    private var selectedTriggerChips: [(id: String, title: String, color: Color)] {
        vm.triggerIDs.map { id in
            let tag = settings.triggerTags.tag(for: id) ?? SymptomTag(id: id)
            let color: Color = id == TriggerCatalog.nothingComesToMindID ? .blue : .purple
            return (id, tag.triggerDisplayName, color)
        }
    }

    // MARK: - 選択行

    /// 「見出し ＋ (?) ＋ 選択済みのタグ ＋ ＞」の1セル。タップでシートを開く。
    /// タグは表示専用（解除もシート側で行う）なので、セル全体で開く。
    /// Button で包むと中の (?) のタップが親に吸われるため、環境の行と同じく onTapGesture にする
    private func selectionRow(
        title: LocalizedStringKey,
        chips: [(id: String, title: String, color: Color)],
        emptyKey: LocalizedStringKey = "symptom.select.empty",
        help: (messageKey: LocalizedStringKey, storageKey: String)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: true, vertical: false)
            if let help {
                BeginnerHelpBanner(
                    help.messageKey,
                    storageKey: help.storageKey,
                    compact: true,
                    tight: true
                )
            }
            Spacer(minLength: 4)
            if chips.isEmpty {
                Text(emptyKey)
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
        .onTapGesture(perform: action)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
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

    /// 編集中の記録と同時に出た別の症状を追加する導線
    private var continuationSection: some View {
        Section {
            Button {
                saveAndContinue()
            } label: {
                Label("symptom.continue.addAnother", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(!vm.canSave)
        } footer: {
            Text("symptom.continue.editHelp")
        }
    }

    // MARK: - 環境（天候・室内・端末気圧）

    /// 中身は測定記録と共用の環境シートに置く。
    /// 記録画面には現在の要約と、開くためのボタンだけを出す。
    /// 発症・終息と同じ「その時の状況」なので日時セクションに並べる
    private var environmentRow: some View {
        HStack(spacing: 8) {
            // ヘルプは Button の中に入れるとタップが親に吸われるので外に出す
            // 測定画面・環境シートと共通のアイコンを添える
            Label("environment.title", systemImage: "thermometer.sun")
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
        // 0℃は有効値なので、値ではなく入力有無フラグで判定する
        if snapshot.isTempSet {
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

    /// 未変更ならそのまま閉じ、変更がある場合だけ確認する
    private func handleCancelTapped() {
        guard vm.isModified else {
            dismiss()
            return
        }
        showDiscardConfirmation = true
    }

    // MARK: - 保存

    private func saveAndDismiss() {
        guard vm.save(in: context) != nil else { return }
        onModifiedChanged?(false)
        // 編集時は従来どおり閉じ、新規時だけ同時に出た症状を追加できるようにする
        if isNewRecord {
            showContinueAlert = true
        } else {
            dismiss()
        }
    }

    /// 編集内容を保存してから、同時発生した症状の入力へ移る
    private func saveAndContinue() {
        guard vm.save(in: context) != nil else { return }
        onModifiedChanged?(false)
        prepareContinuation()
    }

    /// 1件目と同時に出た症状の入力へ切り替える
    private func prepareContinuation() {
        noteFocused = false
        vm = vm.makeContinuation()
        onModifiedChanged?(false)
    }

    /// 辞書から選ばれたタグをタグリストへ入れる
    private func addToTagList(id: String, kind: SymptomTagKind) {
        var list = kind.tagList
        list.add(id: id)
        kind.tagList = list
    }
}
