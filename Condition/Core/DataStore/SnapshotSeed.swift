// SnapshotSeed.swift
// fastlane snapshot 撮影時に、グラフや統計・症状の分析が映えるサンプル記録を投入する
//
// 【重要】DEBUG ビルド限定・起動引数 -FASTLANE_SNAPSHOT YES のときだけ動く
//   投入先は in-memory コンテナ（ModelContainer.shared 側で用意）なので、
//   実ユーザーの永続ストアや Release ビルドには一切影響しない

import Foundation
import SwiftData
import SwiftUI

@MainActor
enum SnapshotSeed {

    /// fastlane snapshot 実行中か（起動引数 -FASTLANE_SNAPSHOT YES）
    static var isActive: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT")
        #else
        return false
        #endif
    }

    /// 撮影時に固定する文字サイズ（起動引数 -SNAPSHOT_FONT_SCALE で指定）
    /// 指定がなければ nil（＝通常のユーザー設定に従う）
    /// UITest 側でデバイスを見て iPad のときだけ "large" 等を渡す運用
    static var forcedDynamicTypeSize: DynamicTypeSize? {
        #if DEBUG
        guard isActive,
              let raw = UserDefaults.standard.string(forKey: "SNAPSHOT_FONT_SCALE")
        else { return nil }
        // アプリの文字サイズ設定 AppFontScale と合わせる:
        //   標準 = .large / 大 = .xxxLarge / 特大 = .accessibility2
        switch raw.lowercased() {
        case "standard":              return .large
        case "large":                 return .xxxLarge       // アプリの「大」に一致
        case "xlarge", "xxxlarge":    return .accessibility2 // アプリの「特大」に一致
        case "accessibility", "a11y": return .accessibility2
        default:                      return nil
        }
        #else
        return nil
        #endif
    }

    /// 撮影用のサンプル記録を投入する。空のときだけ実行
    static func seedIfNeeded(context: ModelContext) {
        #if DEBUG
        // 既に記録があれば二重投入しない
        let existing = (try? context.fetchCount(FetchDescriptor<BodyRecord>())) ?? 0
        guard existing == 0 else { return }

        let cal = AppDateCalendar.gregorian
        let today = cal.startOfDay(for: Date())

        // 直近 60 日分を 1〜2 日おきに投入し、グラフ・統計に十分な密度を持たせる
        // 各測定値は自然な変動を持たせつつ、緩やかな改善傾向（体重・血圧が徐々に下がる）にする
        var day = 0
        while day <= 60 {
            let date = cal.date(byAdding: .day, value: -day, to: today) ?? today
            // 朝の記録（起床時）
            let morning = cal.date(bySettingHour: 7, minute: 30, second: 0, of: date) ?? date
            let r = BodyRecord(dateTime: morning, dateOpt: .cat01)

            // 経過に応じた緩やかな傾向 + 疑似ランダムな日々のゆらぎ
            let t = Double(60 - day) / 60.0            // 0（過去）→ 1（最近）
            let wave = sin(Double(day) * 0.7)          // 日ごとの上下

            // 血圧（改善傾向: 132/85 → 122/78 付近）
            r.nBpHi_mmHg = Int(132 - 10 * t + wave * 3)
            r.nBpLo_mmHg = Int(85 - 7 * t + wave * 2)
            // 心拍数（68 前後）
            r.nPulse_bpm = Int(68 + wave * 4)
            // 体温（36.4〜36.7℃ 付近、x10）
            r.nTemp_10c = Int(365 + wave * 2)
            // 体重（改善傾向: 66.5 → 64.0kg 付近、x10）
            r.nWeight_10Kg = Int(665 - 25 * t + wave * 3)
            // 体脂肪率（23.5 → 21.0% 付近、x10）
            r.nBodyFat_10p = Int(235 - 25 * t + wave * 4)
            // 骨格筋率（28.0 → 29.5% 付近、x10）
            r.nSkMuscle_10p = Int(280 + 15 * t + wave * 2)

            context.insert(r)

            // 過去ほど間隔をあける（最近は毎日、古い分は 2 日おき）
            day += (day < 20) ? 1 : 2
        }

        seedSymptoms(context: context, today: today, calendar: cal)

        try? context.save()
        #endif
    }

    #if DEBUG
    /// 分析3（症状サマリー・発症カレンダー・周期性・環境・直前の状況）が映える症状記録
    /// 頭痛を中心に数日おきに置き、環境・直前の状況・対処も付ける。
    /// 地名や観測所は言語ごとに合わないので、環境は手入力扱いにする
    private static func seedSymptoms(context: ModelContext, today: Date, calendar cal: Calendar) {
        let symptomDays = [0, 2, 4, 6, 9, 11, 13, 16, 18, 21, 24, 27, 29, 32, 35, 38, 41, 44, 47, 50, 53, 57]
        let severities: [SymptomSeverity] = [.moderate, .mild, .severe, .moderate, .mild]
        let triggerSets: [[String]] = [
            ["lackOfSleep"], ["screenTime", "posture"], ["stress"],
            [TriggerCatalog.nothingComesToMindID],
            ["cold"], ["alcohol"], ["lackOfSleep", "stress"], ["screenTime"],
        ]

        for (i, day) in symptomDays.enumerated() {
            let date = cal.date(byAdding: .day, value: -day, to: today) ?? today
            let hour = 8 + (i * 5) % 12
            let start = cal.date(bySettingHour: hour, minute: 15, second: 0, of: date) ?? date
            // 頭痛を多めにし、肩こり・めまいを混ぜる
            let symptomID: String
            switch i % 5 {
            case 1: symptomID = "stiffShoulder"
            case 3: symptomID = "dizziness"
            default: symptomID = "headache"
            }
            let record = SymptomRecord(startAt: start, symptomID: symptomID)
            record.severity = severities[i % severities.count]
            if i == 0 {
                // 最新の1件は継続中にして、一覧の「終息」ボタンも映す
                record.bOngoing = true
            } else {
                record.endAt = cal.date(byAdding: .hour, value: 1 + i % 4, to: start)
            }
            record.triggerIDs = triggerSets[i % triggerSets.count]
            switch symptomID {
            case "stiffShoulder": record.medicineIDs = ["stretch", "bath"]
            case "dizziness":     record.medicineIDs = ["rest"]
            default:              record.medicineIDs = i % 3 == 0 ? ["analgesic", "rest"] : ["analgesic"]
            }

            // 環境: 気温・湿度・気圧・24時間気圧差（x10 単位）
            record.weatherSource = .manual
            record.nTemp_10c = 220 + Int(sin(Double(day) * 0.5) * 50)
            record.bTempSet = true
            record.nHumidity_p = 50 + (i * 7) % 35
            record.bHumiditySet = true
            record.nPressure_10hpa = 10000 + (i * 37) % 160
            record.nPressureDelta24h_10hpa = 20 - (i * 13) % 70
            record.bPressureDelta24hSet = true
            context.insert(record)
        }
    }
    #endif
}
