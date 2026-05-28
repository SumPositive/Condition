// DateOpt.swift
// 測定時の状況区分（旧 MocEntity.h の DateOpt enum 相当）

import Foundation
import SwiftUI

enum DateOpt: Int, CaseIterable, Codable, Identifiable {
    case wake        = 0  // 起床時
    case rest        = 1  // 安静時
    case down        = 2  // 就寝前
    case sleep       = 3  // 就寝時
    case preExercise = 4  // 運動前
    case postExercise = 5 // 運動後

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .wake:         return "category.wake"
        case .rest:         return "category.rest"
        case .down:         return "category.beforeBed"
        case .sleep:        return "category.bedtime"
        case .preExercise:  return "category.preExercise"
        case .postExercise: return "category.postExercise"
        }
    }

    var defaultIcon: String {
        switch self {
        case .wake:         return "sun.horizon.fill"
        case .rest:         return "heart.fill"
        case .down:         return "moon.fill"
        case .sleep:        return "moon.zzz.fill"
        case .preExercise:  return "figure.wave"
        case .postExercise: return "figure.walk"
        }
    }

    var icon: String {
        DateOptAppearanceStore.appearance(for: self).iconName
    }

    var defaultColorKey: String {
        switch self {
        case .wake:         return "green"
        case .rest:         return "blue"
        case .down:         return "orange"
        case .sleep:        return "purple"
        case .preExercise:  return "teal"
        case .postExercise: return "red"
        }
    }

    var color: Color {
        DateOptColorOption.color(for: DateOptAppearanceStore.appearance(for: self).colorKey)
    }

    var displayName: String {
        DateOptAppearanceStore.appearance(for: self).displayName
    }

    var shortLabel: String {
        switch self {
        case .wake:         return "category.wake.short"
        case .rest:         return "category.rest.short"
        case .down:         return "category.beforeBed.short"
        case .sleep:        return "category.bedtime.short"
        case .preExercise:  return "category.preExercise.short"
        case .postExercise: return "category.postExercise.short"
        }
    }
}

/// 区分ごとの表示カスタマイズ
struct DateOptAppearance: Codable, Equatable, Identifiable {
    var dateOptRawValue: Int
    var nameJa: String
    var nameEn: String
    var iconName: String
    var colorKey: String

    var id: Int { dateOptRawValue }

    var displayName: String {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        if languageCode == "ja" {
            return nameJa.isEmpty ? fallbackNameJa : nameJa
        }
        return nameEn.isEmpty ? fallbackNameEn : nameEn
    }

    private var fallbackNameJa: String {
        DateOpt(rawValue: dateOptRawValue)?.defaultNameJa ?? ""
    }

    private var fallbackNameEn: String {
        DateOpt(rawValue: dateOptRawValue)?.defaultNameEn ?? ""
    }
}

extension DateOpt {
    var defaultNameJa: String {
        switch self {
        case .wake:         return "起床時"
        case .rest:         return "安静時"
        case .down:         return "就寝前"
        case .sleep:        return "就寝時"
        case .preExercise:  return "運動前"
        case .postExercise: return "運動後"
        }
    }

    var defaultNameEn: String {
        switch self {
        case .wake:         return "Wake"
        case .rest:         return "Rest"
        case .down:         return "PreBed"
        case .sleep:        return "Bedtime"
        case .preExercise:  return "PreEx"
        case .postExercise: return "PostEx"
        }
    }

    var defaultAppearance: DateOptAppearance {
        DateOptAppearance(
            dateOptRawValue: rawValue,
            nameJa: defaultNameJa,
            nameEn: defaultNameEn,
            iconName: defaultIcon,
            colorKey: defaultColorKey
        )
    }
}

/// 区分アイコンの候補。生活・睡眠・運動・測定の意味が伝わるものに絞る
enum DateOptIconOption {
    static let all: [String] = [
        "sun.horizon.fill",
        "heart.fill",
        "moon.fill",
        "moon.zzz.fill",
        "figure.wave",
        "figure.walk",
        "figure.run",
        "figure.strengthtraining.traditional",
        "figure.mind.and.body",
        "bed.double.fill",
        "house.fill",
        "stethoscope",
        "cross.case.fill",
        "alarm.fill",
        "clock.fill",
        "leaf.fill",
        "bolt.heart.fill",
        "drop.fill"
    ]
}

/// 区分色の候補。グラフと一覧で識別しやすい彩度の色を使う
struct DateOptColorOption: Identifiable {
    let id: String
    let color: Color

    static let all: [DateOptColorOption] = [
        DateOptColorOption(id: "green", color: .green),
        DateOptColorOption(id: "blue", color: .blue),
        DateOptColorOption(id: "orange", color: .orange),
        DateOptColorOption(id: "purple", color: .purple),
        DateOptColorOption(id: "teal", color: .teal),
        DateOptColorOption(id: "red", color: .red),
        DateOptColorOption(id: "pink", color: .pink),
        DateOptColorOption(id: "indigo", color: .indigo),
        DateOptColorOption(id: "cyan", color: .cyan),
        DateOptColorOption(id: "brown", color: .brown)
    ]

    static func color(for key: String) -> Color {
        all.first { $0.id == key }?.color ?? .secondary
    }
}

/// AppSettings初期化中にも使えるよう、UserDefaultsから直接読み出す軽量ストア
enum DateOptAppearanceStore {
    static func appearance(for dateOpt: DateOpt) -> DateOptAppearance {
        appearances().first { $0.dateOptRawValue == dateOpt.rawValue } ?? dateOpt.defaultAppearance
    }

    static func appearances() -> [DateOptAppearance] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.settDateOptAppearances),
              let decoded = try? JSONDecoder().decode([DateOptAppearance].self, from: data) else {
            return DateOpt.allCases.map(\.defaultAppearance)
        }
        // 新しい区分が増えた場合に備えて、不足分は既定値で補完する
        return DateOpt.allCases.map { dateOpt in
            decoded.first { $0.dateOptRawValue == dateOpt.rawValue } ?? dateOpt.defaultAppearance
        }
    }

    static func save(_ appearances: [DateOptAppearance]) {
        // UserDefaultsに入れられるようJSONデータへ変換する
        guard let data = try? JSONEncoder().encode(appearances) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKeys.settDateOptAppearances)
    }
}

// MARK: - 区分推定

/// 過去記録と時間帯マトリックスから、入力日時に最も自然な区分を推定する
enum DateOptEstimator {
    /// 推定結果と、区分ごとの内部スコア
    struct Result {
        let selected: DateOpt
        let matrixDefault: DateOpt
        let scores: [DateOpt: Double]
    }

    /// 時間帯マトリックスを優先しすぎず、履歴が少ない時の土台として使う固定加点
    private static let matrixBias = 1.5
    /// 同じ曜日の記録を少し強く見る倍率
    private static let sameWeekdayMultiplier = 1.25
    /// 時刻差がこの分数に近いほど、スコアが自然に弱くなる
    private static let timeScaleMinutes = 90.0
    /// 推定対象にする履歴期間
    private static let historyDays = 30
    /// 最大区分と次点がこの差未満なら、時間帯マトリックスを優先する
    private static let decisionMargin = 0.3

    /// 区分を1つ返す簡易API
    static func estimate(
        from records: [BodyRecord],
        targetDate: Date,
        hourMap: [Int],
        referenceDate: Date = Date()
    ) -> DateOpt {
        estimateResult(
            from: records,
            targetDate: targetDate,
            hourMap: hourMap,
            referenceDate: referenceDate
        ).selected
    }

    /// 区分ごとのスコアも含めて返す
    static func estimateResult(
        from records: [BodyRecord],
        targetDate: Date,
        hourMap: [Int],
        referenceDate: Date = Date()
    ) -> Result {
        let calendar = Calendar.current
        let targetHour = calendar.component(.hour, from: targetDate)
        let matrixDefault = matrixDateOpt(hour: targetHour, hourMap: hourMap)
        let cutoff = calendar.date(byAdding: .day, value: -historyDays, to: referenceDate) ?? referenceDate
        let targetWeekday = calendar.component(.weekday, from: targetDate)
        let targetMinutes = minutesOfDay(targetDate, calendar: calendar)

        // すべての区分を0点で用意し、あとで表示用にも扱いやすくする
        var scores = Dictionary(uniqueKeysWithValues: DateOpt.allCases.map { ($0, 0.0) })

        // 時間帯マトリックスは、履歴が薄い時に戻るための土台として加点する
        scores[matrixDefault, default: 0] += matrixBias

        for record in records {
            // 目標値レコードや未来レコードは推定材料にしない
            if bodyRecordGoalDate <= record.dateTime { continue }
            if referenceDate < record.dateTime { continue }
            if record.dateTime < cutoff { continue }

            let weekdayWeight = calendar.component(.weekday, from: record.dateTime) == targetWeekday
                ? sameWeekdayMultiplier
                : 1.0
            let timeWeight = timeProximityWeight(
                from: minutesOfDay(record.dateTime, calendar: calendar),
                to: targetMinutes
            )
            let recencyWeight = recencyWeight(recordDate: record.dateTime, referenceDate: referenceDate)

            // 各記録の区分へ、曜日・時刻差・新しさを掛け合わせた点を足す
            scores[record.dateOpt, default: 0] += weekdayWeight * timeWeight * recencyWeight
        }

        return Result(
            selected: selectedDateOpt(scores: scores, fallback: matrixDefault),
            matrixDefault: matrixDefault,
            scores: scores
        )
    }

    private static func matrixDateOpt(hour: Int, hourMap: [Int]) -> DateOpt {
        guard 0 <= hour, hour < hourMap.count else {
            return .rest
        }
        return DateOpt(rawValue: hourMap[hour]) ?? .rest
    }

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private static func timeProximityWeight(from sourceMinutes: Int, to targetMinutes: Int) -> Double {
        let rawDiff = abs(sourceMinutes - targetMinutes)
        let circularDiff = min(rawDiff, 1440 - rawDiff)
        let scaled = Double(circularDiff) / timeScaleMinutes
        // ガウス型に落とすことで、30分差は強く、2〜3時間差はかなり弱くなる
        return exp(-(scaled * scaled))
    }

    private static func recencyWeight(recordDate: Date, referenceDate: Date) -> Double {
        let daysAgo = max(0, referenceDate.timeIntervalSince(recordDate) / 86_400)
        // 30日以内の履歴は最低0.5倍まで残し、直近ほど強くする
        return max(0.5, 1.0 - daysAgo / 60.0)
    }

    private static func selectedDateOpt(scores: [DateOpt: Double], fallback: DateOpt) -> DateOpt {
        let ranked = scores.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return rhs.value < lhs.value
        }
        guard let top = ranked.first else {
            return fallback
        }
        let secondScore = ranked.dropFirst().first?.value ?? 0
        // 最大区分が次点と僅差なら、説明しやすく安定した時間帯マトリックスへ戻す
        if top.value - secondScore < decisionMargin {
            return fallback
        }
        return top.key
    }
}

// MARK: - データ入力元

enum RecordDataSource: Int {
    case appInput    = 0  // このアプリで入力された記録です
    case appModified = 1  // このアプリで入力後に変更された記録です
    case hkImport    = 2  // ヘルスケアから読み込まれた記録です
    case hkModified  = 3  // ヘルスケアから読み込まれた後に変更された記録です

    var icon: String {
        switch self {
        case .appInput:    return "app"
        case .appModified: return "app.fill"
        case .hkImport:    return "heart"
        case .hkModified:  return "heart.fill"
        }
    }

    var color: Color {
        return .secondary
    }

    var label: String {
        switch self {
        case .appInput:    return "text.enteredInThisApp"
        case .appModified: return "text.enteredInThisAppAndLater"
        case .hkImport:    return "health.thisRecordWasImportedFromHealthkit"
        case .hkModified:  return "health.thisRecordWasModifiedAfterBeing"
        }
    }
}
