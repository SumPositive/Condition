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
    /// 継続中・終息日時あり・終息日時不明の3状態
    var progressState: SymptomProgressState { didSet { markModified() } }
    var symptomID: String            { didSet { markModified() } }
    var severity: SymptomSeverity    { didSet { markModified() } }
    var note: String                 { didSet { markModified() } }
    var medicineIDs: [String]        { didSet { markModified() } }
    /// 発症する直前の状況。対処と同じく複数選べる
    var triggerIDs: [String]         { didSet { markModified() } }

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
            progressState = .ongoing
            symptomID = ""
            severity = .defaultForNewRecord
            note = ""
            medicineIDs = []
            triggerIDs = []
            environment = EnvironmentSnapshot()
        case .edit(let record):
            startAt = record.startAt
            endAt = record.endAt ?? record.startAt
            progressState = record.progressState
            symptomID = record.sSymptomID
            severity = record.severity
            note = record.sNote
            medicineIDs = record.medicineIDs
            triggerIDs = record.triggerIDs
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

    /// 終息スイッチの表示状態
    var hasEnded: Bool {
        progressState != .ongoing
    }

    /// 終了が開始より前になっていないか
    var hasInvalidRange: Bool {
        progressState == .completedKnown && endAt < startAt
    }

    /// 終息をONにしたときは日時あり、OFFにしたときは継続中へ切り替える
    func setHasEnded(_ value: Bool) {
        if value, progressState == .ongoing {
            // 継続中から終息へ変えた時点を初期の終息日時にする
            endAt = max(startAt, Date())
        }
        progressState = value ? .completedKnown : .ongoing
        if value, endAt < startAt {
            endAt = startAt
        }
    }

    /// カレンダーで選んだ日時を終息日時として確定する
    func setEndDateKnown() {
        progressState = .completedKnown
        if endAt < startAt { endAt = startAt }
    }

    /// 終息済みだが日時は分からない状態へ切り替える
    func setEndDateUnknown() {
        progressState = .completedUnknown
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

    func toggleTrigger(_ id: String) {
        if id == TriggerCatalog.nothingComesToMindID {
            // 「思い当たらない」は他の状況と同時に選ばない
            triggerIDs = triggerIDs == [id] ? [] : [id]
            return
        }

        // 通常の状況を選んだら「思い当たらない」を外す
        triggerIDs.removeAll { $0 == TriggerCatalog.nothingComesToMindID }
        if let index = triggerIDs.firstIndex(of: id) {
            triggerIDs.remove(at: index)
        } else if triggerIDs.count < SymptomLimits.maxTriggersPerRecord {
            triggerIDs.append(id)
        }
    }

    /// 同時に出た別の症状を続けて記録するための入力状態を作る
    /// 発症日時・環境・直前の状況だけを引き継ぎ、症状固有の入力は初期化する
    func makeContinuation() -> SymptomEditViewModel {
        let next = SymptomEditViewModel(mode: .addNew)
        next.isLoading = true
        next.startAt = startAt
        next.endAt = startAt
        next.progressState = .ongoing
        next.symptomID = ""
        next.severity = .defaultForNewRecord
        next.note = ""
        next.medicineIDs = []
        next.triggerIDs = triggerIDs
        next.environment = environment
        next.isLoading = false
        next.isModified = false
        return next
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
        switch progressState {
        case .ongoing:
            record.bOngoing = true
            record.endAt = nil
        case .completedKnown:
            record.bOngoing = false
            record.endAt = endAt
        case .completedUnknown:
            record.bOngoing = false
            record.endAt = nil
        }
        record.sSymptomID = symptomID
        record.severity = severity
        record.sNote = String(note.trimmingCharacters(in: .newlines).prefix(SymptomLimits.noteMaxLength))
        record.medicineIDs = medicineIDs
        record.triggerIDs = TriggerCatalog.normalizedSelection(triggerIDs)

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
        AppSettings.shared.markTriggersUsed(triggerIDs)
        isModified = false
        return record
    }

}
