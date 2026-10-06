// BodyRecord.swift
// SwiftData モデル（旧 E2record NSManagedObject 相当）

import Foundation
import SwiftData

@Model
final class BodyRecord {

    // MARK: - 日時
    // .spotlight は付けない（理由は SymptomRecord.startAt のコメントを参照）
    var dateTime: Date = Date()

    // MARK: - メタデータ
    var nDateOpt: Int = DateOpt.cat02.rawValue       // DateOpt rawValue
    var nDataSource: Int = RecordDataSource.appInput.rawValue  // RecordDataSource rawValue
    var bCaution: Bool = false                       // 注意フラグ
var sNote1: String = ""
    var sNote2: String = ""
    var sEquipment: String = ""                  // 測定場所・装置
    // 平均値の元になった最大5回分の測定値をJSONで保持
    var sMeasurementSamples: String = ""
    /// 環境シートの値をJSONで保持する（旧記録は空）
    var sEnvironment: String = ""

    // MARK: - 睡眠（起床時の区分だけに付ける補助データ）
    /// 睡眠開始日時（nil = 未入力）
    var dSleepStart: Date? = nil
    /// 睡眠時間（分、0 = 未入力）
    var nSleep_min: Int = 0

    // MARK: - 測定値（0 = 未入力）
    // 血圧（単位: mmHg）
    var nBpHi_mmHg: Int = 0
    var nBpLo_mmHg: Int = 0
    // 血圧の測定箇所（BpSide rawValue, 0=不明）
    var nBpSide: Int = 0
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

    // MARK: - BpSide アクセサ（血圧の測定箇所）
    @Transient var bpSide: BpSide {
        get { BpSide(rawValue: nBpSide) ?? .unknown }
        set { nBpSide = newValue.rawValue }
    }

    // MARK: - 目標値用特殊日付（グローバル定数 bodyRecordGoalDate も参照）
    static let goalDate: Date = bodyRecordGoalDate
    static let maxInputDate: Date = bodyRecordMaxDate
}

// MARK: - 複数回測定値

/// 平均値と一緒に保存する最大5回分の測定値
struct MeasurementSampleSet: Codable, Equatable {
    static let maxTrials = 5

    var bpHi: [Int?] = []
    var bpLo: [Int?] = []
    var pulse: [Int?] = []
    var weight: [Int?] = []
    var temp: [Int?] = []
    var bodyFat: [Int?] = []
    var skMuscle: [Int?] = []

    var trialCount: Int {
        [bpHi, bpLo, pulse, weight, temp, bodyFat, skMuscle]
            .map(\.count)
            .max() ?? 0
    }

    var hasAnyValue: Bool {
        [bpHi, bpLo, pulse, weight, temp, bodyFat, skMuscle]
            .contains { $0.contains { $0 != nil } }
    }

    /// 不正に長い配列を保存しないよう最大5回に揃え、各値を項目の範囲へ収める。
    /// 取り込んだ極端な値（Int.max 付近など）が残ると、編集画面の合計でオーバーフローする
    func limited() -> MeasurementSampleSet {
        MeasurementSampleSet(
            bpHi: Self.limited(bpHi, spec: MeasureRange.bpHi),
            bpLo: Self.limited(bpLo, spec: MeasureRange.bpLo),
            pulse: Self.limited(pulse, spec: MeasureRange.pulse),
            weight: Self.limited(weight, spec: MeasureRange.weight),
            temp: Self.limited(temp, spec: MeasureRange.temp),
            bodyFat: Self.limited(bodyFat, spec: MeasureRange.bodyFat),
            skMuscle: Self.limited(skMuscle, spec: MeasureRange.skMuscle)
        )
    }

    /// 平均値の取り込みと同じく、0 以下は未入力、それ以外は範囲内へ clamp する
    private static func limited(_ values: [Int?], spec: MeasureSpec) -> [Int?] {
        values.prefix(maxTrials).map { value in
            guard let value, value > 0 else { return nil }
            return min(max(value, spec.min), spec.max)
        }
    }
}

extension BodyRecord {
    /// 保存済みの複数回測定値を型付きデータとして読み書きする
    var measurementSampleSet: MeasurementSampleSet? {
        get {
            guard !sMeasurementSamples.isEmpty,
                  let data = sMeasurementSamples.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(MeasurementSampleSet.self, from: data),
                  decoded.hasAnyValue else { return nil }
            return decoded.limited()
        }
        set {
            guard let value = newValue?.limited(), value.hasAnyValue,
                  let data = try? JSONEncoder().encode(value),
                  let json = String(data: data, encoding: .utf8) else {
                sMeasurementSamples = ""
                return
            }
            sMeasurementSamples = json
        }
    }
}

// MARK: - 睡眠

/// 起床時の記録に付ける睡眠の値（開始日時と睡眠時間はそれぞれ未入力にできる）
struct SleepEntry: Equatable, Sendable {
    /// 睡眠を付ける区分（既定名「起床時」の区分に固定）
    static let dateOpt: DateOpt = .cat01
    /// 選択肢の刻み（分）
    static let stepMinutes = 30
    /// 睡眠開始を選べる範囲（記録日時から遡る時間）
    static let startLookbackMinutes = 18 * 60
    /// 睡眠開始の選択肢で最初に中央へ見せる位置（記録日時の8時間前）
    static let startFocusMinutes = 8 * 60
    /// 睡眠時間の選択肢で最初に中央へ見せる値（6時間）
    static let durationFocusMinutes = 6 * 60
    /// 「不眠」を表す睡眠時間（0 は未入力なので負の値で区別する）
    static let sleeplessMinutes = -1
    /// 「10時間超」を表す睡眠時間（選択肢の最大＋1刻み）
    static let overMaxMinutes = 10 * 60 + stepMinutes
    /// 刻みで選べる睡眠時間の最大
    static let maxStepMinutes = 10 * 60

    var start: Date? = nil
    /// 睡眠時間（分）。0 = 未入力、sleeplessMinutes = 不眠、overMaxMinutes = 10時間超
    var minutes: Int = 0

    var hasAnyValue: Bool { start != nil || minutes != 0 }

    /// 相関図などで使う睡眠時間（時間）。未入力は nil、不眠は 0
    var hours: Double? {
        switch minutes {
        case 0: return nil
        case Self.sleeplessMinutes: return 0
        default: return Double(minutes) / 60
        }
    }

    /// 選択肢の刻みへ揃える。開始は記録日時の範囲内、睡眠時間は 不眠〜10時間超 に収める
    func normalized(recordDate: Date) -> SleepEntry {
        var result = self
        if let start {
            let options = Self.startOptions(recordDate: recordDate)
            // 刻みの半分（秒）。先頭の刻みへ寄せられる範囲までは残す
            let halfStep = TimeInterval(Self.stepMinutes * 30)
            // 範囲外は捨て、範囲内は最も近い刻みへ寄せる
            if let first = options.first, first.addingTimeInterval(-halfStep) <= start, start <= recordDate {
                result.start = options.min { abs($0.timeIntervalSince(start)) < abs($1.timeIntervalSince(start)) }
            } else {
                result.start = nil
            }
        }
        result.minutes = Self.snappedMinutes(minutes)
        return result
    }

    /// 睡眠時間を選択肢の値へ寄せる
    static func snappedMinutes(_ minutes: Int) -> Int {
        if minutes == 0 || minutes == sleeplessMinutes { return minutes }
        if minutes < 0 { return 0 }
        if maxStepMinutes < minutes { return overMaxMinutes }
        let snapped = Int((Double(minutes) / Double(stepMinutes)).rounded()) * stepMinutes
        // 15分未満の睡眠は不眠として扱う
        return snapped == 0 ? sleeplessMinutes : snapped
    }

    /// 睡眠開始の選択肢（記録日時の18時間前〜記録日時、時計の00分・30分の刻み、古い順）
    static func startOptions(recordDate: Date) -> [Date] {
        let step = TimeInterval(stepMinutes * 60)
        let lower = recordDate.addingTimeInterval(-TimeInterval(startLookbackMinutes * 60))
        // 時差のある地域でも時計の刻みになるよう、現地時刻のずれを足してから切り上げる
        let offset = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: lower))
        let firstRaw = ((lower.timeIntervalSinceReferenceDate + offset) / step).rounded(.up) * step - offset
        var result: [Date] = []
        var value = Date(timeIntervalSinceReferenceDate: firstRaw)
        while value <= recordDate {
            result.append(value)
            value = value.addingTimeInterval(step)
        }
        return result
    }

    /// 睡眠開始の選択肢で、最初に中央へ見せる値（記録日時の8時間前に最も近い刻み）
    static func startFocus(recordDate: Date) -> Date? {
        let target = recordDate.addingTimeInterval(-TimeInterval(startFocusMinutes * 60))
        return startOptions(recordDate: recordDate)
            .min { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) }
    }

    /// 睡眠時間の選択肢（10時間超、10時間〜30分、不眠の順）
    static let durationOptions: [Int] =
        [overMaxMinutes]
        + stride(from: maxStepMinutes, through: stepMinutes, by: -stepMinutes).map { $0 }
        + [sleeplessMinutes]

    /// 睡眠時間の表示（例: 7時間30分、7時間、不眠、10時間超）
    static func durationText(_ minutes: Int) -> String {
        switch minutes {
        case 0:
            return String(localized: "sleep.notEntered")
        case sleeplessMinutes:
            return String(localized: "sleep.duration.sleepless")
        case overMaxMinutes...:
            return String(format: String(localized: "sleep.duration.overFormat"), maxStepMinutes / 60)
        default:
            if minutes < 60 {
                return String(format: String(localized: "sleep.duration.minutesFormat"), minutes)
            }
            if minutes % 60 == 0 {
                return String(format: String(localized: "sleep.duration.hoursFormat"), minutes / 60)
            }
            return String(format: String(localized: "sleep.duration.format"), minutes / 60, minutes % 60)
        }
    }

    /// 睡眠開始時刻の表示（端末の12/24時間表記に従う）
    static func startText(_ date: Date) -> String {
        let formatter = AppDateCalendar.formatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }
}

extension BodyRecord {
    /// 睡眠の値を型付きで読み書きする
    var sleepEntry: SleepEntry {
        get { SleepEntry(start: dSleepStart, minutes: nSleep_min) }
        set {
            dSleepStart = newValue.start
            nSleep_min = newValue.minutes
        }
    }
}

/// ヘルスケアの睡眠サンプル1件（HealthKit に依存しない形にしてテストできるようにする）
struct SleepInterval: Equatable, Sendable {
    let start: Date
    let end: Date
    /// true = 睡眠（段階を問わない）、false = ベッドにいた
    let isAsleep: Bool
}

/// ヘルスケアの睡眠サンプルから、起床時の記録に付ける1回分の睡眠を求める
enum SleepSessionLogic {
    /// 記録日時から遡って探す範囲（18時間）
    static let lookback: TimeInterval = 18 * 3600
    /// この間隔以内の中断は同じ睡眠として扱う（夜中に目が覚めた区間など）
    static let mergeGap: TimeInterval = 60 * 60

    /// - Returns: 範囲内で最も長い睡眠。見つからなければ nil
    static func mainSleep(from intervals: [SleepInterval], recordDate: Date) -> SleepEntry? {
        let windowStart = recordDate.addingTimeInterval(-lookback)
        // 範囲内へ切り詰める
        let clipped = intervals.compactMap { item -> SleepInterval? in
            let start = max(item.start, windowStart)
            let end = min(item.end, recordDate)
            guard start < end else { return nil }
            return SleepInterval(start: start, end: end, isAsleep: item.isAsleep)
        }
        // 睡眠の記録が無いとき（iPhone のみの利用者など）はベッドにいた時間で代用する
        let asleep = clipped.filter(\.isAsleep)
        let source = asleep.isEmpty ? clipped : asleep
        let merged = union(source.map { ($0.start, $0.end) })
        guard !merged.isEmpty else { return nil }

        // 中断が短い区間どうしを1回の睡眠にまとめる
        var sessions: [[(Date, Date)]] = []
        for range in merged {
            if let last = sessions.last?.last, range.0.timeIntervalSince(last.1) <= mergeGap {
                sessions[sessions.count - 1].append(range)
            } else {
                sessions.append([range])
            }
        }
        // 昼寝などより本睡眠を採るため最も長いものを選ぶ（同じ長さなら新しい方）
        let scored = sessions.map { session in
            (start: session[0].0, seconds: session.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) })
        }
        // 逆順にしてから最大を取ると、同じ長さのとき新しい方が残る
        guard let best = scored.reversed().max(by: { $0.seconds < $1.seconds }) else { return nil }
        let minutes = Int((best.seconds / 60).rounded())
        guard 0 < minutes else { return nil }
        return SleepEntry(start: best.start, minutes: min(minutes, 24 * 60))
    }

    /// 重なった区間を合わせる（複数の記録元による二重計上を防ぐ）
    private static func union(_ ranges: [(Date, Date)]) -> [(Date, Date)] {
        var result: [(Date, Date)] = []
        for range in ranges.sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, range.0 <= last.1 {
                result[result.count - 1].1 = max(last.1, range.1)
            } else {
                result.append(range)
            }
        }
        return result
    }
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
