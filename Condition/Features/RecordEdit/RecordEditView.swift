// RecordEditView.swift
// 記録編集画面（旧 E2editTVC 相当）

import SwiftUI
import SwiftData
import AZDial
import HealthKit

struct RecordEditView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var vm: RecordEditViewModel
    @State private var showDatePicker = false
    @State private var showDeleteAlert = false
    @State private var conflictData: RecentConflict? = nil
    @State private var isDateOptExpanded = false
    @FocusState private var focusNote1: Bool
    @FocusState private var focusNote2: Bool
    @FocusState private var focusEquipment: Bool

    private let note1AnchorID = "record-note1-anchor"
    private let note2AnchorID = "record-note2-anchor"
    private let equipmentAnchorID = "record-equipment-anchor"

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMdEjmm")
        return f
    }()

    private var settings: AppSettings { AppSettings.shared }
    private var hkService: HealthKitService { HealthKitService.shared }

    private var hkDirection: HKSyncDirection {
        HKSyncDirection(rawValue: settings.hkDirection) ?? .writeOnly
    }

    private var isNewRecord: Bool {
        if case .addNew = vm.mode { return true }
        return false
    }

    private var title: LocalizedStringKey {
        switch vm.mode {
        case .addNew:    return "record.new.title"
        case .edit:      return "record.edit.title"
        case .goalEdit:  return "goal.values"
        }
    }

    private let onHKImported: ((Int) -> Void)?
    /// 変更状態が変わるたびに呼ばれるコールバック（true=変更あり / false=変更なし or シート消滅）
    private let onModifiedChanged: ((Bool) -> Void)?

    init(mode: EditMode,
         onHKImported: ((Int) -> Void)? = nil,
         onModifiedChanged: ((Bool) -> Void)? = nil) {
        _vm = State(initialValue: RecordEditViewModel(mode: mode))
        self.onHKImported = onHKImported
        self.onModifiedChanged = onModifiedChanged
    }

    var body: some View {
        let navContent = NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    hkImportSection
                    dateSection
                    Section("record.measurements") {
                        ForEach(orderedRecordFields, id: \.rawValue) { kind in
                            fieldRow(for: kind)
                        }
                    }
                    healthKitSection

                    // メモセクション
                    Section("record.memo.section") {
                        AZMemoEditor(placeholder: "record.memo1", text: $vm.sNote1, isFocused: $focusNote1)
                            .id(note1AnchorID)
                        AZMemoEditor(placeholder: "record.memo2", text: $vm.sNote2, isFocused: $focusNote2)
                            .id(note2AnchorID)
                        AZMemoEditor(placeholder: "record.device", text: $vm.sEquipment, isFocused: $focusEquipment)
                            .id(equipmentAnchorID)
                        Toggle(isOn: $vm.bCaution) {
                            HStack(spacing: 6) {
                                if vm.bCaution {
                                    Image(systemName: "flag.fill")
                                        .foregroundStyle(.orange)
                                }
                                Text("record.cautionFlag")
                            }
                        }
                    }

                    // 削除ボタン（編集時のみ）
                    if case .edit(let record) = vm.mode {
                        Section {
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Label(
                                    "record.delete.button",
                                    systemImage: "trash"
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .alert(
                            "record.delete.confirm",
                            isPresented: $showDeleteAlert
                        ) {
                            Button("action.delete", role: .destructive) {
                                try? vm.delete(record: record, context: context)
                                dismiss()
                            }
                            Button("action.cancel", role: .cancel) {}
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.sNote1) { _, _ in scrollFocusedMemoIntoView(proxy) }
                .onChange(of: vm.sNote2) { _, _ in scrollFocusedMemoIntoView(proxy) }
                .onChange(of: vm.sEquipment) { _, _ in scrollFocusedMemoIntoView(proxy) }
                .onChange(of: focusNote1) { _, isFocused in if isFocused { scrollMemoIntoView(note1AnchorID, proxy: proxy) } }
                .onChange(of: focusNote2) { _, isFocused in if isFocused { scrollMemoIntoView(note2AnchorID, proxy: proxy) } }
                .onChange(of: focusEquipment) { _, isFocused in if isFocused { scrollMemoIntoView(equipmentAnchorID, proxy: proxy) } }
                .safeAreaInset(edge: .bottom) {
                    if isMemoFocused {
                        // キーボード上へ入力行を逃がすため、フォーカス中だけ下端余白を追加する
                        Color.clear.frame(height: 180)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        saveAndDismiss()
                    }
                    .disabled((!vm.isModified && !isNewRecord) || conflictData != nil)
                    .opacity(conflictData == nil ? 1 : 0)
                    .bold()
                    .tint(vm.isModified ? .accentColor : Color(.secondaryLabel))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $vm.dateTime) {
                    vm.onDateChanged()
                }
            }
            .sheet(item: $conflictData) { conflict in
                RecentConflictSheet(conflict: conflict) { action in
                    handleConflictAction(action, previous: conflict.previous)
                }
            }
            .onAppear {
                if isNewRecord {
                    vm.loadPreviousValues(context: context)
                }
            }
            // isModified は ViewModel の didSet で管理（View 側 onChange 不要）
            .onChange(of: vm.isModified) { _, newValue in onModifiedChanged?(newValue) }
        }
        // .sheet で提示されるため、AppのdynamicTypeSize環境値が引き継がれないことがある
        // AppSettings から直接フォントスケールを適用して確実に連動させる
        if settings.fontScale.followsSystem {
            navContent
        } else {
            navContent.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
        }
    }

    // MARK: - セクション分割ヘルパー

    /// 設定の順序と非表示設定に従った表示フィールド一覧
    private var orderedRecordFields: [GraphKind] {
        let hidden = Set(settings.hiddenFields)
        return settings.graphPanelOrder
            .compactMap { GraphKind(rawValue: $0) }
            .filter { $0.isRecordField && !hidden.contains($0.rawValue) }
    }

    @ViewBuilder
    private func fieldRow(for kind: GraphKind) -> some View {
        switch kind {
        case .bp:
            dialRow(title: "metric.systolic.long", value: $vm.nBpHi_mmHg, enabled: $vm.bpHiEnabled, spec: MeasureRange.bpHi, unit: "unit.mmHg", stepperStep: 1, color: .red, locked: vm.valuesLocked)
            dialRow(title: "metric.diastolic.long", value: $vm.nBpLo_mmHg, enabled: $vm.bpLoEnabled, spec: MeasureRange.bpLo, unit: "unit.mmHg", stepperStep: 1, color: .blue, locked: vm.valuesLocked)
        case .pulse:
            dialRow(title: "metric.heartRate", value: $vm.nPulse_bpm, enabled: $vm.pulseEnabled, spec: MeasureRange.pulse, unit: "unit.bpm", stepperStep: 1, color: .orange, locked: vm.valuesLocked)
        case .weight:
            dialRow(title: "metric.weight", value: $vm.nWeight_10Kg, enabled: $vm.weightEnabled, spec: MeasureRange.weight, unit: "unit.kg", stepperStep: 1, decimals: 1, color: .indigo, locked: vm.valuesLocked)
        case .temp:
            dialRow(title: "metric.bodyTemp", value: $vm.nTemp_10c, enabled: $vm.tempEnabled, spec: MeasureRange.temp, unit: "unit.celsius", stepperStep: 1, decimals: 1, color: .pink, locked: vm.valuesLocked)
        case .bodyFat:
            dialRow(title: "metric.bodyFat", value: $vm.nBodyFat_10p, enabled: $vm.bodyFatEnabled, spec: MeasureRange.bodyFat, unit: "%", stepperStep: 1, decimals: 1, color: .purple, locked: vm.valuesLocked)
        case .skMuscle:
            dialRow(title: "metric.skeletalMuscle", value: $vm.nSkMuscle_10p, enabled: $vm.skMuscleEnabled, spec: MeasureRange.skMuscle, unit: "%", stepperStep: 1, decimals: 1, color: .teal, locked: vm.valuesLocked)
        case .bpAvg, .bmi, .weightChange:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        if case .goalEdit = vm.mode { } else {
            if case .edit = vm.mode, settings.hkEnabled {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: vm.dataSource.icon)
                            .foregroundStyle(vm.dataSource.color)
                        Text(LocalizedStringKey(vm.dataSource.label))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                dateRow
                    .disabled(vm.isHealthRecord)
                dateOptRow
            }
        }
    }

    // MARK: - HealthKit 取得ボタン（常に自動連携のため非表示）

    @ViewBuilder
    private var hkImportSection: some View {
        EmptyView()
    }

    private func bulkImportFromHealthKit() {
        vm.isLoadingFromHK = true
        Task {
            defer { vm.isLoadingFromHK = false }
            let cal = Calendar.current
            let now = Date()
            let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)

            let appSettings = AppSettings.shared
            let hkValues = await HealthKitService.shared.readSamples(
                from: oneYearAgo, to: now,
                hiddenFields: Set(appSettings.hiddenFields)
            )

            // 既存レコードの時刻セット（過去1年、分単位）
            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate { $0.dateTime >= oneYearAgo && $0.dateTime < now }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            func roundToMinute(_ d: Date) -> Date {
                let secs = d.timeIntervalSinceReferenceDate
                return Date(timeIntervalSinceReferenceDate: (secs / 60).rounded(.down) * 60)
            }
            let existingTimes = Set(existing.map { roundToMinute($0.dateTime) })
            var addedCount = 0
            for v in hkValues {
                guard !existingTimes.contains(roundToMinute(v.date)) else { continue }
                let record = BodyRecord(dateTime: v.date, dateOpt: appSettings.autoDateOpt(for: v.date))
                record.nBpHi_mmHg   = v.bpHi
                record.nBpLo_mmHg   = v.bpLo
                record.nPulse_bpm   = v.pulse
                record.nTemp_10c    = v.temp
                record.nWeight_10Kg = v.weight
                record.nBodyFat_10p = v.bodyFat
                context.insert(record)
                addedCount += 1
            }
            try? context.save()
            let count = addedCount
            dismiss()
            onHKImported?(count)
        }
    }

    // MARK: - HealthKit セクション（常に自動連携のため非表示）

    @ViewBuilder
    private var healthKitSection: some View {
        EmptyView()
    }

    // MARK: - 日時行

    private var dateRow: some View {
        Button {
            showDatePicker = true
        } label: {
            HStack {
                Text("record.datetime")
                    .foregroundStyle(.primary)
                Spacer()
                Text(Self.dateTimeFormatter.string(from: vm.dateTime))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateOptRow: some View {
        ViewThatFits(in: .horizontal) {
            // 1行：ラベル＋ピッカー
            HStack {
                Text("record.category")
                Spacer()
                dateOptPicker
            }
            // 2行：ラベル行 ＋ ピッカー右寄せ行
            VStack(alignment: .leading, spacing: 0) {
                Text("record.category")
                dateOptPicker
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var dateOptPicker: some View {
        // 区分はメニューではなく共通のドロップダウンPickerで選ぶ
        AZDropdownPicker(
            options: DateOpt.allCases,
            selection: $vm.dateOpt,
            isExpanded: $isDateOptExpanded,
            minWidth: 150
        ) { opt in
            HStack(spacing: 6) {
                Image(systemName: opt.icon)
                Text(LocalizedStringKey(opt.label))
            }
        }
    }

    // MARK: - ダイアル行

    @ViewBuilder
    private func dialRow(
        title: LocalizedStringKey,
        value: Binding<Int>,
        enabled: Binding<Bool>,
        spec: MeasureSpec,
        unit: LocalizedStringKey,
        stepperStep: Int,
        decimals: Int = 0,
        color: Color = .primary,
        locked: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                // 1行：見出し＋値＋単位＋スイッチ
                HStack {
                    Text(title).font(.callout)
                    Spacer()
                    rowControls(value: value, enabled: enabled, spec: spec,
                                unit: unit, decimals: decimals, color: color, locked: locked)
                }
                // 2行：見出し（左寄せ） ／ 値＋単位＋スイッチ（右寄せ）
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout)
                    rowControls(value: value, enabled: enabled, spec: spec,
                                unit: unit, decimals: decimals, color: color, locked: locked)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if enabled.wrappedValue {
                AZDialView(
                    value: value,
                    min: spec.min,
                    max: spec.max,
                    step: 1,
                    stepperStep: stepperStep,
                    decimals: decimals,
                    style: DialStyle.builtin(id: AppSettings.shared.dialStyle) ?? .shape,
                    tuning: AppSettings.shared.dialTuning
                )
                .disabled(locked)
            }
        }
        .disabled(locked)
        .padding(.vertical, 4)
    }

    /// 値・単位・トグルをまとめた横並びコントロール
    private func rowControls(
        value: Binding<Int>,
        enabled: Binding<Bool>,
        spec: MeasureSpec,
        unit: LocalizedStringKey,
        decimals: Int,
        color: Color,
        locked: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if enabled.wrappedValue {
                // 数値と単位を同じボタン内に入れてタップ領域を拡大
                NumpadValueText(value: value, min: spec.min, max: spec.max,
                                decimals: decimals, color: color, unit: unit)
            } else {
                Text("placeholder.none")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
            Toggle("", isOn: enabled)
                .labelsHidden()
        }
    }

    // MARK: - メモ行スクロール

    private var isMemoFocused: Bool {
        focusNote1 || focusNote2 || focusEquipment
    }

    private func scrollFocusedMemoIntoView(_ proxy: ScrollViewProxy) {
        if focusNote1 {
            scrollMemoIntoView(note1AnchorID, proxy: proxy)
        } else if focusNote2 {
            scrollMemoIntoView(note2AnchorID, proxy: proxy)
        } else if focusEquipment {
            scrollMemoIntoView(equipmentAnchorID, proxy: proxy)
        }
    }

    private func scrollMemoIntoView(_ anchorID: String, proxy: ScrollViewProxy) {
        // キーボード表示中もメモ欄の入力行が隠れないよう、少し遅らせて下端へ寄せる
        for delay in [0.05, 0.22] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard isMemoFocused else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(anchorID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 保存

    private func saveAndDismiss() {
        // 新規追加で「記録をまとめる」時間内に衝突があればシート表示
        if let conflict = vm.findRecentConflict(context: context) {
            conflictData = conflict
            return
        }
        do {
            try vm.save(context: context)
            dismiss()
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func handleConflictAction(_ action: ConflictAction, previous: BodyRecord) {
        do {
            try vm.resolveConflict(action, previous: previous, context: context)
            // RecordEditView を閉じれば上の衝突シートも SwiftUI が自動で閉じる
            // 手動で conflictData = nil と dismiss() を併用すると二重 dismiss となり、
            // 親シートの isPresented バインディングが false に戻らず再表示できなくなる
            dismiss()
        } catch {
            vm.errorMessage = error.localizedDescription
            // エラー時のみ衝突シートを閉じてエラーメッセージを見せる
            conflictData = nil
        }
    }
}

// MARK: - 日付ピッカーシート

struct DatePickerSheet: View {
    @Binding var date: Date
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 500

    var body: some View {
        NavigationStack {
            DatePicker(
                "",
                selection: $date,
                in: ...BodyRecord.maxInputDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                // ナビゲーションバー高さ（inline: 約44）＋セーフエリアを加算
                let safeArea = (UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }
                    .first?.safeAreaInsets.bottom ?? 0)
                contentHeight = h + 44 + safeArea
            }
            .navigationTitle("record.datetime.select")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") {
                        onChanged()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }
}
