// RecordsJSONIO.swift
// 記録一覧の JSON エクスポート／インポート処理
//
// SettingsView から抽出した純粋ロジック。SwiftData の ModelContext を引数で受け取り、
// UI 状態には依存しない。テストはこの型を直接呼び出す。

import Foundation
import SwiftData

// MARK: - エクスポート整形

enum RecordJSONExportStyle: Int, CaseIterable, Identifiable {
    case compact = 0
    case pretty = 1

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .compact: return "settings.exportFormat.compact"
        case .pretty:  return "settings.exportFormat.pretty"
        }
    }

    var jsonOptions: JSONSerialization.WritingOptions {
        switch self {
        case .compact:
            return [.sortedKeys]
        case .pretty:
            return [.prettyPrinted, .sortedKeys]
        }
    }
}

// MARK: - インポート JSON 形

struct RecordImportEnvelope: Decodable {
    let schemaVersion: Int?
    let categoryAppearances: [DateOptAppearance]?
    let records: [RecordImportRecord]
    /// 症状メモ（schemaVersion 2 以降）。旧バックアップには無いので任意
    let symptoms: [SymptomImportRecord]?
    /// 症状・薬のタグリスト（表示名と並び順の復元用）
    let symptomTags: SymptomTagList?
    let medicineTags: SymptomTagList?
}

struct SymptomImportRecord: Decodable {
    let startAt: String
    let endAt: String?
    let ongoing: Bool?
    let symptom: String?        // 表示名（人が読むため。復元は symptomId を優先）
    let symptomId: String?
    let severity: Int?
    let note: String?
    let medicines: [String]?    // 表示名
    let medicineIds: [String]?
    let dataSourceRaw: Int?
    let weather: SymptomWeatherImport?

    /// ISO8601DateFormatter は Sendable ではないので static では持たず、
    /// RecordImportRecord.parsedDate と同じくその場で作る
    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                           .withColonSeparatorInTime, .withTimeZone]
        return f
    }

    var parsedStartAt: Date? { Self.makeISOFormatter().date(from: startAt) }
    var parsedEndAt: Date? { endAt.flatMap { Self.makeISOFormatter().date(from: $0) } }

    /// 症状ID。旧い書き出しや他アプリ由来で ID が無い場合は表示名から辞書を引く
    var resolvedSymptomID: String? {
        if let symptomId, !symptomId.isEmpty { return symptomId }
        guard let symptom, !symptom.isEmpty else { return nil }
        return SymptomCatalog.all.first { $0.localizedName == symptom }?.id
    }

    var parsedSeverity: SymptomSeverity {
        SymptomSeverity(rawValue: severity ?? 0) ?? .unspecified
    }
}

struct SymptomWeatherImport: Decodable {
    let source: String?         // "jma" / "weatherKit" / "manual"（旧: "auto"）
    let temp: Double?
    let humidity: Int?
    let pressure: Double?
    let pressureDelta24h: Double?
    let devicePressure: Double?
    let symbol: String?
    let place: String?
    let stationId: String?
    let pressureStationId: String?
    let pressureStationDistanceKm: Double?
    let indoorTemp: Double?
    let indoorHumidity: Int?
    let sourceUrl: String?
    /// 観測値の時刻（ISO8601）。旧バックアップには無い
    let observedAt: String?
    // 0℃・0%・変化量0と欠測を区別するフラグ（旧バックアップには無い）
    let tempSet: Bool?
    let humiditySet: Bool?
    let pressureDelta24hSet: Bool?
    let tempEdited: Bool?
    let humidityEdited: Bool?
    let pressureEdited: Bool?

    /// 観測時刻。ISO8601DateFormatter は Sendable ではないのでその場で作る
    var parsedObservedAt: Date? {
        guard let observedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                           .withColonSeparatorInTime, .withTimeZone]
        return f.date(from: observedAt)
    }

    var parsedSource: SymptomWeatherSource {
        switch source?.lowercased() {
        case "jma":                 return .jma
        case "weatherkit", "auto":  return .weatherKit   // "auto" は旧バックアップ
        case "manual":              return .manual
        default:                    return .none
        }
    }
}

struct RecordImportRecord: Decodable {
    let dateTime: String
    let condition: String?
    let conditionRaw: Int?
    let dataSourceRaw: Int?
    let cautionFlag: Bool?
    let memo1: String?
    let memo2: String?
    let device: String?
    let bpSystolic: Int?
    let bpDiastolic: Int?
    let bpSide: String?          // "right" / "left"（不明は出力しない）
    let heartRate: Int?
    let bodyTemp: Double?
    let weight: Double?
    let bodyFat: Double?
    let skeletalMuscle: Double?
    let measurementSamples: MeasurementSampleSet?

    var parsedDate: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return iso.date(from: dateTime)
    }

    var dateOpt: DateOpt? {
        if let conditionRaw {
            return DateOpt(rawValue: conditionRaw)
        }
        guard let condition, !condition.isEmpty else { return nil }
        if let exact = DateOpt.allCases.first(where: { $0.label == condition }) {
            return exact
        }
        if let custom = DateOpt.allCases.first(where: { $0.displayName == condition }) {
            return custom
        }
        if let legacy = legacyDateOpt(for: condition) {
            return legacy
        }
        return DateOpt.allCases.first {
            NSLocalizedString($0.label, comment: "") == condition
        }
    }

    var dataSource: RecordDataSource? {
        guard let dataSourceRaw else { return nil }
        return RecordDataSource(rawValue: dataSourceRaw)
    }

    /// 血圧の測定箇所（左右）。未指定・不正値は不明。
    var parsedBpSide: BpSide {
        switch bpSide?.lowercased() {
        case "right": return .right
        case "left":  return .left
        default:      return .unknown
        }
    }

    private func legacyDateOpt(for condition: String) -> DateOpt? {
        let legacyPairs: [(String, DateOpt)] = [
            ("category.wake",         .cat01),
            ("category.rest",         .cat02),
            ("category.beforeBed",    .cat03),
            ("category.bedtime",      .cat04),
            ("category.preExercise",  .cat05),
            ("category.postExercise", .cat06),
        ]
        return legacyPairs.first { $0.0 == condition }?.1
    }
}

// MARK: - サービス本体

enum RecordsJSONIO {

    /// 2: 症状メモ（symptoms / symptomTags / medicineTags）を追加
    static let currentSchemaVersion = 2

    enum IOError: LocalizedError, Equatable {
        case unsupportedSchemaVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let version):
                return "未対応のJSON形式です（schemaVersion: \(version)）"
            }
        }
    }

    struct ImportResult: Equatable {
        let inserted: Int
        let updated: Int
        let skipped: Int
        /// 直前のインポートで適用された区分表示マスタ（バックアップが含んでいた場合のみ）
        let categoryAppearances: [DateOptAppearance]?
        var symptomsInserted: Int = 0
        var symptomsUpdated: Int = 0
        var symptomsSkipped: Int = 0
        /// バックアップが含んでいたタグリスト（呼び出し側が AppSettings へ反映する）
        var symptomTags: SymptomTagList? = nil
        var medicineTags: SymptomTagList? = nil
    }

    // MARK: エクスポート

    /// 記録の配列を JSON データへシリアライズ。区分表示マスタも同梱する。
    /// - Parameters:
    ///   - records: 出力対象の `BodyRecord` 配列（目標値レコードは事前に除外しておくこと）
    ///   - style: 整形スタイル
    ///   - categoryAppearances: 含める区分表示マスタ（nil の場合は省略）
    ///   - exportDate: メタデータ用の出力時刻（テスト容易性のため引数化、本番は `Date()`）
    static func export(
        records: [BodyRecord],
        symptoms: [SymptomRecord] = [],
        style: RecordJSONExportStyle = .compact,
        categoryAppearances: [DateOptAppearance]? = nil,
        symptomTags: SymptomTagList? = nil,
        medicineTags: SymptomTagList? = nil,
        exportDate: Date = Date()
    ) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]

        var recordObjects: [[String: Any]] = []
        for record in records {
            // 目標値や入力上限を超える特殊レコードはバックアップ対象外にする
            guard record.dateTime <= bodyRecordMaxDate else { continue }
            var object: [String: Any] = [
                "dateTime":      iso.string(from: record.dateTime),
                "condition":     record.dateOpt.displayName,
                "conditionRaw":  record.nDateOpt,
                "dataSourceRaw": record.nDataSource,
                "cautionFlag":   record.bCaution,
                "memo1":         record.sNote1,
                "memo2":         record.sNote2,
                "device":        record.sEquipment,
            ]
            if 0 < record.nBpHi_mmHg    { object["bpSystolic"]      = record.nBpHi_mmHg }
            if 0 < record.nBpLo_mmHg    { object["bpDiastolic"]     = record.nBpLo_mmHg }
            if record.bpSide.isDefined  { object["bpSide"]          = record.bpSide == .left ? "left" : "right" }
            if 0 < record.nPulse_bpm    { object["heartRate"]       = record.nPulse_bpm }
            if 0 < record.nTemp_10c     { object["bodyTemp"]        = decimalNumber(record.nTemp_10c,     scale: 1) }
            if 0 < record.nWeight_10Kg  { object["weight"]          = decimalNumber(record.nWeight_10Kg,  scale: 1) }
            if 0 < record.nBodyFat_10p  { object["bodyFat"]         = decimalNumber(record.nBodyFat_10p,  scale: 1) }
            if 0 < record.nSkMuscle_10p { object["skeletalMuscle"]  = decimalNumber(record.nSkMuscle_10p, scale: 1) }
            // 平均値を再編集できるよう元の測定値もバックアップする
            if let sampleSet = record.measurementSampleSet,
               let sampleObject = jsonObject(sampleSet) {
                object["measurementSamples"] = sampleObject
            }
            recordObjects.append(object)
        }

        var envelope: [String: Any] = [
            "schemaVersion": currentSchemaVersion,
            "exportDate": iso.string(from: exportDate),
            "records":    recordObjects,
        ]
        if let categoryAppearances {
            envelope["categoryAppearances"] = categoryAppearances.map(appearanceObject)
        }
        if !symptoms.isEmpty {
            envelope["symptoms"] = symptoms.map {
                symptomObject($0, iso: iso, symptomTags: symptomTags, medicineTags: medicineTags)
            }
        }
        // 表示名と並び順を復元できるようタグリストも同梱する
        if let symptomTags, let object = jsonObject(symptomTags) {
            envelope["symptomTags"] = object
        }
        if let medicineTags, let object = jsonObject(medicineTags) {
            envelope["medicineTags"] = object
        }

        return (try? JSONSerialization.data(withJSONObject: envelope, options: style.jsonOptions)) ?? Data()
    }

    /// 症状1件の JSON オブジェクト。既存の "condition"/"conditionRaw" と同じく、
    /// 人が読める表示名と復元用の ID を両方出す
    private static func symptomObject(
        _ record: SymptomRecord,
        iso: ISO8601DateFormatter,
        symptomTags: SymptomTagList?,
        medicineTags: SymptomTagList?
    ) -> [String: Any] {
        // 表示名はタグリストの上書き名を優先する。渡されなければ辞書のローカライズ名になる
        let displayName = (symptomTags?.tag(for: record.sSymptomID)
            ?? SymptomTag(id: record.sSymptomID)).symptomDisplayName

        var object: [String: Any] = [
            "startAt":   iso.string(from: record.startAt),
            "ongoing":   record.bOngoing,
            "symptom":   displayName,
            "symptomId": record.sSymptomID,
            "severity":  record.nSeverity,
            "dataSourceRaw": record.nDataSource,
        ]
        if let endAt = record.endAt { object["endAt"] = iso.string(from: endAt) }
        if !record.sNote.isEmpty { object["note"] = record.sNote }
        let medicineIDs = record.medicineIDs
        if !medicineIDs.isEmpty {
            object["medicineIds"] = medicineIDs
            object["medicines"] = medicineIDs.map { id in
                (medicineTags?.tag(for: id) ?? SymptomTag(id: id)).medicineDisplayName
            }
        }
        if record.hasWeather {
            var weather: [String: Any] = [
                "source": Self.weatherSourceName(record.weatherSource),
            ]
            // 0℃・0%も有効値なので、値ではなく入力有無フラグで出し分ける
            if record.bTempSet {
                weather["temp"] = decimalNumber(record.nTemp_10c, scale: 1)
                weather["tempSet"] = true
            }
            if record.bHumiditySet {
                weather["humidity"] = record.nHumidity_p
                weather["humiditySet"] = true
            }
            if 0 < record.nPressure_10hpa { weather["pressure"] = decimalNumber(record.nPressure_10hpa, scale: 1) }
            if record.bPressureDelta24hSet {
                weather["pressureDelta24h"] = decimalNumber(record.nPressureDelta24h_10hpa, scale: 1)
                weather["pressureDelta24hSet"] = true
            }
            if !record.sWeatherSourceURL.isEmpty { weather["sourceUrl"] = record.sWeatherSourceURL }
            if let observedAt = record.dWeatherObservedAt {
                weather["observedAt"] = iso.string(from: observedAt)
            }
            if record.nDevicePressure_10hpa != 0 {
                weather["devicePressure"] = decimalNumber(record.nDevicePressure_10hpa, scale: 1)
            }
            if !record.sWeatherSymbol.isEmpty { weather["symbol"] = record.sWeatherSymbol }
            if !record.sWeatherPlace.isEmpty { weather["place"] = record.sWeatherPlace }
            if !record.sWeatherStationID.isEmpty { weather["stationId"] = record.sWeatherStationID }
            if !record.sPressureStationID.isEmpty {
                weather["pressureStationId"] = record.sPressureStationID
                if record.nPressureStationDistance_10km > 0 {
                    weather["pressureStationDistanceKm"] =
                        decimalNumber(record.nPressureStationDistance_10km, scale: 1)
                }
            }
            // 室内値は外気と別項目。0℃・0%も有効なので入力フラグで出し分ける
            if record.bIndoorTempSet {
                weather["indoorTemp"] = decimalNumber(record.nIndoorTemp_10c, scale: 1)
            }
            if record.bIndoorHumiditySet {
                weather["indoorHumidity"] = record.nIndoorHumidity_p
            }
            if record.bTempEdited { weather["tempEdited"] = true }
            if record.bHumidityEdited { weather["humidityEdited"] = true }
            if record.bPressureEdited { weather["pressureEdited"] = true }
            object["weather"] = weather
        }
        return object
    }

    private static func weatherSourceName(_ source: SymptomWeatherSource) -> String {
        switch source {
        case .none:       return "none"
        case .weatherKit: return "weatherKit"
        case .manual:     return "manual"
        case .jma:        return "jma"
        }
    }

    // MARK: インポート

    /// JSON データを既存レコードへ統合する。同一日時（秒丸め）レコードは更新、無ければ挿入。
    /// 範囲外の測定値は仕様の min/max に clamp。0 以下や nil は「未入力」扱い。
    /// - Throws: JSON decode 失敗または `context.save()` 失敗
    @discardableResult
    static func importJSON(
        _ data: Data,
        into context: ModelContext,
        saveChanges: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ImportResult {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(RecordImportEnvelope.self, from: data)
        let schemaVersion = envelope.schemaVersion ?? 0
        guard 0 <= schemaVersion, schemaVersion <= currentSchemaVersion else {
            throw IOError.unsupportedSchemaVersion(schemaVersion)
        }
        var result = try merge(
            envelope.records,
            into: context,
            categoryAppearances: envelope.categoryAppearances,
            saveChanges: saveChanges
        )
        // 症状メモは schemaVersion 2 以降にしか無い。旧バックアップでは何もしない
        if let symptoms = envelope.symptoms, !symptoms.isEmpty {
            let symptomResult = try mergeSymptoms(symptoms, into: context, saveChanges: saveChanges)
            result.symptomsInserted = symptomResult.inserted
            result.symptomsUpdated = symptomResult.updated
            result.symptomsSkipped = symptomResult.skipped
        }
        result.symptomTags = envelope.symptomTags
        result.medicineTags = envelope.medicineTags
        return result
    }

    /// 症状メモを統合する。開始日時（秒丸め）と症状IDが一致するレコードを同一とみなす。
    /// 測定記録と違い、同じ時刻に別の症状を記録できる（1レコード1症状のため）
    @discardableResult
    static func mergeSymptoms(
        _ importedSymptoms: [SymptomImportRecord],
        into context: ModelContext,
        saveChanges: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> (inserted: Int, updated: Int, skipped: Int) {
        let existingRecords = try context.fetch(FetchDescriptor<SymptomRecord>())
        struct Key: Hashable {
            let date: Date
            let symptomID: String
        }
        var existingByKey: [Key: SymptomRecord] = [:]
        for record in existingRecords {
            existingByKey[Key(date: normalizedSecond(record.startAt), symptomID: record.sSymptomID)] = record
        }

        var inserted = 0
        var updated = 0
        var skipped = 0
        for imported in importedSymptoms {
            // 症状が特定できない、または日時が読めないものは取り込まない
            guard let startAt = imported.parsedStartAt,
                  let symptomID = imported.resolvedSymptomID,
                  !symptomID.isEmpty else {
                skipped += 1
                continue
            }
            let key = Key(date: normalizedSecond(startAt), symptomID: symptomID)
            let record: SymptomRecord
            if let existing = existingByKey[key] {
                record = existing
                updated += 1
            } else {
                record = SymptomRecord(startAt: startAt, symptomID: symptomID)
                context.insert(record)
                existingByKey[key] = record
                inserted += 1
            }

            record.startAt = startAt
            record.sSymptomID = symptomID
            record.bOngoing = imported.ongoing ?? false
            // 継続中と終了時刻は同時に成立しない
            record.endAt = record.bOngoing ? nil : imported.parsedEndAt
            record.severity = imported.parsedSeverity
            record.sNote = String((imported.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(SymptomLimits.noteImportMaxLength))
            record.medicineIDs = Array((imported.medicineIds ?? [])
                .prefix(SymptomLimits.maxMedicinesPerRecord))
            record.dataSource = RecordDataSource(rawValue: imported.dataSourceRaw ?? 0) ?? .appInput
            applyImportedWeather(imported.weather, to: record)
        }

        do {
            try saveChanges(context)
        } catch {
            context.rollback()
            throw error
        }
        return (inserted: inserted, updated: updated, skipped: skipped)
    }

    private static func applyImportedWeather(_ weather: SymptomWeatherImport?, to record: SymptomRecord) {
        guard let weather, weather.parsedSource.isPresent else {
            record.nTemp_10c = 0
            record.nHumidity_p = 0
            record.nPressure_10hpa = 0
            record.nPressureDelta24h_10hpa = 0
            record.bTempSet = false
            record.bHumiditySet = false
            record.bPressureDelta24hSet = false
            record.sWeatherSourceURL = ""
            record.nDevicePressure_10hpa = 0
            record.sWeatherSymbol = ""
            record.sWeatherPlace = ""
            record.sWeatherStationID = ""
            record.sPressureStationID = ""
            record.nPressureStationDistance_10km = 0
            record.nIndoorTemp_10c = 0
            record.nIndoorHumidity_p = 0
            record.bIndoorTempSet = false
            record.bIndoorHumiditySet = false
            record.bTempEdited = false
            record.bHumidityEdited = false
            record.bPressureEdited = false
            record.weatherSource = .none
            return
        }
        record.nTemp_10c = clampedSignedDec(weather.temp, SymptomLimits.tempRange_10c)
        // 旧バックアップにはフラグが無いので、値があれば入力済みとみなす
        record.bTempSet = weather.tempSet ?? (weather.temp != nil)
        record.nHumidity_p = clampedSignedInt(weather.humidity, SymptomLimits.humidityRange_p)
        record.bHumiditySet = weather.humiditySet ?? (weather.humidity != nil)
        record.nPressure_10hpa = clampedSignedDec(weather.pressure, SymptomLimits.pressureRange_10hpa)
        record.nPressureDelta24h_10hpa = clampedSignedDec(
            weather.pressureDelta24h, SymptomLimits.pressureDeltaRange_10hpa
        )
        record.bPressureDelta24hSet = weather.pressureDelta24hSet ?? (weather.pressureDelta24h != nil)
        record.sWeatherSourceURL = String((weather.sourceUrl ?? "").prefix(300))
        record.dWeatherObservedAt = weather.parsedObservedAt
        record.nDevicePressure_10hpa = clampedSignedDec(
            weather.devicePressure, SymptomLimits.pressureRange_10hpa
        )
        record.sWeatherSymbol = String((weather.symbol ?? "").prefix(60))
        record.sWeatherPlace = String((weather.place ?? "").prefix(60))
        record.sWeatherStationID = String((weather.stationId ?? "").prefix(16))
        record.sPressureStationID = String((weather.pressureStationId ?? "").prefix(16))
        record.nPressureStationDistance_10km = weather.pressureStationDistanceKm
            .map { max(0, Int(($0 * 10).rounded())) } ?? 0
        record.bIndoorTempSet = weather.indoorTemp != nil
        record.nIndoorTemp_10c = weather.indoorTemp
            .map { clampedSignedDec($0, SymptomLimits.tempRange_10c) } ?? 0
        record.bIndoorHumiditySet = weather.indoorHumidity != nil
        record.nIndoorHumidity_p = weather.indoorHumidity
            .map { clampedSignedInt($0, SymptomLimits.humidityRange_p) } ?? 0
        record.bTempEdited = weather.tempEdited ?? false
        record.bHumidityEdited = weather.humidityEdited ?? false
        record.bPressureEdited = weather.pressureEdited ?? false
        record.weatherSource = weather.parsedSource
    }

    /// 気温や気圧差は負の値も正しいので、測定値用の clamp（0=未入力）とは分ける
    static func clampedSignedDec(_ raw: Double?, _ range: (min: Int, max: Int)) -> Int {
        guard let raw else { return 0 }
        let scaled = Int((raw * 10).rounded())
        return min(max(scaled, range.min), range.max)
    }

    static func clampedSignedInt(_ raw: Int?, _ range: (min: Int, max: Int)) -> Int {
        guard let raw else { return 0 }
        return min(max(raw, range.min), range.max)
    }

    @discardableResult
    static func merge(
        _ importedRecords: [RecordImportRecord],
        into context: ModelContext,
        categoryAppearances: [DateOptAppearance]? = nil,
        saveChanges: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ImportResult {
        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime < bodyRecordGoalDate }
        )
        let existingRecords = try context.fetch(descriptor)
        var existingByDate: [Date: BodyRecord] = [:]
        for record in existingRecords {
            existingByDate[normalizedSecond(record.dateTime)] = record
        }

        var inserted = 0
        var updated = 0
        var skipped = 0
        for imported in importedRecords {
            guard let date = imported.parsedDate, date <= bodyRecordMaxDate else {
                skipped += 1
                continue
            }
            let key = normalizedSecond(date)
            let record: BodyRecord
            if let existing = existingByDate[key] {
                record = existing
                updated += 1
            } else {
                record = BodyRecord(dateTime: date, dateOpt: imported.dateOpt ?? .cat02)
                context.insert(record)
                existingByDate[key] = record
                inserted += 1
            }

            record.dateTime   = date
            record.dateOpt    = imported.dateOpt ?? .cat02
            record.dataSource = imported.dataSource ?? .appInput
            record.bCaution   = imported.cautionFlag ?? false
            record.sNote1     = (imported.memo1  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            record.sNote2     = (imported.memo2  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            record.sEquipment = (imported.device ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            record.nBpHi_mmHg    = clampedIntMeasure(imported.bpSystolic,    spec: MeasureRange.bpHi)
            record.nBpLo_mmHg    = clampedIntMeasure(imported.bpDiastolic,   spec: MeasureRange.bpLo)
            // 左右は血圧がある記録のみ。旧バックアップでは不明。
            record.bpSide = (record.nBpHi_mmHg > 0 || record.nBpLo_mmHg > 0) ? imported.parsedBpSide : .unknown
            record.nPulse_bpm    = clampedIntMeasure(imported.heartRate,     spec: MeasureRange.pulse)
            record.nTemp_10c     = clampedDecMeasure(imported.bodyTemp,      spec: MeasureRange.temp)
            record.nWeight_10Kg  = clampedDecMeasure(imported.weight,        spec: MeasureRange.weight)
            record.nBodyFat_10p  = clampedDecMeasure(imported.bodyFat,       spec: MeasureRange.bodyFat)
            record.nSkMuscle_10p = clampedDecMeasure(imported.skeletalMuscle, spec: MeasureRange.skMuscle)
            // 旧バックアップではnilとなるため従来記録との互換性を保てる
            record.measurementSampleSet = imported.measurementSamples
        }

        do {
            try saveChanges(context)
        } catch {
            // 保存失敗時は挿入と更新をまとめて取り消す
            context.rollback()
            throw error
        }
        let normalizedAppearances = categoryAppearances.map { normalizedDateOptAppearances($0) }
        return ImportResult(
            inserted: inserted,
            updated: updated,
            skipped: skipped,
            categoryAppearances: normalizedAppearances
        )
    }

    // MARK: 共有ヘルパー

    /// ISO8601 ⇄ Date のラウンドトリップで発生する subsecond 精度のズレを吸収するため、
    /// 重複判定は秒単位に丸めた日時で行う
    static func normalizedSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    /// インポート測定値（整数）を 0=未入力 または許容範囲内に丸める
    static func clampedIntMeasure(_ raw: Int?, spec: MeasureSpec) -> Int {
        guard let v = raw, v > 0 else { return 0 }
        return min(max(v, spec.min), spec.max)
    }

    /// インポート測定値（小数）を ×10 整数化のうえ、許容範囲内に clamp
    static func clampedDecMeasure(_ raw: Double?, spec: MeasureSpec) -> Int {
        guard let v = raw, v > 0 else { return 0 }
        let scaled = Int((v * 10).rounded())
        return min(max(scaled, spec.min), spec.max)
    }

    /// 区分表示マスタを完全な配列に正規化する。未指定区分は既定値で補完。
    static func normalizedDateOptAppearances(_ imported: [DateOptAppearance]) -> [DateOptAppearance] {
        DateOpt.allCases.map { dateOpt in
            if let appearance = imported.first(where: { $0.dateOptRawValue == dateOpt.rawValue }) {
                return normalizedAppearance(appearance, for: dateOpt)
            }
            return dateOpt.defaultAppearance
        }
    }

    // MARK: 内部ヘルパー

    private static func decimalNumber(_ value: Int, scale: Int) -> NSDecimalNumber {
        // JSON 出力で Double の2進小数誤差が長く出ないよう、10進数として出力する
        NSDecimalNumber(value: value).dividing(by: NSDecimalNumber(mantissa: 1, exponent: Int16(scale), isNegative: false))
    }

    /// Codable値をJSONSerializationへ渡せるオブジェクトに変換する
    private static func jsonObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func normalizedAppearance(
        _ appearance: DateOptAppearance,
        for dateOpt: DateOpt
    ) -> DateOptAppearance {
        let iconName = DateOptIconOption.all.contains(appearance.iconName)
            ? appearance.iconName
            : dateOpt.defaultIcon
        let colorKey = DateOptColorOption.all.contains { $0.id == appearance.colorKey }
            ? appearance.colorKey
            : dateOpt.defaultColorKey
        return DateOptAppearance(
            dateOptRawValue: dateOpt.rawValue,
            nameJa: limitedImportName(appearance.nameJa),
            nameEn: limitedImportName(appearance.nameEn),
            iconName: iconName,
            colorKey: colorKey
        )
    }

    private static func limitedImportName(_ value: String) -> String {
        // 壊れたバックアップによる極端な長文だけを防ぎ、通常の名称は維持する
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }

    private static func appearanceObject(_ appearance: DateOptAppearance) -> [String: Any] {
        [
            "dateOptRawValue": appearance.dateOptRawValue,
            "nameJa":   appearance.nameJa,
            "nameEn":   appearance.nameEn,
            "iconName": appearance.iconName,
            "colorKey": appearance.colorKey,
        ]
    }
}
