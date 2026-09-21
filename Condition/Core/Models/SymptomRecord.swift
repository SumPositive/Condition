// SymptomRecord.swift
// SwiftData モデル（症状メモ）
//
// 測定記録（BodyRecord）とはリレーションを張らず、時刻で突き合わせる。
// 命名は BodyRecord の流儀に合わせる（n/s/b プレフィックス、単位サフィックス、0=未入力）。

import Foundation
import SwiftData

// MARK: - 程度

/// 症状の程度。rawValue は HealthKit の `HKCategoryValueSeverity` と一致させてある。
/// 変換を挟まないので、HealthKit へ書き出しても情報が落ちない。
enum SymptomSeverity: Int, CaseIterable, Codable, Identifiable {
    case unspecified = 0   // 未指定（外部データ取り込み専用。UI には出さない）
    case notPresent  = 1   // なし
    case mild        = 2   // 軽い
    case moderate    = 3   // 中くらい
    case severe      = 4   // 強い

    var id: Int { rawValue }

    /// 記録画面で選べる程度。`unspecified` は含めない
    static let selectableCases: [SymptomSeverity] = [.notPresent, .mild, .moderate, .severe]

    /// 新規記録の初期選択
    static let defaultForNewRecord: SymptomSeverity = .moderate

    var labelKey: String {
        switch self {
        case .unspecified: return "symptom.severity.unspecified"
        case .notPresent:  return "symptom.severity.notPresent"
        case .mild:        return "symptom.severity.mild"
        case .moderate:    return "symptom.severity.moderate"
        case .severe:      return "symptom.severity.severe"
        }
    }

    var colorKey: String {
        switch self {
        case .unspecified: return "gray"
        case .notPresent:  return "gray"
        case .mild:        return "green"
        case .moderate:    return "orange"
        case .severe:      return "red"
        }
    }

    /// 統計の対象にしてよい程度か（未指定は集計から外す）
    var isCountable: Bool { self != .unspecified }
}

// MARK: - 天候の取得元

enum SymptomWeatherSource: Int, Codable {
    case none   = 0   // 未取得
    case auto   = 1   // WeatherKit から自動取得
    case manual = 2   // 手動入力

    var isPresent: Bool { self != .none }
}

// MARK: - モデル

@Model
final class SymptomRecord {

    // MARK: - 日時
    @Attribute(.spotlight) var startAt: Date = Date()
    /// 終了時刻。nil かつ bOngoing == false なら「点」の記録
    var endAt: Date? = nil
    /// 継続中（終了時刻の入力待ち）
    var bOngoing: Bool = false

    // MARK: - 症状
    /// 辞書由来は slug（"headache"）、ユーザー追加は "u:<UUID>"
    var sSymptomID: String = ""
    /// SymptomSeverity rawValue（= HKCategoryValueSeverity rawValue）
    var nSeverity: Int = SymptomSeverity.moderate.rawValue

    // MARK: - 付帯情報
    var sNote: String = ""
    /// 薬IDの JSON 配列。症状と違い、薬は同時に複数あるのが普通
    var sMedicineIDs: String = ""
    var nDataSource: Int = RecordDataSource.appInput.rawValue

    // MARK: - 天候スナップショット（0 / 空 = 未取得）
    var nTemp_10c: Int = 0                  // 気温 x10 ℃
    var nHumidity_p: Int = 0                // 湿度 %
    var nPressure_10hpa: Int = 0            // 気圧 x10 hPa
    var nPressureDelta24h_10hpa: Int = 0    // 24時間前との差 x10 hPa（符号あり）
    var sWeatherSymbol: String = ""         // SF Symbol 名
    var sWeatherPlace: String = ""          // 市区町村レベルの地名
    var nWeatherSource: Int = SymptomWeatherSource.none.rawValue

    // MARK: - 初期化

    init(startAt: Date = Date(), symptomID: String = "") {
        self.startAt = startAt
        self.sSymptomID = symptomID
    }
}

// MARK: - アクセサ

extension SymptomRecord {

    @Transient var severity: SymptomSeverity {
        get { SymptomSeverity(rawValue: nSeverity) ?? .unspecified }
        set { nSeverity = newValue.rawValue }
    }

    @Transient var dataSource: RecordDataSource {
        get { RecordDataSource(rawValue: nDataSource) ?? .appInput }
        set { nDataSource = newValue.rawValue }
    }

    @Transient var weatherSource: SymptomWeatherSource {
        get { SymptomWeatherSource(rawValue: nWeatherSource) ?? .none }
        set { nWeatherSource = newValue.rawValue }
    }

    /// 薬IDの配列。壊れた JSON は空配列として扱う
    @Transient var medicineIDs: [String] {
        get {
            guard !sMedicineIDs.isEmpty,
                  let data = sMedicineIDs.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return decoded
        }
        set {
            guard !newValue.isEmpty,
                  let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                sMedicineIDs = ""
                return
            }
            sMedicineIDs = json
        }
    }

    /// セクション表示用年月（例: 2026年3月 → 202603）。BodyRecord.yearMonth と揃える
    @Transient var yearMonth: Int {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: startAt)
        return (comps.year ?? 0) * 100 + (comps.month ?? 0)
    }

    /// 終了済みのエピソードか
    @Transient var isCompleted: Bool {
        !bOngoing && endAt != nil
    }

    /// 持続時間。終了済みなら実測、継続中は現在までの暫定値、点の記録は nil
    @Transient var duration: TimeInterval? {
        if let endAt { return max(0, endAt.timeIntervalSince(startAt)) }
        if bOngoing { return max(0, Date().timeIntervalSince(startAt)) }
        return nil
    }

    /// 統計で使える確定した持続時間（継続中と点の記録は除外）
    @Transient var completedDuration: TimeInterval? {
        guard isCompleted, let endAt else { return nil }
        return max(0, endAt.timeIntervalSince(startAt))
    }

    /// 天候が入っているか
    @Transient var hasWeather: Bool {
        weatherSource.isPresent
    }
}

// MARK: - 入力上限

enum SymptomLimits {
    /// メモの最大文字数（壊れたバックアップの極端な長文だけを弾く）
    static let noteMaxLength = 2000
    /// 1件に付けられる薬の最大数
    static let maxMedicinesPerRecord = 10
    /// 気温・湿度・気圧の入力許容範囲（手動入力とインポートの clamp に使う）
    static let tempRange_10c        = (min: -600, max: 600)      // -60.0 〜 60.0 ℃
    static let humidityRange_p      = (min: 0,    max: 100)      // 0 〜 100 %
    static let pressureRange_10hpa  = (min: 8000, max: 11000)    // 800.0 〜 1100.0 hPa
    static let pressureDeltaRange_10hpa = (min: -1000, max: 1000) // ±100.0 hPa
}
