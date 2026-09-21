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

    // MARK: - 天候（フェーズ1は手動入力のみ）
    var weatherSource: SymptomWeatherSource { didSet { markModified() } }
    var tempText: String             { didSet { markModified() } }
    var humidityText: String         { didSet { markModified() } }
    var pressureText: String         { didSet { markModified() } }
    var weatherPlace: String         { didSet { markModified() } }

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
            weatherSource = .none
            tempText = ""
            humidityText = ""
            pressureText = ""
            weatherPlace = ""
        case .edit(let record):
            startAt = record.startAt
            endAt = record.endAt ?? record.startAt
            hasEndAt = record.endAt != nil
            isOngoing = record.bOngoing
            symptomID = record.sSymptomID
            severity = record.severity
            note = record.sNote
            medicineIDs = record.medicineIDs
            weatherSource = record.weatherSource
            tempText = Self.decimalText(record.nTemp_10c, scale: 1, isSet: record.hasWeather)
            humidityText = record.nHumidity_p > 0 ? "\(record.nHumidity_p)" : ""
            pressureText = Self.decimalText(record.nPressure_10hpa, scale: 1, isSet: record.nPressure_10hpa > 0)
            weatherPlace = record.sWeatherPlace
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

        applyWeather(to: record)

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

    private func applyWeather(to record: SymptomRecord) {
        // フェーズ1は手動入力のみ。自動取得（WeatherKit）はフェーズ4で足す。
        // 自動取得済みの値を編集画面で触っていない場合は、取得値をそのまま残す
        guard weatherSource != .auto else { return }

        let temp = Self.scaledInt(tempText, scale: 1)
        let humidity = Int(humidityText.trimmingCharacters(in: .whitespaces))
        let pressure = Self.scaledInt(pressureText, scale: 1)
        let place = weatherPlace.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAny = temp != nil || humidity != nil || pressure != nil || !place.isEmpty

        guard hasAny else {
            record.nTemp_10c = 0
            record.nHumidity_p = 0
            record.nPressure_10hpa = 0
            record.nPressureDelta24h_10hpa = 0
            record.sWeatherSymbol = ""
            record.sWeatherPlace = ""
            record.weatherSource = .none
            return
        }

        record.nTemp_10c = Self.clamped(temp, SymptomLimits.tempRange_10c)
        record.nHumidity_p = Self.clamped(humidity, SymptomLimits.humidityRange_p)
        record.nPressure_10hpa = Self.clamped(pressure, SymptomLimits.pressureRange_10hpa)
        record.sWeatherPlace = String(place.prefix(60))
        record.weatherSource = .manual
    }

    // MARK: - 数値の入出力

    private static func decimalText(_ value: Int, scale: Int, isSet: Bool) -> String {
        guard isSet, value != 0 else { return "" }
        return String(format: "%.\(scale)f", Double(value) / pow(10, Double(scale)))
    }

    /// "20.1" → 201（scale=1）。空欄と不正値は nil
    private static func scaledInt(_ text: String, scale: Int) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return nil }
        return Int((value * pow(10, Double(scale))).rounded())
    }

    private static func clamped(_ value: Int?, _ range: (min: Int, max: Int)) -> Int {
        guard let value else { return 0 }
        return min(max(value, range.min), range.max)
    }
}
