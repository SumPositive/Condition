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
    @State private var showWeatherFields = false
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
            .navigationTitle("symptom.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    vm.toggleMedicine(id)
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

    // MARK: - 天候（フェーズ1は手動入力のみ）

    private var weatherSection: some View {
        Section {
            if showWeatherFields || vm.weatherSource.isPresent {
                LabeledContent("symptom.weather.temp") {
                    TextField("", text: Binding(get: { vm.tempText }, set: { vm.tempText = $0 }))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("symptom.weather.humidity") {
                    TextField("", text: Binding(get: { vm.humidityText }, set: { vm.humidityText = $0 }))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("symptom.weather.pressure") {
                    TextField("", text: Binding(get: { vm.pressureText }, set: { vm.pressureText = $0 }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("symptom.weather.place") {
                    TextField("", text: Binding(get: { vm.weatherPlace }, set: { vm.weatherPlace = $0 }))
                        .multilineTextAlignment(.trailing)
                }
            } else {
                Button("symptom.weather.enterManually") {
                    showWeatherFields = true
                }
            }
        } header: {
            Text("symptom.section.weather")
        } footer: {
            // 自動取得はフェーズ4。ここで期待させないよう手動入力だけであることを明示する
            Text("symptom.section.weather.footer")
        }
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
