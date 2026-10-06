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

/// あとから足した項目の「キーが無い」と「null で空にする」を区別する。
///
/// 旧バックアップには項目そのものが無いので、同じ日時の既存記録へ重ねたとき
/// 端末内の値を消してはいけない。エクスポートは値が無ければ明示的に null を書くので、
/// 新しいバックアップでは null を「空にする」指示として扱える
enum ImportField<Value: Decodable>: Decodable {
    /// キーが無い（旧形式）。既存値を保持する
    case absent
    /// 明示的な null。値を空にする
    case null
    case value(Value)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .null : .value(try container.decode(Value.self))
    }
}

extension KeyedDecodingContainer {
    /// 合成された init(from:) は ImportField のプロパティをこの多重定義で読む。
    /// キーが無いときに throw せず `.absent` を返す
    func decode<Value>(_ type: ImportField<Value>.Type, forKey key: Key) throws -> ImportField<Value> {
        guard contains(key) else { return .absent }
        return try decodeIfPresent(type, forKey: key) ?? .null
    }
}

struct RecordImportEnvelope: Decodable {
    let schemaVersion: Int?
    let categoryAppearances: [DateOptAppearance]?
    let records: [RecordImportRecord]
    /// 症状メモ（schemaVersion 2 以降）。旧バックアップには無いので任意
    let symptoms: [SymptomImportRecord]?
    /// 症状・薬のタグリスト（表示名と並び順の復元用）
    let symptomTags: SymptomTagList?
    let medicineTags: SymptomTagList?
    /// 直前の状況のタグリスト。追加前のバックアップには無いので任意
    let triggerTags: SymptomTagList?
    /// アプリの設定（表示・記録・グラフ・統計・分析の配置・目標値）。追加前のバックアップには無いので任意
    let settings: AppSettingsBackup?
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
    let triggers: [String]?     // 表示名
    /// 直前の状況は追加前のバックアップには無い。無ければ既存の選択を保持する
    let triggerIds: ImportField<[String]>
    let dataSourceRaw: Int?
    /// 無ければ既存の環境を保持し、null なら環境を空にする
    let weather: ImportField<SymptomWeatherImport>

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

    /// 症状ID。旧い書き出しや他アプリ由来で ID が無い場合は、薬・直前の状況と同じく
    /// 同梱のタグリストと辞書（全対応言語）から表示名を引く
    func resolvedSymptomID(tags: SymptomTagList?) -> String? {
        if let symptomId, !symptomId.isEmpty { return symptomId }
        return Self.resolveID(name: symptom ?? "", tags: tags, matchingID: SymptomCatalog.matchingID(forName:))
    }

    var parsedSeverity: SymptomSeverity {
        SymptomSeverity(rawValue: severity ?? 0) ?? .unspecified
    }

    /// 終了日時。開始より前なら編集画面と同じく成立しないので、日時不明として扱う
    func validEndAt(startAt: Date) -> Date? {
        guard let parsedEndAt, startAt <= parsedEndAt else { return nil }
        return parsedEndAt
    }

    /// 薬の ID。ID の無い旧形式や外部作成の JSON では表示名から引く
    func resolvedMedicineIDs(tags: SymptomTagList?) -> [String] {
        if let medicineIds { return medicineIds }
        return Self.resolveIDs(names: medicines ?? [], tags: tags, matchingID: MedicineCatalog.matchingID(forName:))
    }

    /// 直前の状況の ID。ID が無く表示名だけあるときは表示名から引く
    func resolvedTriggerIDs(tags: SymptomTagList?) -> ImportField<[String]> {
        guard case .absent = triggerIds, let triggers else { return triggerIds }
        return .value(Self.resolveIDs(names: triggers, tags: tags, matchingID: TriggerCatalog.matchingID(forName:)))
    }

    /// 表示名を ID へ。名前を付け替えたタグやユーザー追加タグは同梱のタグリストから、
    /// それ以外は辞書から引く。引けない名前は取り込まない
    private static func resolveIDs(
        names: [String],
        tags: SymptomTagList?,
        matchingID: (String) -> String?
    ) -> [String] {
        var ids: [String] = []
        for name in names {
            let id = resolveID(name: name, tags: tags, matchingID: matchingID)
            if let id, !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// 表示名1つを ID へ。同梱タグリストの付けた名前を先に見て、無ければ辞書を引く
    private static func resolveID(
        name rawName: String,
        tags: SymptomTagList?,
        matchingID: (String) -> String?
    ) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return tags?.tags.first { !$0.customName.isEmpty && $0.customName == name }?.id
            ?? matchingID(name)
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

/// 起床時の睡眠（開始日時は記録日時と同じ ISO8601 文字列）
struct RecordImportSleep: Decodable {
    let start: String?
    let minutes: Int?
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
    /// 複数回測定の元の値。旧バックアップには無い。無ければ既存値を保持し、null なら空にする
    let measurementSamples: ImportField<MeasurementSampleSet>
    /// 測定に付けた環境。旧バックアップには無い。無ければ既存値を保持し、null なら空にする
    let environment: ImportField<EnvironmentSnapshot>
    /// 起床時の睡眠。旧バックアップには無い。無ければ既存値を保持し、null なら空にする
    let sleep: ImportField<RecordImportSleep>

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

    /// 2: 症状メモ（symptoms / symptomTags / medicineTags）を追加。
    /// 直前の状況（triggerIds / triggerTags）と設定（settings）は任意項目の追加なので版は上げない
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
        var triggerTags: SymptomTagList? = nil
        /// バックアップが含んでいた設定。反映するかは呼び出し側で利用者に確かめる
        var settings: AppSettingsBackup? = nil
    }

    // MARK: エクスポート

    /// 記録の配列を JSON データへシリアライズ。区分表示マスタも同梱する。
    /// - Parameters:
    ///   - records: 出力対象の `BodyRecord` 配列（目標値レコードは事前に除外しておくこと）
    ///   - style: 整形スタイル
    ///   - categoryAppearances: 含める区分表示マスタ（nil の場合は省略）
    ///   - exportDate: メタデータ用の出力時刻（テスト容易性のため引数化、本番は `Date()`）
    /// - Throws: 一部の項目でも変換できない場合。欠けたバックアップを正常扱いで共有しないため
    static func export(
        records: [BodyRecord],
        symptoms: [SymptomRecord] = [],
        style: RecordJSONExportStyle = .compact,
        categoryAppearances: [DateOptAppearance]? = nil,
        symptomTags: SymptomTagList? = nil,
        medicineTags: SymptomTagList? = nil,
        triggerTags: SymptomTagList? = nil,
        settings: AppSettingsBackup? = nil,
        exportDate: Date = Date()
    ) throws -> Data {
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
            // 無いときは null を書き、旧形式（キー無し＝既存値を保持）と区別する
            if let sampleSet = record.measurementSampleSet {
                object["measurementSamples"] = try jsonObject(sampleSet)
            } else {
                object["measurementSamples"] = NSNull()
            }
            // 環境の取得元・室内値・端末気圧もバックアップに含める
            if record.environmentSnapshot.hasAnyValue {
                object["environment"] = try jsonObject(record.environmentSnapshot)
            } else {
                object["environment"] = NSNull()
            }
            // 睡眠も同じく、無いときは null を書いて旧形式と区別する
            let sleep = record.sleepEntry
            if sleep.hasAnyValue {
                var sleepObject: [String: Any] = [:]
                if let start = sleep.start { sleepObject["start"] = iso.string(from: start) }
                // 不眠は -1、10時間超は 630 のまま書き、取り込みで元に戻せるようにする
                if sleep.minutes != 0 { sleepObject["minutes"] = sleep.minutes }
                object["sleep"] = sleepObject
            } else {
                object["sleep"] = NSNull()
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
                symptomObject(
                    $0, iso: iso,
                    symptomTags: symptomTags, medicineTags: medicineTags, triggerTags: triggerTags
                )
            }
        }
        // 表示名と並び順を復元できるようタグリストも同梱する
        if let symptomTags {
            envelope["symptomTags"] = try jsonObject(symptomTags)
        }
        if let medicineTags {
            envelope["medicineTags"] = try jsonObject(medicineTags)
        }
        if let triggerTags {
            envelope["triggerTags"] = try jsonObject(triggerTags)
        }
        // 設定は任意項目の追加なので schemaVersion は上げない（古いアプリでも記録は取り込める）
        if let settings {
            envelope["settings"] = try jsonObject(settings)
        }

        return try JSONSerialization.data(withJSONObject: envelope, options: style.jsonOptions)
    }

    /// 症状1件の JSON オブジェクト。既存の "condition"/"conditionRaw" と同じく、
    /// 人が読める表示名と復元用の ID を両方出す。
    /// 記録一覧の書き出し（JSON）でも同じ形にするため内部公開にする
    static func symptomObject(
        _ record: SymptomRecord,
        iso: ISO8601DateFormatter,
        symptomTags: SymptomTagList?,
        medicineTags: SymptomTagList?,
        triggerTags: SymptomTagList?
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
        let triggerIDs = record.triggerIDs
        // 空でも書き、旧形式（キー無し＝既存の選択を保持）と区別する
        object["triggerIds"] = triggerIDs
        if !triggerIDs.isEmpty {
            object["triggers"] = triggerIDs.map { id in
                (triggerTags?.tag(for: id) ?? SymptomTag(id: id)).triggerDisplayName
            }
        }
        // 屋外の取得元が無くても、室温・室内湿度・端末気圧だけの記録はある。
        // 取得元ではなく、環境のどれかに値があるかで出力を決める
        if record.environmentSnapshot.hasAnyValue {
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
        } else {
            // 無いときは null を書き、旧形式（キー無し＝既存の環境を保持）と区別する
            object["weather"] = NSNull()
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
        // 測定記録と症状メモは途中で保存せず、両方を統合してから1回だけ保存する。
        // 片方だけ保存された状態で失敗を報告すると、再実行時に利用者が混乱するため
        var result: ImportResult
        do {
            result = try merge(
                envelope.records,
                into: context,
                categoryAppearances: envelope.categoryAppearances,
                saveChanges: { _ in }
            )
            // 症状メモは schemaVersion 2 以降にしか無い。旧バックアップでは何もしない
            if let symptoms = envelope.symptoms, !symptoms.isEmpty {
                let symptomResult = try mergeSymptoms(
                    symptoms,
                    into: context,
                    symptomTags: envelope.symptomTags,
                    medicineTags: envelope.medicineTags,
                    triggerTags: envelope.triggerTags,
                    saveChanges: { _ in }
                )
                result.symptomsInserted = symptomResult.inserted
                result.symptomsUpdated = symptomResult.updated
                result.symptomsSkipped = symptomResult.skipped
            }
            try saveChanges(context)
        } catch {
            // 統合途中・保存時のどちらで失敗しても、測定記録と症状メモをまとめて取り消す
            context.rollback()
            throw error
        }
        result.symptomTags = envelope.symptomTags
        result.medicineTags = envelope.medicineTags
        result.triggerTags = envelope.triggerTags
        result.settings = envelope.settings
        return result
    }

    /// 症状メモを統合する。開始日時（秒丸め）と症状IDが一致するレコードを同一とみなす。
    /// 測定記録と違い、同じ時刻に別の症状を記録できる（1レコード1症状のため）
    @discardableResult
    static func mergeSymptoms(
        _ importedSymptoms: [SymptomImportRecord],
        into context: ModelContext,
        symptomTags: SymptomTagList? = nil,
        medicineTags: SymptomTagList? = nil,
        triggerTags: SymptomTagList? = nil,
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
                  let symptomID = imported.resolvedSymptomID(tags: symptomTags),
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
            record.endAt = record.bOngoing ? nil : imported.validEndAt(startAt: startAt)
            record.severity = imported.parsedSeverity
            record.sNote = String((imported.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(SymptomLimits.noteImportMaxLength))
            record.medicineIDs = Array(imported.resolvedMedicineIDs(tags: medicineTags)
                .prefix(SymptomLimits.maxMedicinesPerRecord))
            switch imported.resolvedTriggerIDs(tags: triggerTags) {
            case .absent:
                break   // 旧形式。既存の選択を保持する
            case .null:
                record.triggerIDs = []
            case .value(let triggerIDs):
                record.triggerIDs = TriggerCatalog.normalizedSelection(Array(triggerIDs
                    .prefix(SymptomLimits.maxTriggersPerRecord)))
            }
            record.dataSource = RecordDataSource(rawValue: imported.dataSourceRaw ?? 0) ?? .appInput
            switch imported.weather {
            case .absent:
                break   // 旧形式。既存の環境を保持する
            case .null:
                applyImportedWeather(nil, to: record)
            case .value(let weather):
                applyImportedWeather(weather, to: record)
            }
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
        // weather が null の記録だけ環境を空にする。取得元が "none" でも、
        // 室内値・端末気圧だけを持つ記録があるので値は取り込む
        guard let weather else {
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
        record.sWeatherSourceURL = String((weather.sourceUrl ?? "").prefix(SymptomLimits.weatherSourceURLMaxLength))
        record.dWeatherObservedAt = weather.parsedObservedAt
        record.nDevicePressure_10hpa = clampedSignedDec(
            weather.devicePressure, SymptomLimits.pressureRange_10hpa
        )
        record.sWeatherSymbol = String((weather.symbol ?? "").prefix(SymptomLimits.weatherSymbolMaxLength))
        record.sWeatherPlace = String((weather.place ?? "").prefix(SymptomLimits.weatherPlaceMaxLength))
        record.sWeatherStationID = String((weather.stationId ?? "").prefix(SymptomLimits.stationIDMaxLength))
        record.sPressureStationID = String((weather.pressureStationId ?? "").prefix(SymptomLimits.stationIDMaxLength))
        record.nPressureStationDistance_10km = weather.pressureStationDistanceKm
            .flatMap { clampedTenths($0, SymptomLimits.pressureStationDistanceRange_10km) } ?? 0
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
        return clampedTenths(raw, range) ?? 0
    }

    /// 小数を ×10 の整数へ。変換の詳細は `SymptomLimits.clampedScaled` を参照
    /// - Returns: 非有限値（NaN・無限大）は nil
    static func clampedTenths(_ raw: Double, _ range: (min: Int, max: Int)) -> Int? {
        SymptomLimits.clampedScaled(raw, scale: 1, range)
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
            // 旧形式で項目が無い場合は既存値を保持し、null なら空にする
            switch imported.measurementSamples {
            case .absent:
                break
            case .null:
                record.measurementSampleSet = nil
            case .value(let sampleSet):
                record.measurementSampleSet = sampleSet
            }
            switch imported.environment {
            case .absent:
                break
            case .null:
                record.environmentSnapshot = EnvironmentSnapshot()
            case .value(let environment):
                // 症状の weather と同じ範囲・文字列長へ収めてから保存する
                record.environmentSnapshot = environment.normalized()
            }
            switch imported.sleep {
            case .absent:
                break
            case .null:
                record.sleepEntry = SleepEntry()
            case .value(let sleep):
                // 記録日時と同じ書式で読み、選択肢の刻みへ寄せる
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
                let start = sleep.start.flatMap { iso.date(from: $0) }
                record.sleepEntry = SleepEntry(start: start, minutes: sleep.minutes ?? 0)
                    .normalized(recordDate: date)
            }
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
        return clampedTenths(v, (min: spec.min, max: spec.max)) ?? 0
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
    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
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
