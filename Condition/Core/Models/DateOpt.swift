// DateOpt.swift
// 測定時の状況区分（旧 MocEntity.h の DateOpt enum 相当）

import Foundation
import SwiftUI

enum DateOpt: Int, CaseIterable, Codable, Identifiable {
    // 既定の名称は新規インストール向け（2.9.0 で見直し）。
    // それ以前からの利用者は旧既定（就寝時・運動後あり）を保存して固定する（legacyDefault* 参照）
    case cat01 = 0  // 既定: 起床時
    case cat02 = 1  // 既定: 安静時
    case cat03 = 2  // 既定: 就寝前
    case cat04 = 3  // 既定: 不調時（旧既定: 就寝時）
    case cat05 = 4  // 既定: 運動前
    case cat06 = 5  // 既定: 未定義（旧既定: 運動後）
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
        case .cat06: return undefinedIcon
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
        // 起床時は朝日のオレンジ、就寝前は夜の月の黄色（2.9.0 で見直し）
        case .cat01: return "orange"
        case .cat02: return "blue"
        case .cat03: return "yellow"
        case .cat04: return "pink"
        case .cat05: return "teal"
        case .cat06: return "gray"
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
        case .cat04: return "bolt.heart.fill"
        case .cat05: return "figure.wave"
        case .cat06: return "6.square.fill"
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

    /// nameEn が英語プリセットのまま（＝ユーザーが編集していない）か。
    /// 更新時に固定した旧既定（Bedtime / PostEx）も、編集していない名前として扱う
    private var isNameEnStillDefault: Bool {
        nameEn == fallbackNameEn || isNameEnLegacyDefault
    }

    private var isNameEnLegacyDefault: Bool {
        guard let legacy = DateOpt(rawValue: dateOptRawValue)?.legacyDefaultNameEn else { return false }
        return !nameEn.isEmpty && nameEn == legacy
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

    /// 現在の言語のプリセット既定名（ko/zh-Hant 用）。旧既定のままなら旧既定の現地語名
    private var localizedFallbackName: String {
        guard let opt = DateOpt(rawValue: dateOptRawValue) else { return "" }
        if isNameEnLegacyDefault, let legacy = opt.legacyDefaultLocalizedName { return legacy }
        return opt.defaultLocalizedName
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
        case .cat04: return "不調時"
        case .cat05: return "運動前"
        case .cat06: return ""
        case .cat07: return ""
        case .cat08: return ""
        }
    }

    var defaultNameEn: String {
        switch self {
        case .cat01: return "Wake"
        case .cat02: return "Rest"
        case .cat03: return "PreBed"
        case .cat04: return "Unwell"
        case .cat05: return "PreEx"
        case .cat06: return ""
        case .cat07: return ""
        case .cat08: return ""
        }
    }

    var defaultNameKo: String {
        switch self {
        case .cat01: return "기상"
        case .cat02: return "안정"
        case .cat03: return "취침전"
        case .cat04: return "몸 불편"
        case .cat05: return "운동전"
        case .cat06: return ""
        case .cat07: return ""
        case .cat08: return ""
        }
    }

    var defaultNameZhHant: String {
        switch self {
        case .cat01: return "起床"
        case .cat02: return "安靜"
        case .cat03: return "睡前"
        case .cat04: return "身體不適"
        case .cat05: return "運動前"
        case .cat06: return ""
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

    // MARK: 旧既定（2.8.x まで）

    /// 2.8.x までの既定。cat04 は「就寝時」、cat06 は「運動後」だった。
    /// 区分を編集したことのない既存の利用者は、既定をその場で使って表示しているので、
    /// 既定を変えると過去の記録の区分名まで変わってしまう。更新時にこの旧既定を保存して固定する
    var legacyDefaultAppearance: DateOptAppearance {
        switch self {
        case .cat04:
            return DateOptAppearance(
                dateOptRawValue: rawValue, nameJa: "就寝時", nameEn: "Bedtime",
                iconName: "moon.zzz.fill", colorKey: "purple"
            )
        case .cat06:
            return DateOptAppearance(
                dateOptRawValue: rawValue, nameJa: "運動後", nameEn: "PostEx",
                iconName: "figure.walk", colorKey: "red"
            )
        default:
            return defaultAppearance
        }
    }

    /// 旧既定の英語名と、その現地語名（ko / zh-Hant）。
    /// 固定した旧既定を、韓国語・繁体字でも英語のままにせず現地語で表示するために使う
    var legacyDefaultNameEn: String? {
        switch self {
        case .cat04: return "Bedtime"
        case .cat06: return "PostEx"
        default:     return nil
        }
    }

    var legacyDefaultLocalizedName: String? {
        switch (self, DateOptAppearance.currentLanguageCode) {
        case (.cat04, "ko"):      return "취침"
        case (.cat04, "zh-Hant"): return "就寢"
        case (.cat06, "ko"):      return "운동후"
        case (.cat06, "zh-Hant"): return "運動後"
        default:                  return nil
        }
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
        // 就寝前（月）の既定色
        DateOptColorOption(id: "yellow", color: .yellow),
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

/// 直近3ヶ月の記録から、同じ曜日・同じ時刻（時）で最も多い区分を推定する。
/// 該当する記録が無ければ未定とし、区分を決めるときは時間帯マップ（時間帯と区分の初期値）を使う
enum DateOptEstimator {
    /// 推定結果
    struct Result {
        /// 記録から推定した区分（nil = 未定）
        let estimated: DateOpt?
        /// 決定した区分（未定なら時間帯マップ）
        let selected: DateOpt
        /// 時間帯マップの区分
        let matrixDefault: DateOpt
        /// 同じ曜日・同じ時刻の記録数（区分ごと）
        let counts: [DateOpt: Int]
    }

    /// 推定対象にする履歴期間（3ヶ月相当）
    private static let historyDays = 90

    /// 区分を1つ返す。未定なら時間帯マップの区分
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

    /// 推定した区分と、決定した区分・記録数を返す
    static func estimateResult(
        from records: [BodyRecord],
        targetDate: Date,
        hourMap: [Int],
        referenceDate: Date = Date()
    ) -> Result {
        let calendar = AppDateCalendar.gregorian
        let targetHour = calendar.component(.hour, from: targetDate)
        let targetWeekday = calendar.component(.weekday, from: targetDate)
        let cutoff = calendar.date(byAdding: .day, value: -historyDays, to: referenceDate) ?? referenceDate

        // 推定対象は定義済み（名称設定済み）区分のみ。新規記録の候補と一致させる
        let definedOpts = DateOpt.allCases.filter(\.isDefined)

        // 時間帯マップの既定が未定義区分を指す場合は、定義済みの先頭へ丸める
        let rawMatrixDefault = matrixDateOpt(hour: targetHour, hourMap: hourMap)
        let matrixDefault = rawMatrixDefault.isDefined
            ? rawMatrixDefault
            : (definedOpts.first ?? rawMatrixDefault)

        // 同じ曜日・同じ時刻の記録を区分ごとに数え、同数のときに使う最新日時も控える
        var counts: [DateOpt: Int] = [:]
        var latest: [DateOpt: Date] = [:]
        for record in records {
            // 目標値レコード・未来の記録・3ヶ月より前の記録は使わない
            if bodyRecordGoalDate <= record.dateTime { continue }
            if referenceDate < record.dateTime { continue }
            if record.dateTime < cutoff { continue }
            // 未定義区分の履歴は新規記録の候補にならないので数えない
            guard record.dateOpt.isDefined else { continue }
            guard calendar.component(.weekday, from: record.dateTime) == targetWeekday,
                  calendar.component(.hour, from: record.dateTime) == targetHour else { continue }
            counts[record.dateOpt, default: 0] += 1
            latest[record.dateOpt] = max(latest[record.dateOpt] ?? .distantPast, record.dateTime)
        }

        // 最も多い区分。同数なら最近使った区分にする
        let estimated = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (latest[lhs.key] ?? .distantPast) < (latest[rhs.key] ?? .distantPast)
        }?.key

        return Result(
            estimated: estimated,
            selected: estimated ?? matrixDefault,
            matrixDefault: matrixDefault,
            counts: counts
        )
    }

    /// 時間帯と区分の初期値から区分を引く（測定時刻の通知でも使う）
    static func matrixDateOpt(hour: Int, hourMap: [Int]) -> DateOpt {
        guard 0 <= hour, hour < hourMap.count else {
            return .cat02
        }
        return DateOpt(rawValue: hourMap[hour]) ?? .cat02
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
    /// 国際慣習（航海の左舷＝赤・右舷＝緑）に合わせて 左＝赤・右＝緑 とする。
    /// 血圧の上（収縮期）・下（拡張期）はオレンジ／琥珀にして、この赤緑と被らせない。
    var badgeColor: Color {
        switch self {
        case .unknown: return .secondary
        case .right:   return .green
        case .left:    return .red
        }
    }

    /// 左右が指定されているか（不明でない）
    var isDefined: Bool { self != .unknown }
}
