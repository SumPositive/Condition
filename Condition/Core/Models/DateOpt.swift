// DateOpt.swift
// 測定時の状況区分（旧 MocEntity.h の DateOpt enum 相当）

import Foundation
import SwiftUI

enum DateOpt: Int, CaseIterable, Codable, Identifiable {
    case cat01 = 0  // 既定: 起床時
    case cat02 = 1  // 既定: 安静時
    case cat03 = 2  // 既定: 就寝前
    case cat04 = 3  // 既定: 就寝時
    case cat05 = 4  // 既定: 運動前
    case cat06 = 5  // 既定: 運動後
    case cat07 = 6  // 既定: 未定義
    case cat08 = 7  // 既定: 未定義

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .cat01: return "category.cat01"
        case .cat02: return "category.cat02"
        case .cat03: return "category.cat03"
        case .cat04: return "category.cat04"
        case .cat05: return "category.cat05"
        case .cat06: return "category.cat06"
        case .cat07: return "category.cat07"
        case .cat08: return "category.cat08"
        }
    }

    var defaultIcon: String {
        switch self {
        case .cat01: return defaultNamedIcon
        case .cat02: return defaultNamedIcon
        case .cat03: return defaultNamedIcon
        case .cat04: return defaultNamedIcon
        case .cat05: return defaultNamedIcon
        case .cat06: return defaultNamedIcon
        case .cat07: return undefinedIcon
        case .cat08: return undefinedIcon
        }
    }

    var icon: String {
        let appearance = DateOptAppearanceStore.appearance(for: self)
        // 未定義区分は番号アイコンで表示し、設定済みなら選択アイコンを使う
        return appearance.isDefined ? appearance.iconName : undefinedIcon
    }

    var defaultColorKey: String {
        switch self {
        case .cat01: return "green"
        case .cat02: return "blue"
        case .cat03: return "orange"
        case .cat04: return "purple"
        case .cat05: return "teal"
        case .cat06: return "red"
        case .cat07: return "gray"
        case .cat08: return "gray"
        }
    }

    var color: Color {
        let appearance = DateOptAppearanceStore.appearance(for: self)
        // 未定義区分は保存色に関係なくグレー系で表示する
        return appearance.isDefined ? DateOptColorOption.color(for: appearance.colorKey) : .secondary
    }

    var displayName: String {
        DateOptAppearanceStore.appearance(for: self).displayName
    }

    var placeholderName: String {
        let format = NSLocalizedString("settings.category.placeholderNumber", comment: "")
        return String(format: format, rawValue + 1)
    }

    var namePlaceholder: String {
        placeholderName
    }

    var isDefined: Bool {
        DateOptAppearanceStore.appearance(for: self).isDefined
    }

    var defaultNamedIcon: String {
        switch self {
        case .cat01: return "sun.horizon.fill"
        case .cat02: return "heart.fill"
        case .cat03: return "moon.fill"
        case .cat04: return "moon.zzz.fill"
        case .cat05: return "figure.wave"
        case .cat06: return "figure.walk"
        case .cat07: return "7.square.fill"
        case .cat08: return "8.square.fill"
        }
    }

    var undefinedIcon: String {
        "\(rawValue + 1).square"
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

    /// 現在の言語コード（区分名の言語判定に共通利用）
    static var currentLanguageCode: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        // 繁体字は script まで見て zh-Hant を判別する
        if code == "zh" {
            let script = Locale.current.language.script?.identifier
            return script == "Hant" ? "zh-Hant" : "zh"
        }
        return code
    }

    var displayName: String {
        switch Self.currentLanguageCode {
        case "ja":
            return nameJa.isEmpty ? fallbackOrPlaceholder(fallbackNameJa) : nameJa
        case "ko", "zh-Hant":
            // 保存名が英語プリセットのまま（未カスタム）なら現地語プリセットを表示する
            let localized = localizedFallbackName
            if nameEn.isEmpty { return fallbackOrPlaceholder(localized) }
            return isNameEnStillDefault ? (localized.isEmpty ? nameEn : localized) : nameEn
        default:
            return nameEn.isEmpty ? fallbackOrPlaceholder(fallbackNameEn) : nameEn
        }
    }

    var isDefined: Bool {
        // 名称を空欄にした区分は、既定名があっても未定義として扱う。
        // ja は nameJa、それ以外は nameEn の有無で判定する（保存構造は2言語のまま）。
        Self.currentLanguageCode == "ja" ? !nameJa.isEmpty : !nameEn.isEmpty
    }

    /// nameEn が英語プリセットのまま（＝ユーザーが編集していない）か
    private var isNameEnStillDefault: Bool {
        nameEn == fallbackNameEn
    }

    /// 名称編集フィールドの初期値。ja は nameJa、それ以外は nameEn を編集する。
    /// ko/zh-Hant で未カスタムなら現地語プリセットを出発点にする。
    var editableName: String {
        switch Self.currentLanguageCode {
        case "ja":
            return nameJa
        case "ko", "zh-Hant":
            return isNameEnStillDefault ? localizedFallbackName : nameEn
        default:
            return nameEn
        }
    }

    /// 現在の言語のプリセット既定名（ko/zh-Hant 用）
    private var localizedFallbackName: String {
        DateOpt(rawValue: dateOptRawValue)?.defaultLocalizedName ?? ""
    }

    private var fallbackNameJa: String {
        DateOpt(rawValue: dateOptRawValue)?.defaultNameJa ?? ""
    }

    private var fallbackNameEn: String {
        DateOpt(rawValue: dateOptRawValue)?.defaultNameEn ?? ""
    }

    private func fallbackOrPlaceholder(_ name: String) -> String {
        if name.isEmpty {
            return DateOpt(rawValue: dateOptRawValue)?.placeholderName ?? ""
        }
        return name
    }
}

extension DateOpt {
    var defaultNameJa: String {
        switch self {
        case .cat01: return "起床時"
        case .cat02: return "安静時"
        case .cat03: return "就寝前"
        case .cat04: return "就寝時"
        case .cat05: return "運動前"
        case .cat06: return "運動後"
        case .cat07: return ""
        case .cat08: return ""
        }
    }

    var defaultNameEn: String {
        switch self {
        case .cat01: return "Wake"
        case .cat02: return "Rest"
        case .cat03: return "PreBed"
        case .cat04: return "Bedtime"
        case .cat05: return "PreEx"
        case .cat06: return "PostEx"
        case .cat07: return ""
        case .cat08: return ""
        }
    }

    var defaultNameKo: String {
        switch self {
        case .cat01: return "기상"
        case .cat02: return "안정"
        case .cat03: return "취침전"
        case .cat04: return "취침"
        case .cat05: return "운동전"
        case .cat06: return "운동후"
        case .cat07: return ""
        case .cat08: return ""
        }
    }

    var defaultNameZhHant: String {
        switch self {
        case .cat01: return "起床"
        case .cat02: return "安靜"
        case .cat03: return "睡前"
        case .cat04: return "就寢"
        case .cat05: return "運動前"
        case .cat06: return "運動後"
        case .cat07: return ""
        case .cat08: return ""
        }
    }

    /// 現在の言語に応じた既定の区分名（プリセット）
    var defaultLocalizedName: String {
        switch DateOptAppearance.currentLanguageCode {
        case "ja":      return defaultNameJa
        case "ko":      return defaultNameKo
        case "zh-Hant": return defaultNameZhHant
        default:        return defaultNameEn
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
        "sun.max.fill",
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
        "drop.fill",
        "smoke.fill",
        "snowflake",
        "tag.fill",
        "tag",
        "1.square.fill",
        "2.square.fill",
        "3.square.fill",
        "4.square.fill",
        "5.square.fill",
        "6.square.fill",
        "7.square.fill",
        "8.square.fill"
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
        DateOptColorOption(id: "brown", color: .brown),
        // 区分7/8の初期色として使うグレー系
        DateOptColorOption(id: "gray", color: .secondary)
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
    /// 推定対象にする履歴期間（3ヶ月相当）
    private static let historyDays = 90
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
            return .cat02
        }
        return DateOpt(rawValue: hourMap[hour]) ?? .cat02
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
        // 90日以内の履歴は最低0.5倍まで残し、直近ほど強くする
        return max(0.5, 1.0 - daysAgo / 180.0)
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

// MARK: - 血圧の測定箇所（左右）

/// 血圧をどちらの腕で測ったか。区分(DateOpt)とは独立したフラグ。
enum BpSide: Int, CaseIterable, Identifiable {
    case unknown = 0  // 不明（デフォルト）
    case right   = 1  // 右腕
    case left    = 2  // 左腕

    var id: Int { rawValue }

    // rawValue は保存互換のため据え置き。UI/セグメントの並びは [左, ・(不明), 右]。
    static var allCases: [BpSide] { [.left, .unknown, .right] }

    /// 全画面共通の表記（全言語 L/R 固定、不明は中点「・」）。文字数が言語で変わらない。
    var code: String {
        switch self {
        case .unknown: return "・"
        case .right:   return "R"
        case .left:    return "L"
        }
    }

    /// バッジ色（左右で色分け）。不明は色なし。
    var badgeColor: Color {
        switch self {
        case .unknown: return .secondary
        case .right:   return .orange
        case .left:    return .teal
        }
    }

    /// 左右が指定されているか（不明でない）
    var isDefined: Bool { self != .unknown }
}
