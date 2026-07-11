// AppConstants.swift
// 旧 Global.h / MocEntity.h の定数群

import Foundation
import SwiftUI

// MARK: - #Predicate で参照可能なグローバル定数
// SwiftData の #Predicate マクロは @Model クラスの static プロパティを参照できないため
// ファイルスコープの let 定数として定義する

let bodyRecordGoalDate: Date = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var comps = DateComponents()
    comps.year = 2200; comps.month = 1; comps.day = 1
    comps.hour = 0; comps.minute = 0; comps.second = 0
    return cal.date(from: comps)!
}()

let bodyRecordMaxDate: Date = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var comps = DateComponents()
    comps.year = 2090; comps.month = 12; comps.day = 31
    comps.hour = 23; comps.minute = 59; comps.second = 59
    return cal.date(from: comps)!
}()

// MARK: - アプリ識別
enum AppConstants {
    static let productName      = "AzBodyNote"
    static let copyright        = "©2012 Azukid"
    static let unlockProductID  = "com.azukid.AzBodyNote.Unlock"

    // 通知名
    static let notificationRefreshAllViews = Notification.Name("RefreshAllViews")
    static let notificationRefetchAllData  = Notification.Name("RefetchAllDatabaseData")
    static let notificationAppDidBecomeActive = Notification.Name("AppDidBecomeActive")
}

// MARK: - 測定値の範囲・初期値（旧 E2_n* 定数群）
enum MeasureRange {
    // 血圧（上）mmHg  40以上は2桁で自動確定、30〜39は決定ボタンで確定
    static let bpHi = MeasureSpec(min: 30,  initVal: 120, max: 300, decimals: 0, autoCompleteFirstDigit: 4)
    // 血圧（下）mmHg  40以上は2桁で自動確定、20〜39は決定ボタンで確定
    static let bpLo = MeasureSpec(min: 20,  initVal: 80,  max: 200, decimals: 0, autoCompleteFirstDigit: 4)
    // 心拍数 bpm  30以上は2桁で自動確定、10〜29は決定ボタンで確定
    static let pulse = MeasureSpec(min: 10,  initVal: 65,  max: 200, decimals: 0, autoCompleteFirstDigit: 3)
    // 体重 x10 kg  (650 = 65.0 kg)  小数1桁入力で自動確定
    static let weight = MeasureSpec(min: 0,   initVal: 650, max: 2000, decimals: 1)
    // 体温 x10 ℃  (365 = 36.5 ℃)  小数1桁入力で自動確定
    static let temp = MeasureSpec(min: 310, initVal: 365, max: 429,  decimals: 1)
    // 体脂肪率 x10 % (235 = 23.5 %)  小数1桁入力で自動確定
    static let bodyFat = MeasureSpec(min: 0,   initVal: 235, max: 1000,  decimals: 1)
    // 骨格筋率 x10 % (285 = 28.5 %)  小数1桁入力で自動確定
    static let skMuscle = MeasureSpec(min: 0,   initVal: 285, max: 1000,  decimals: 1)
    // 脈圧 mmHg  血圧上下から計算される値でテンキー入力はしないため自動確定しきい値なし
    static let bpPp = MeasureSpec(min: 10,  initVal: 40,  max: 100,  decimals: 0)
    // BMI x10 (220 = 22.0)  小数1桁入力で自動確定
    static let bmi  = MeasureSpec(min: 100, initVal: 220, max: 500,  decimals: 1)
}

struct MeasureSpec {
    let min: Int
    let initVal: Int
    let max: Int
    let decimals: Int   // 小数点桁数（0=整数表示、1=小数1桁）

    /// テンキー自動確定用のしきい値（整数項目のみ）。
    /// 先頭桁がこの値以上なら2桁入力で確定、未満なら3桁入力で確定する。
    /// nil の項目（小数項目）は「小数第 decimals 桁まで入力されたら確定」で判定する。
    /// 例) 血圧上(30〜300, =4): 40〜99は2桁で確定、100〜300は3桁で確定、30〜39は自動確定しない。
    var autoCompleteFirstDigit: Int? = nil

    /// テンキーで入力途中の文字列 `text` を、これ以上桁を足す必要がなく自動確定してよいか判定する。
    /// - 小数項目: 小数点があり小数第 decimals 桁まで入力されたら true
    /// - 整数項目: 先頭桁 >= autoCompleteFirstDigit なら2桁、未満なら3桁入力で true
    ///   （下限帯は 2桁で止まり自動確定しないため false のまま。決定ボタンで確定する）
    func shouldAutoComplete(after text: String) -> Bool {
        guard !text.isEmpty else { return false }

        if decimals > 0 {
            // 小数項目: 小数点以降が decimals 桁に達したら確定
            guard let dot = text.firstIndex(of: ".") else { return false }
            let fractionDigits = text.distance(from: text.index(after: dot), to: text.endIndex)
            return fractionDigits >= decimals
        }

        // 整数項目: 先頭桁のしきい値で必要桁数を切り替える
        guard let threshold = autoCompleteFirstDigit,
              let firstDigit = text.first?.wholeNumberValue else { return false }
        let requiredDigits = firstDigit >= threshold ? 2 : 3
        return text.count >= requiredDigits
    }
}

// MARK: - 日付判定
enum DateOptConstants {
    static let aroundHour = 2   // 前後許容時間（旧 DateOpt_AroundHOUR）
    static let goalDateUTC = "2200-01-01T00:00:00"  // 目標値レコードの特殊日時
    static let maxDateUTC  = "2090-12-31T23:59:59"  // 最大入力許可日付
}

// MARK: - アプリカラー（旧 COLOR_* マクロ）
extension Color {
    static let azuki    = Color(red: 151/255, green:  80/255, blue:  77/255)
    static let azDark   = Color(red:  70/255, green:  70/255, blue:  70/255)
    static let azWhite  = Color(red: 250/255, green: 250/255, blue: 250/255)
    static let azBack   = Color(red: 220/255, green: 220/255, blue: 220/255)
    static let azEdit   = Color(red: 210/255, green: 220/255, blue: 210/255)
    static let azGoal   = Color(red: 210/255, green: 210/255, blue: 220/255)
}

// MARK: - グラフ・統計設定
enum GraphConstants {
    static let listPageLimit  = 50    // 旧 LIST_PAGE_LIMIT
    static let graphPageLimit = 50    // 旧 GRAPH_PAGE_LIMIT
    static let statDaysMax    = 70    // 旧 STAT_DAYS_MAX
    static let statDaysFree   = 7     // 旧 STAT_DAYS_FREE（無料制限）
    static let oneWidMin      = 30    // 旧 ONE_WID_MIN
    static let oneWidMax      = 80    // 旧 ONE_WID_MAX
}

// MARK: - グラフパネル種別（旧 EnumGraphs）
enum GraphKind: Int, CaseIterable, Identifiable, Codable {
    case bp           = 0
    case bpAvg        = 1  // 脈圧（グラフ専用）
    case pulse        = 2
    case temp         = 3
    case weight       = 4
    case bodyFat      = 6
    case skMuscle     = 7
    case bmi          = 8  // BMI（グラフ専用）
    case weightChange = 9  // 体重変化量（グラフ専用）

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .bp:           return "metric.bloodPressure"
        case .bpAvg:        return "metric.pulsePressure.calc"
        case .pulse:        return "metric.heartRate"
        case .temp:         return "metric.bodyTemp"
        case .weight:       return "metric.weight"
        case .bodyFat:      return "metric.bodyFat"
        case .skMuscle:     return "metric.skeletalMuscle"
        case .bmi:          return "metric.bmi.formula"
        case .weightChange: return "metric.weightChange"
        }
    }

    /// 記録入力画面にも対応するフィールドかどうか
    var isRecordField: Bool {
        switch self {
        case .bpAvg, .bmi, .weightChange: return false
        default: return true
        }
    }
}

enum StatSection: Int, CaseIterable, Identifiable {
    case bpJsh           = 0
    case bpRatio         = 1
    case bpDateOptCorr   = 2
    case bp24h           = 3
    case bpSummary       = 8   // 血圧 上下平均サマリー
    case weightSummary   = 4
    case tempSummary     = 5
    case temp24h         = 6
    case tempHist        = 7
    case weightBpScatter = 10  // 体重 × 血圧 相関散布図

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .bpJsh:           return "metric.bloodPressureDistribution"
        case .bpRatio:         return "metric.bpJshRatio"
        case .bpDateOptCorr:   return "metric.bpByCategory"
        case .bp24h:           return "metric.bp24hDistribution"
        case .bpSummary:       return "metric.bloodPressureSummary"
        case .weightSummary:   return "metric.weightSummary"
        case .tempSummary:     return "metric.bodyTempSummary"
        case .temp24h:         return "metric.bodyTemp24hDistribution"
        case .tempHist:        return "metric.bodyTempDistribution"
        case .weightBpScatter: return "metric.weightBpCorrelation"
        }
    }
}
