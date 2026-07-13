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

    static let currentSchemaVersion = 1

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
        style: RecordJSONExportStyle = .compact,
        categoryAppearances: [DateOptAppearance]? = nil,
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

        return (try? JSONSerialization.data(withJSONObject: envelope, options: style.jsonOptions)) ?? Data()
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
        return try merge(
            envelope.records,
            into: context,
            categoryAppearances: envelope.categoryAppearances,
            saveChanges: saveChanges
        )
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
