// SnapshotSeed.swift
// fastlane snapshot 撮影時に、グラフや統計が映えるサンプル記録を投入する
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

        let cal = Calendar.current
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

        try? context.save()
        #endif
    }
}
