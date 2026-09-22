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
    @State private var showDiscardAlert = false
    @State private var showEnvironmentSheet = false
    /// 保存後に「続けて記録」で2件目を作るかの確認
    @State private var showContinueSheet = false
    @FocusState private var noteFocused: Bool

    private var settings: AppSettings { AppSettings.shared }

    /// 記録画面のタグ行に出す件数
    private static let visibleTagCount = 8

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
                severitySection
                medicineSection
                noteSection
                weatherSection
            }
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
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize()
                    // アイコンと文字が別々に読み上げられないよう1つにまとめる
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("symptom.edit.title"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel") {
                        if vm.isModified { showDiscardAlert = true } else { dismiss() }
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
                    vm.addMedicine(id)
                }
            }
            .sheet(isPresented: $showEnvironmentSheet) {
                EnvironmentEditView(
                    snapshot: vm.environment,
                    recordDate: vm.startAt
                ) { updated in
                    vm.environment = updated
                }
            }
            .alert("record.discardChanges.title", isPresented: $showDiscardAlert) {
                Button("action.discard", role: .destructive) { dismiss() }
                Button("action.cancel", role: .cancel) {}
            }
            .onChange(of: vm.isModified) { _, newValue in onModifiedChanged?(newValue) }
        }
    }

    // MARK: - 日時

    private var dateSection: some View {
        Section {
            DatePicker(
                "symptom.startAt",
                selection: Binding(get: { vm.startAt }, set: { vm.startAt = $0 }),
                in: ...Date.distantFuture,
                displayedComponents: [.date, .hourAndMinute]
            )

            Toggle("symptom.ongoing", isOn: Binding(
                get: { vm.isOngoing },
                set: { vm.setOngoing($0) }
            ))

            if !vm.isOngoing {
                Toggle("symptom.hasEndAt", isOn: Binding(
                    get: { vm.hasEndAt },
                    set: { vm.setHasEndAt($0) }
                ))
                if vm.hasEndAt {
                    DatePicker(
                        "symptom.endAt",
                        selection: Binding(get: { vm.endAt }, set: { vm.endAt = $0 }),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    if vm.hasInvalidRange {
                        Label("symptom.error.endBeforeStart", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("symptom.section.when")
        } footer: {
            // 終了を必須にすると発症直後に記録できなくなるので、あとから入れられることを伝える
            Text("symptom.section.when.footer")
        }
    }

    // MARK: - 症状

    private var symptomSection: some View {
        Section {
            SymptomTagRow(
                tags: symptomTags,
                kind: .symptom,
                selectedIDs: vm.symptomID.isEmpty ? [] : [vm.symptomID],
                onTap: { id in
                    // 1レコード1症状。選び直しはできるが複数は持てない
                    vm.symptomID = (vm.symptomID == id) ? "" : id
                },
                onAdd: { showSymptomPicker = true }
            )
            .padding(.vertical, 2)
        } header: {
            Text("symptom.section.symptom")
        }
    }

    /// MRU 上位。編集中の症状がリスト外にあるときは先頭に足して必ず見えるようにする
    private var symptomTags: [SymptomTag] {
        var tags = settings.symptomTags.frequentlyUsed(limit: Self.visibleTagCount)
        if !vm.symptomID.isEmpty, !tags.contains(where: { $0.id == vm.symptomID }) {
            let selected = settings.symptomTags.tag(for: vm.symptomID) ?? SymptomTag(id: vm.symptomID)
            tags.insert(selected, at: 0)
        }
        return tags
    }

    // MARK: - 程度

    private var severitySection: some View {
        Section {
            Picker("symptom.severity", selection: Binding(
                get: { vm.severity },
                set: { vm.severity = $0 }
            )) {
                ForEach(SymptomSeverity.selectableCases) { level in
                    Text(LocalizedStringKey(level.labelKey)).tag(level)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("symptom.section.severity")
        }
    }

    // MARK: - 薬

    private var medicineSection: some View {
        Section {
            SymptomTagRow(
                tags: medicineTags,
                kind: .medicine,
                selectedIDs: Set(vm.medicineIDs),
                onTap: { vm.toggleMedicine($0) },
                onAdd: { showMedicinePicker = true }
            )
            .padding(.vertical, 2)
        } header: {
            Text("symptom.section.medicine")
        }
    }

    private var medicineTags: [SymptomTag] {
        var tags = settings.medicineTags.frequentlyUsed(limit: Self.visibleTagCount)
        for id in vm.medicineIDs where !tags.contains(where: { $0.id == id }) {
            tags.insert(settings.medicineTags.tag(for: id) ?? SymptomTag(id: id), at: 0)
        }
        return tags
    }

    // MARK: - メモ

    private var noteSection: some View {
        Section {
            AZMemoEditor(
                placeholder: "symptom.note.placeholder",
                text: Binding(get: { vm.note }, set: { vm.note = $0 }),
                isFocused: $noteFocused
            )
        } header: {
            Text("symptom.section.note")
        }
    }

    // MARK: - 環境（天候・室内・端末気圧）

    /// 中身は測定記録と共用の環境シートに置く。
    /// 記録画面には現在の要約と、開くためのボタンだけを出す
    private var weatherSection: some View {
        Section {
            Button {
                showEnvironmentSheet = true
            } label: {
                HStack {
                    Label("environment.title", systemImage: "cloud.sun.fill")
                    Spacer()
                    Text(environmentSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
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
