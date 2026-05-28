// BodyRecord.swift
// SwiftData モデル（旧 E2record NSManagedObject 相当）

import Foundation
import SwiftData

@Model
final class BodyRecord {

    // MARK: - 日時（インデックス付き）
    @Attribute(.spotlight) var dateTime: Date = Date()

    // MARK: - メタデータ
    var nDateOpt: Int = DateOpt.cat02.rawValue       // DateOpt rawValue
    var nDataSource: Int = RecordDataSource.appInput.rawValue  // RecordDataSource rawValue
    var bCaution: Bool = false                       // 注意フラグ
var sNote1: String = ""
    var sNote2: String = ""
    var sEquipment: String = ""                  // 測定場所・装置

    // MARK: - 測定値（0 = 未入力）
    // 血圧（単位: mmHg）
    var nBpHi_mmHg: Int = 0
    var nBpLo_mmHg: Int = 0
    // 心拍数（単位: bpm）
    var nPulse_bpm: Int = 0
    // 体温（x10 ℃ 例: 365 = 36.5℃）
    var nTemp_10c: Int = 0
    // 体重（x10 kg 例: 650 = 65.0kg）
    var nWeight_10Kg: Int = 0
    // 体脂肪率（x10 % 例: 235 = 23.5%）
    var nBodyFat_10p: Int = 0
    // 骨格筋率（x10 % 例: 285 = 28.5%）
    var nSkMuscle_10p: Int = 0

    // MARK: - 初期化

    init(dateTime: Date = Date(), dateOpt: DateOpt = .cat02) {
        self.dateTime = dateTime
        self.nDateOpt = dateOpt.rawValue
    }

    // MARK: - 計算プロパティ（旧 nYearMM 相当）
    /// セクション表示用年月（例: 2024年3月 → 202403）
    @Transient var yearMonth: Int {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: dateTime)
        return (comps.year ?? 0) * 100 + (comps.month ?? 0)
    }

    /// 目標値レコードか（dateTime が goalDate と一致）
    @Transient var isGoalRecord: Bool {
        dateTime >= Self.goalDate
    }

    // MARK: - DateOpt アクセサ
    @Transient var dateOpt: DateOpt {
        get { DateOpt(rawValue: nDateOpt) ?? .cat02 }
        set { nDateOpt = newValue.rawValue }
    }

    // MARK: - DataSource アクセサ
    @Transient var dataSource: RecordDataSource {
        get { RecordDataSource(rawValue: nDataSource) ?? .appInput }
        set { nDataSource = newValue.rawValue }
    }

    // MARK: - 目標値用特殊日付（グローバル定数 bodyRecordGoalDate も参照）
    static let goalDate: Date = bodyRecordGoalDate
    static let maxInputDate: Date = bodyRecordMaxDate
}

// MARK: - 表示用ヘルパー
extension BodyRecord {
    var displayBpHi: String   { ValueFormatter.format(nBpHi_mmHg,   decimals: 0) }
    var displayBpLo: String   { ValueFormatter.format(nBpLo_mmHg,   decimals: 0) }
    var displayPulse: String  { ValueFormatter.format(nPulse_bpm,    decimals: 0) }
    var displayTemp: String   { ValueFormatter.format(nTemp_10c,     decimals: 1) }
    var displayWeight: String { ValueFormatter.format(nWeight_10Kg,  decimals: 1) }
    var displayBodyFat: String  { ValueFormatter.format(nBodyFat_10p,  decimals: 1) }
    var displaySkMuscle: String { ValueFormatter.format(nSkMuscle_10p, decimals: 1) }
}
