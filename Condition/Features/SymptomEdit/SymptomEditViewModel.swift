// SymptomEditViewModel.swift
// 症状メモの入力状態。SwiftData のモデルとは切り離して持ち、保存時にだけ書き戻す

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class SymptomEditViewModel {

    enum Mode {
        case addNew
        case edit(SymptomRecord)
    }

    let mode: Mode

    // MARK: - 入力値
    var startAt: Date                { didSet { markModified() } }
    var endAt: Date                  { didSet { markModified() } }
    var hasEndAt: Bool               { didSet { markModified() } }
    var isOngoing: Bool              { didSet { markModified() } }
    var symptomID: String            { didSet { markModified() } }
    var severity: SymptomSeverity    { didSet { markModified() } }
    var note: String                 { didSet { markModified() } }
    var medicineIDs: [String]        { didSet { markModified() } }

    // MARK: - 環境（天候・室内・端末気圧）
    /// 中身の編集は測定記録と共用の環境シートが行う。ここは値を持って保存するだけ
    var environment: EnvironmentSnapshot { didSet { markModified() } }

    private(set) var isModified = false
    /// 読み込み中は isModified を立てない
    private var isLoading = true

    // MARK: - 初期化

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .addNew:
            let now = Date()
            startAt = now
            endAt = now
            hasEndAt = false
            isOngoing = false
            symptomID = ""
            severity = .defaultForNewRecord
            note = ""
            medicineIDs = []
            environment = EnvironmentSnapshot()
        case .edit(let record):
            startAt = record.startAt
            endAt = record.endAt ?? record.startAt
            hasEndAt = record.endAt != nil
            isOngoing = record.bOngoing
            symptomID = record.sSymptomID
            severity = record.severity
            note = record.sNote
            medicineIDs = record.medicineIDs
            environment = record.environmentSnapshot
        }
        isLoading = false
    }

    private func markModified() {
        guard !isLoading else { return }
        isModified = true
    }

    // MARK: - 妥当性

    /// 保存できるか。症状が選ばれていないレコードは作れない
    var canSave: Bool {
        !symptomID.isEmpty && !hasInvalidRange
    }

    /// 終了が開始より前になっていないか
    var hasInvalidRange: Bool {
        hasEndAt && !isOngoing && endAt < startAt
    }

    /// 継続中にすると終了時刻は持てない（同時に成立しない状態を作らせない）
    func setOngoing(_ value: Bool) {
        isOngoing = value
        if value { hasEndAt = false }
    }

    func setHasEndAt(_ value: Bool) {
        hasEndAt = value
        if value {
            isOngoing = false
            if endAt < startAt { endAt = startAt }
        }
    }

    /// 辞書シートから選ばれた薬を足す。
    /// シートは「追加する」ための画面なので、既に選ばれていても外さない
    func addMedicine(_ id: String) {
        guard !medicineIDs.contains(id),
              medicineIDs.count < SymptomLimits.maxMedicinesPerRecord else { return }
        medicineIDs.append(id)
    }

    func toggleMedicine(_ id: String) {
        if let index = medicineIDs.firstIndex(of: id) {
            medicineIDs.remove(at: index)
        } else if medicineIDs.count < SymptomLimits.maxMedicinesPerRecord {
            medicineIDs.append(id)
        }
    }

    // MARK: - 保存

    /// 入力値をモデルへ書き戻す。新規なら挿入して返す
    @discardableResult
    func save(in context: ModelContext) -> SymptomRecord? {
        guard canSave else { return nil }

        let record: SymptomRecord
        switch mode {
        case .addNew:
            record = SymptomRecord(startAt: startAt, symptomID: symptomID)
            record.dataSource = .appInput
            context.insert(record)
        case .edit(let existing):
            record = existing
            // 入力後に変更された記録であることを残す
            if record.dataSource == .appInput { record.dataSource = .appModified }
        }

        record.startAt = startAt
        record.bOngoing = isOngoing
        record.endAt = (hasEndAt && !isOngoing) ? endAt : nil
        record.sSymptomID = symptomID
        record.severity = severity
        record.sNote = String(note.trimmingCharacters(in: .newlines).prefix(SymptomLimits.noteMaxLength))
        record.medicineIDs = medicineIDs

        record.apply(environment)

        do {
            try context.save()
        } catch {
            context.rollback()
            AppAnalytics.shared.record(error: error, name: "symptom_save_failed")
            return nil
        }

        // 使ったタグを MRU の先頭へ寄せる
        AppSettings.shared.markSymptomUsed(symptomID)
        AppSettings.shared.markMedicinesUsed(medicineIDs)
        isModified = false
        return record
    }

}
