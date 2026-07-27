// ConditionTests.swift

import Testing
import Foundation
import SwiftData
import HealthKit
@testable import Condition

// MARK: - 既存テスト

@Suite("ValueFormatter Tests")
struct ValueFormatterTests {

    @Test("整数値の変換")
    func integerFormat() {
        #expect(ValueFormatter.format(120, decimals: 0) == "120")
        #expect(ValueFormatter.format(0,   decimals: 0) == "")
        #expect(ValueFormatter.format(-1,  decimals: 0) == "")
    }

    @Test("小数1桁の変換")
    func decimal1Format() {
        #expect(ValueFormatter.format(650, decimals: 1) == "65.0")
        #expect(ValueFormatter.format(365, decimals: 1) == "36.5")
        #expect(ValueFormatter.format(235, decimals: 1) == "23.5")
    }
}

// AppSettings.shared.dateOptHourMap（UserDefaults 共有）を退避・復元するため直列化する
@Suite("DateOpt Tests", .serialized)
struct DateOptTests {

    @Test("autoDateOpt: 6時台は dateOptHourMap で設定された区分を返す")
    @MainActor
    func autoDateOptByHourMap() {
        let settings = AppSettings.shared
        // 共有設定（UserDefaults連動）を汚さないよう、テスト後に必ず元へ戻す
        let original = settings.dateOptHourMap
        defer { settings.dateOptHourMap = original }

        // 既存UserDefaultsに依存しないよう、24時間ぶんの既知マップを用意し6時台に cat01（起床時 既定）を割り当てる
        var map = Array(repeating: DateOpt.cat02.rawValue, count: 24)
        map[6] = DateOpt.cat01.rawValue
        settings.dateOptHourMap = map

        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 6; comps.minute = 30
        let date = cal.date(from: comps)!
        #expect(settings.autoDateOpt(for: date) == .cat01)
    }
}

@Suite("BodyRecord Tests")
struct BodyRecordTests {

    @Test("yearMonth 計算")
    func yearMonth() {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 15
        let date = cal.date(from: comps)!
        let record = BodyRecord(dateTime: date)
        #expect(record.yearMonth == 202403)
    }

    @Test("goalDate 判定")
    func goalDateDetection() {
        let normal = BodyRecord(dateTime: Date())
        let goal   = BodyRecord(dateTime: BodyRecord.goalDate)
        #expect(!normal.isGoalRecord)
        #expect(goal.isGoalRecord)
    }
}

// MARK: - 複数回測定テスト

@Suite("Measurement Sample Tests")
struct MeasurementSampleTests {

    @Test("測定値は項目ごとに最大5回へ制限される")
    func samplesAreLimitedToFiveTrials() {
        let record = BodyRecord()
        // 外部データから6回以上渡されても保存上限を超えないことを確認する
        record.measurementSampleSet = MeasurementSampleSet(
            bpHi: [120, 121, 122, 123, 124, 125],
            bpLo: [70, 71, 72, 73, 74, 75],
            pulse: [],
            weight: [],
            temp: [],
            bodyFat: [],
            skMuscle: []
        )

        #expect(record.measurementSampleSet?.bpHi == [120, 121, 122, 123, 124])
        #expect(record.measurementSampleSet?.bpLo == [70, 71, 72, 73, 74])
        #expect(record.measurementSampleSet?.trialCount == 5)
    }

    @Test("測定値が全て空なら通常記録として扱われる")
    func emptySamplesAreNotStored() {
        let record = BodyRecord()
        record.measurementSampleSet = MeasurementSampleSet(
            bpHi: [nil],
            bpLo: [nil],
            pulse: [],
            weight: [],
            temp: [],
            bodyFat: [],
            skMuscle: []
        )

        #expect(record.measurementSampleSet == nil)
        #expect(record.sMeasurementSamples.isEmpty)
    }

    @Test("壊れた測定値JSONは平均記録として扱わない")
    func corruptedSamplesAreIgnored() {
        let record = BodyRecord()
        record.sMeasurementSamples = "{broken-json"

        #expect(record.measurementSampleSet == nil)
    }

    @Test("空セルの初回操作はプレースホルダー値を確定する")
    func firstDialActionAcceptsPlaceholder() {
        let first = MeasurementSampleDialLogic.acceptedValue(
            currentValue: nil,
            placeholder: 120,
            proposedValue: 121,
            hasInputText: false
        )
        let second = MeasurementSampleDialLogic.acceptedValue(
            currentValue: 120,
            placeholder: 120,
            proposedValue: 121,
            hasInputText: false
        )

        #expect(first == 120)
        #expect(second == 121)
    }

    @Test("テンキー入力中とプレースホルダーなしでは操作値を採用する")
    func dialActionUsesProposedValueWithoutApplicablePlaceholder() {
        let typing = MeasurementSampleDialLogic.acceptedValue(
            currentValue: nil,
            placeholder: 120,
            proposedValue: 125,
            hasInputText: true
        )
        let noPlaceholder = MeasurementSampleDialLogic.acceptedValue(
            currentValue: nil,
            placeholder: nil,
            proposedValue: 130,
            hasInputText: false
        )

        #expect(typing == 125)
        #expect(noPlaceholder == 130)
    }

    @Test("編集直後は未変更で値や入力に差があると変更済みになる")
    func editChangeDetection() {
        let initial = MeasurementAverageChangeLogic.hasUnsavedChanges(
            isEditing: true,
            hasAnyValue: true,
            hasInputText: false,
            matchesInitialSnapshot: true
        )
        let valueChanged = MeasurementAverageChangeLogic.hasUnsavedChanges(
            isEditing: true,
            hasAnyValue: true,
            hasInputText: false,
            matchesInitialSnapshot: false
        )
        let typing = MeasurementAverageChangeLogic.hasUnsavedChanges(
            isEditing: true,
            hasAnyValue: true,
            hasInputText: true,
            matchesInitialSnapshot: true
        )

        #expect(!initial)
        #expect(valueChanged)
        #expect(typing)
    }

    @Test("記録編集ViewModelから平均値と各測定値を保存できる")
    @MainActor
    func recordEditViewModelStoresSamples() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let viewModel = RecordEditViewModel(mode: .addNew)
        viewModel.nBpHi_mmHg = 121
        viewModel.nBpLo_mmHg = 81
        viewModel.bpHiEnabled = true
        viewModel.bpLoEnabled = true
        viewModel.measurementSampleSet = MeasurementSampleSet(
            bpHi: [120, 122],
            bpLo: [80, 82],
            pulse: [],
            weight: [],
            temp: [],
            bodyFat: [],
            skMuscle: []
        )

        try viewModel.save(context: context)

        let saved = try #require(context.fetch(FetchDescriptor<BodyRecord>()).first)
        #expect(saved.nBpHi_mmHg == 121)
        #expect(saved.nBpLo_mmHg == 81)
        #expect(saved.measurementSampleSet?.bpHi == [120, 122])
        #expect(saved.measurementSampleSet?.bpLo == [80, 82])
    }
}

// MARK: - テスト用ヘルパー

/// インメモリ ModelContainer を生成する。各テストで隔離した SwiftData ストアを得る用途
@MainActor
private func makeInMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: BodyRecord.self, configurations: config)
}

/// テスト用に固定的なレコードを作って context に挿入し、save まで実行する
@MainActor
@discardableResult
private func seedRecord(
    _ context: ModelContext,
    daysAgo: Int = 0,
    bpHi: Int = 120,
    bpLo: Int = 78,
    pulse: Int = 65,
    weight10kg: Int = 650,
    dateOpt: DateOpt = .cat02,
    bpSide: BpSide = .unknown,
    note1: String = "",
    note2: String = "",
    device: String = ""
) throws -> BodyRecord {
    let cal = Calendar.current
    let date = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    let r = BodyRecord(dateTime: date, dateOpt: dateOpt)
    r.nBpHi_mmHg = bpHi
    r.nBpLo_mmHg = bpLo
    r.nPulse_bpm = pulse
    r.nWeight_10Kg = weight10kg
    r.bpSide = bpSide
    r.sNote1 = note1
    r.sNote2 = note2
    r.sEquipment = device
    context.insert(r)
    try context.save()
    return r
}

// MARK: - SwiftData 永続化テスト

@Suite("BodyRecord Persistence Tests")
struct BodyRecordPersistenceTests {

    @Test("挿入と取得：1件のレコードが正しく保存・取得される")
    @MainActor
    func insertAndFetchOne() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let inserted = try seedRecord(ctx, bpHi: 130, bpLo: 85, pulse: 72)

        let fetched = try ctx.fetch(FetchDescriptor<BodyRecord>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.nBpHi_mmHg == 130)
        #expect(fetched.first?.nBpLo_mmHg == 85)
        #expect(fetched.first?.nPulse_bpm == 72)
        #expect(fetched.first?.persistentModelID == inserted.persistentModelID)
    }

    @Test("大量挿入：100件のレコードが個別に保存される")
    @MainActor
    func bulkInsertCountsMatch() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        for i in 0..<100 {
            try seedRecord(ctx, daysAgo: i)
        }
        let fetched = try ctx.fetch(FetchDescriptor<BodyRecord>())
        #expect(fetched.count == 100)
    }

    @Test("更新：取得→変更→再取得で反映される")
    @MainActor
    func updateRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        try seedRecord(ctx, bpHi: 120)

        let target = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        target.nBpHi_mmHg = 140
        try ctx.save()

        let reloaded = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        #expect(reloaded.nBpHi_mmHg == 140)
    }

    @Test("削除：個別 delete 後に件数が減る")
    @MainActor
    func deleteOne() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        try seedRecord(ctx, daysAgo: 0)
        try seedRecord(ctx, daysAgo: 1)
        try seedRecord(ctx, daysAgo: 2)

        let all = try ctx.fetch(FetchDescriptor<BodyRecord>())
        ctx.delete(all[0])
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<BodyRecord>()).count == 2)
    }

    @Test("Predicate：日時で絞り込みが効く")
    @MainActor
    func predicateByDateRange() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        for i in 0..<10 {
            try seedRecord(ctx, daysAgo: i)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let desc = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime >= cutoff }
        )
        let recent = try ctx.fetch(desc)
        #expect(recent.count >= 3 && recent.count <= 4)
    }

    @Test("Predicate：目標値レコードは bodyRecordGoalDate で除外される")
    @MainActor
    func predicateExcludesGoalDate() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        try seedRecord(ctx)
        let goal = BodyRecord(dateTime: bodyRecordGoalDate, dateOpt: .cat02)
        ctx.insert(goal)
        try ctx.save()

        let desc = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime < bodyRecordGoalDate }
        )
        let normal = try ctx.fetch(desc)
        #expect(normal.count == 1)
        #expect(!normal[0].isGoalRecord)
    }

    @Test("ソート：dateTime 降順で並ぶ")
    @MainActor
    func sortByDateDesc() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        try seedRecord(ctx, daysAgo: 5)
        try seedRecord(ctx, daysAgo: 1)
        try seedRecord(ctx, daysAgo: 3)

        let desc = FetchDescriptor<BodyRecord>(
            sortBy: [SortDescriptor(\BodyRecord.dateTime, order: .reverse)]
        )
        let sorted = try ctx.fetch(desc)
        #expect(sorted.count == 3)
        #expect(sorted[0].dateTime > sorted[1].dateTime)
        #expect(sorted[1].dateTime > sorted[2].dateTime)
    }

    @Test("yearMonth 集計：同月内のレコードが同じ yearMonth を返す")
    @MainActor
    func yearMonthGrouping() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1
        comps.day = 5;  let d1 = cal.date(from: comps)!
        comps.day = 28; let d2 = cal.date(from: comps)!

        let a = BodyRecord(dateTime: d1); ctx.insert(a)
        let b = BodyRecord(dateTime: d2); ctx.insert(b)
        try ctx.save()

        #expect(a.yearMonth == 202601)
        #expect(b.yearMonth == 202601)
    }
}

// MARK: - JSON ラウンドトリップ

@Suite("RecordsJSONIO Round-Trip Tests")
struct JSONRoundTripTests {

    @Test("単一レコード：エクスポート→インポートで全フィールドが復元される")
    @MainActor
    func singleRecordRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let srcCtx = ModelContext(container)
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -1, to: Date())!
        let r = BodyRecord(dateTime: date, dateOpt: .cat04)
        r.nBpHi_mmHg = 132
        r.nBpLo_mmHg = 84
        r.nPulse_bpm = 71
        r.nTemp_10c = 365
        r.nWeight_10Kg = 712
        r.nBodyFat_10p = 220
        r.nSkMuscle_10p = 305
        r.sNote1 = "朝の測定"
        r.sNote2 = "やや疲労感"
        r.sEquipment = "Omron Connect"
        r.bCaution = true
        r.bpSide = .left
        srcCtx.insert(r)
        try srcCtx.save()

        let data = RecordsJSONIO.export(records: [r], style: .pretty)
        #expect(!data.isEmpty)

        let destContainer = try makeInMemoryContainer()
        let destCtx = ModelContext(destContainer)
        let result = try RecordsJSONIO.importJSON(data, into: destCtx)
        #expect(result.inserted == 1)
        #expect(result.updated == 0)

        let restored = try destCtx.fetch(FetchDescriptor<BodyRecord>()).first!
        #expect(restored.dateOpt == .cat04)
        #expect(restored.nBpHi_mmHg == 132)
        #expect(restored.nBpLo_mmHg == 84)
        #expect(restored.nPulse_bpm == 71)
        #expect(restored.nTemp_10c == 365)
        #expect(restored.nWeight_10Kg == 712)
        #expect(restored.nBodyFat_10p == 220)
        #expect(restored.nSkMuscle_10p == 305)
        #expect(restored.sNote1 == "朝の測定")
        #expect(restored.sNote2 == "やや疲労感")
        #expect(restored.sEquipment == "Omron Connect")
        #expect(restored.bCaution == true)
        #expect(restored.bpSide == .left)
        #expect(RecordsJSONIO.normalizedSecond(restored.dateTime) ==
                RecordsJSONIO.normalizedSecond(date))
    }

    @Test("複数回測定値：空欄を含む最大5回分が復元される")
    @MainActor
    func measurementSamplesRoundTrip() throws {
        let sourceContainer = try makeInMemoryContainer()
        let sourceContext = ModelContext(sourceContainer)
        let record = BodyRecord(dateTime: Date(), dateOpt: .cat02)
        // 平均値の元になった行構成を空欄も含めて保存する
        record.measurementSampleSet = MeasurementSampleSet(
            bpHi: [120, 122, nil, 121, 119],
            bpLo: [80, 82, nil, 81, 79],
            pulse: [65, 66, nil, 64, 65],
            weight: [],
            temp: [],
            bodyFat: [],
            skMuscle: []
        )
        sourceContext.insert(record)
        try sourceContext.save()

        let data = RecordsJSONIO.export(records: [record])
        let destinationContainer = try makeInMemoryContainer()
        let destinationContext = ModelContext(destinationContainer)
        try RecordsJSONIO.importJSON(data, into: destinationContext)

        let restored = try #require(
            destinationContext.fetch(FetchDescriptor<BodyRecord>()).first?.measurementSampleSet
        )
        #expect(restored.bpHi == [120, 122, nil, 121, 119])
        #expect(restored.bpLo == [80, 82, nil, 81, 79])
        #expect(restored.pulse == [65, 66, nil, 64, 65])
        #expect(restored.trialCount == 5)
    }

    @Test("複数レコード：エクスポート→インポートで件数と内容が一致する")
    @MainActor
    func multipleRecordsRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let srcCtx = ModelContext(container)
        var inputs: [BodyRecord] = []
        for i in 0..<10 {
            let r = try seedRecord(srcCtx, daysAgo: i, bpHi: 110 + i, bpLo: 70 + i, pulse: 60 + i)
            inputs.append(r)
        }

        let data = RecordsJSONIO.export(records: inputs)

        let destContainer = try makeInMemoryContainer()
        let destCtx = ModelContext(destContainer)
        let result = try RecordsJSONIO.importJSON(data, into: destCtx)
        #expect(result.inserted == 10)

        let restored = try destCtx.fetch(FetchDescriptor<BodyRecord>(
            sortBy: [SortDescriptor(\BodyRecord.dateTime)]
        ))
        let originals = inputs.sorted { $0.dateTime < $1.dateTime }
        #expect(restored.count == originals.count)
        for (r, o) in zip(restored, originals) {
            #expect(r.nBpHi_mmHg == o.nBpHi_mmHg)
            #expect(r.nBpLo_mmHg == o.nBpLo_mmHg)
            #expect(r.nPulse_bpm == o.nPulse_bpm)
        }
    }

    @Test("compact / pretty の出力サイズは異なるが、再インポート結果は等価")
    @MainActor
    func compactPrettyEquivalence() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        for i in 0..<5 {
            try seedRecord(ctx, daysAgo: i)
        }
        let records = try ctx.fetch(FetchDescriptor<BodyRecord>())

        let compact = RecordsJSONIO.export(records: records, style: .compact)
        let pretty  = RecordsJSONIO.export(records: records, style: .pretty)
        #expect(compact.count < pretty.count)

        let c1 = try makeInMemoryContainer(); let cx1 = ModelContext(c1)
        let c2 = try makeInMemoryContainer(); let cx2 = ModelContext(c2)
        _ = try RecordsJSONIO.importJSON(compact, into: cx1)
        _ = try RecordsJSONIO.importJSON(pretty,  into: cx2)
        let fromCompact = try cx1.fetch(FetchDescriptor<BodyRecord>())
        let fromPretty  = try cx2.fetch(FetchDescriptor<BodyRecord>())
        #expect(fromCompact.count == fromPretty.count)
    }

    @Test("envelope に exportDate と records キーが含まれる")
    @MainActor
    func envelopeStructure() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        try seedRecord(ctx)
        let records = try ctx.fetch(FetchDescriptor<BodyRecord>())

        let data = RecordsJSONIO.export(records: records)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["schemaVersion"] as? Int == RecordsJSONIO.currentSchemaVersion)
        #expect(json?["exportDate"] is String)
        #expect(json?["records"] is [[String: Any]])
    }

    @Test("categoryAppearances を指定すると JSON に含まれる")
    @MainActor
    func envelopeIncludesCategoryAppearances() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        try seedRecord(ctx)
        let records = try ctx.fetch(FetchDescriptor<BodyRecord>())

        let appearances = DateOpt.allCases.map { $0.defaultAppearance }
        let data = RecordsJSONIO.export(records: records, categoryAppearances: appearances)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = json?["categoryAppearances"] as? [[String: Any]]
        #expect(arr?.count == DateOpt.allCases.count)
    }

    @Test("区分表示マスタ：8区分の名称・アイコン・色が往復で維持される")
    @MainActor
    func categoryAppearancesRoundTrip() throws {
        let appearances = DateOpt.allCases.map { dateOpt in
            DateOptAppearance(
                dateOptRawValue: dateOpt.rawValue,
                nameJa: dateOpt == .cat08 ? "" : "区分\(dateOpt.rawValue + 1)",
                nameEn: dateOpt == .cat08 ? "" : "Cat\(dateOpt.rawValue + 1)",
                iconName: "\(dateOpt.rawValue + 1).square.fill",
                colorKey: dateOpt == .cat08 ? "gray" : "blue"
            )
        }
        let data = RecordsJSONIO.export(records: [], categoryAppearances: appearances)
        let container = try makeInMemoryContainer()
        let result = try RecordsJSONIO.importJSON(data, into: ModelContext(container))

        #expect(result.categoryAppearances == appearances)
        #expect(result.categoryAppearances?.count == DateOpt.allCases.count)
    }

    @Test("目標値と入力上限超過レコードはエクスポートされない")
    func specialDatesAreExcludedFromExport() throws {
        let valid = BodyRecord(dateTime: bodyRecordMaxDate)
        let overMax = BodyRecord(dateTime: bodyRecordMaxDate.addingTimeInterval(1))
        let goal = BodyRecord(dateTime: bodyRecordGoalDate)
        let data = RecordsJSONIO.export(records: [valid, overMax, goal])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let records = json?["records"] as? [[String: Any]]

        #expect(records?.count == 1)
    }
}

// MARK: - JSON インポート堅牢性

@Suite("RecordsJSONIO Robustness Tests")
struct JSONImportRobustnessTests {

    private struct ForcedSaveError: Error {}

    /// テスト用に最小限の JSON を組み立てる
    private static func envelopeJSON(_ records: [[String: Any]]) -> Data {
        let envelope: [String: Any] = [
            "exportDate": "2026-06-20T10:00:00+09:00",
            "records": records,
        ]
        return try! JSONSerialization.data(withJSONObject: envelope)
    }

    private static func isoString(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return iso.string(from: date)
    }

    @Test("不正な dateTime のレコードはスキップされる")
    @MainActor
    func malformedDateTimeIsSkipped() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)

        let data = Self.envelopeJSON([
            ["dateTime": "not a date", "bpSystolic": 120],
            ["dateTime": "2026-06-20T09:00:00+09:00", "bpSystolic": 130],
        ])
        let result = try RecordsJSONIO.importJSON(data, into: ctx)
        #expect(result.inserted == 1)
        #expect(result.skipped == 1)
        let fetched = try ctx.fetch(FetchDescriptor<BodyRecord>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.nBpHi_mmHg == 130)
    }

    @Test("範囲外の整数値は spec の min/max にクランプされる")
    @MainActor
    func intOutOfRangeIsClamped() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)

        let data = Self.envelopeJSON([
            [
                "dateTime": "2026-06-20T09:00:00+09:00",
                "bpSystolic": 9999,
                "bpDiastolic": 1,
                "heartRate": 250,
            ]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        #expect(r.nBpHi_mmHg == MeasureRange.bpHi.max)
        #expect(r.nBpLo_mmHg == MeasureRange.bpLo.min)
        #expect(r.nPulse_bpm == MeasureRange.pulse.max)
    }

    @Test("0 以下の値は 未入力(0) として扱われる")
    @MainActor
    func nonPositiveIsTreatedAsUnset() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)

        let data = Self.envelopeJSON([
            [
                "dateTime": "2026-06-20T09:00:00+09:00",
                "bpSystolic": -10,
                "bpDiastolic": 0,
                "weight": 0.0,
            ]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        #expect(r.nBpHi_mmHg == 0)
        #expect(r.nBpLo_mmHg == 0)
        #expect(r.nWeight_10Kg == 0)
    }

    @Test("小数測定値は ×10 整数化されつつ range に clamp される")
    @MainActor
    func decimalScaledAndClamped() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let data = Self.envelopeJSON([
            [
                "dateTime": "2026-06-20T09:00:00+09:00",
                "weight": 65.3,
                "bodyTemp": 36.6,
                "bodyFat": 999.9,
            ]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        #expect(r.nWeight_10Kg == 653)
        #expect(r.nTemp_10c == 366)
        #expect(r.nBodyFat_10p == MeasureRange.bodyFat.max)
    }

    @Test("同一日時（秒丸め）は更新され、二重挿入されない")
    @MainActor
    func sameDateSecondsCausesUpdate() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        try seedRecord(ctx, daysAgo: 0, bpHi: 120)
        let original = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        let date = RecordsJSONIO.normalizedSecond(original.dateTime).addingTimeInterval(0.5)
        let data = Self.envelopeJSON([
            ["dateTime": iso.string(from: date), "bpSystolic": 145],
        ])
        let result = try RecordsJSONIO.importJSON(data, into: ctx)
        #expect(result.inserted == 0)
        #expect(result.updated == 1)
        let after = try ctx.fetch(FetchDescriptor<BodyRecord>())
        #expect(after.count == 1)
        #expect(after.first?.nBpHi_mmHg == 145)
    }

    @Test("未知の conditionRaw は fallback として .cat02 になる")
    @MainActor
    func unknownConditionRawFallsBackToCat02() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let data = Self.envelopeJSON([
            [
                "dateTime": "2026-06-20T09:00:00+09:00",
                "conditionRaw": 999,
                "bpSystolic": 120,
            ]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        #expect(r.dateOpt == .cat02)
    }

    @Test("レガシー condition キー（category.wake 等）は対応区分にマップされる")
    @MainActor
    func legacyConditionKeyMapsToCategory() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let data = Self.envelopeJSON([
            ["dateTime": "2026-06-20T09:00:00+09:00", "condition": "category.wake"],
            ["dateTime": "2026-06-20T10:00:00+09:00", "condition": "category.bedtime"],
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let sorted = try ctx.fetch(FetchDescriptor<BodyRecord>(
            sortBy: [SortDescriptor(\BodyRecord.dateTime)]
        ))
        #expect(sorted.count == 2)
        #expect(sorted[0].dateOpt == .cat01)
        #expect(sorted[1].dateOpt == .cat04)
    }

    @Test("空 records 配列でもエラーにならず 0 件挿入")
    @MainActor
    func emptyRecordsArray() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let data = Self.envelopeJSON([])
        let result = try RecordsJSONIO.importJSON(data, into: ctx)
        #expect(result.inserted == 0)
        #expect(result.updated == 0)
    }

    @Test("壊れた JSON はエラーをスローする")
    @MainActor
    func corruptedJSONThrows() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let data = "this is not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try RecordsJSONIO.importJSON(data, into: ctx)
        }
    }

    @Test("文字列フィールドの前後空白・改行は除去される")
    @MainActor
    func stringTrimming() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let data = Self.envelopeJSON([
            [
                "dateTime": "2026-06-20T09:00:00+09:00",
                "memo1": "  メモ1  \n",
                "memo2": "\n\n メモ2\t",
                "device": "  Omron  ",
            ]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try ctx.fetch(FetchDescriptor<BodyRecord>()).first!
        #expect(r.sNote1 == "メモ1")
        #expect(r.sNote2 == "メモ2")
        #expect(r.sEquipment == "Omron")
    }

    @Test("入力上限日は受理し、それを超える日付と目標値日はスキップする")
    @MainActor
    func specialImportDatesAreValidated() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let data = Self.envelopeJSON([
            ["dateTime": Self.isoString(bodyRecordMaxDate), "bpSystolic": 120],
            ["dateTime": Self.isoString(bodyRecordMaxDate.addingTimeInterval(1)), "bpSystolic": 130],
            ["dateTime": Self.isoString(bodyRecordGoalDate), "bpSystolic": 140],
        ])

        let result = try RecordsJSONIO.importJSON(data, into: ctx)
        let fetched = try ctx.fetch(FetchDescriptor<BodyRecord>())
        #expect(result.inserted == 1)
        #expect(result.skipped == 2)
        #expect(fetched.count == 1)
        #expect(fetched.first?.dateTime == bodyRecordMaxDate)
    }

    @Test("旧JSONは受理し、未対応の将来schemaVersionは拒否する")
    @MainActor
    func schemaVersionCompatibility() throws {
        let legacyContainer = try makeInMemoryContainer()
        let legacyResult = try RecordsJSONIO.importJSON(
            Self.envelopeJSON([["dateTime": "2026-06-20T09:00:00+09:00"]]),
            into: ModelContext(legacyContainer)
        )
        #expect(legacyResult.inserted == 1)

        let futureJSON = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": RecordsJSONIO.currentSchemaVersion + 1,
            "records": [],
        ])
        let futureContainer = try makeInMemoryContainer()
        do {
            _ = try RecordsJSONIO.importJSON(futureJSON, into: ModelContext(futureContainer))
            Issue.record("未対応のschemaVersionが受理されました")
        } catch let error as RecordsJSONIO.IOError {
            #expect(error == .unsupportedSchemaVersion(RecordsJSONIO.currentSchemaVersion + 1))
        }
    }

    @Test("保存失敗時は挿入と既存更新をまとめてロールバックする")
    @MainActor
    func saveFailureRollsBackAllChanges() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let existing = try seedRecord(ctx, bpHi: 120)
        let existingDate = RecordsJSONIO.normalizedSecond(existing.dateTime)
        let newDate = existingDate.addingTimeInterval(-3_600)
        let data = Self.envelopeJSON([
            ["dateTime": Self.isoString(existingDate), "bpSystolic": 150],
            ["dateTime": Self.isoString(newDate), "bpSystolic": 130],
        ])

        do {
            _ = try RecordsJSONIO.importJSON(data, into: ctx) { _ in
                throw ForcedSaveError()
            }
            Issue.record("保存失敗がスローされませんでした")
        } catch is ForcedSaveError {
            let fetched = try ctx.fetch(FetchDescriptor<BodyRecord>())
            #expect(fetched.count == 1)
            #expect(fetched.first?.nBpHi_mmHg == 120)
        }
    }

    @Test("区分マスタの欠落・重複・範囲外値・不正表示値を正規化する")
    @MainActor
    func invalidCategoryAppearancesAreNormalized() throws {
        let envelope: [String: Any] = [
            "schemaVersion": RecordsJSONIO.currentSchemaVersion,
            "records": [],
            "categoryAppearances": [
                [
                    "dateOptRawValue": DateOpt.cat01.rawValue,
                    "nameJa": "  起床  ",
                    "nameEn": "  Wake  ",
                    "iconName": "invalid.symbol",
                    "colorKey": "invalid-color",
                ],
                [
                    "dateOptRawValue": DateOpt.cat01.rawValue,
                    "nameJa": "重複",
                    "nameEn": "Duplicate",
                    "iconName": "heart.fill",
                    "colorKey": "red",
                ],
                [
                    "dateOptRawValue": 999,
                    "nameJa": "範囲外",
                    "nameEn": "Unknown",
                    "iconName": "heart.fill",
                    "colorKey": "red",
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let container = try makeInMemoryContainer()
        let result = try RecordsJSONIO.importJSON(data, into: ModelContext(container))
        let appearances = try #require(result.categoryAppearances)
        let cat01 = try #require(appearances.first { $0.dateOptRawValue == DateOpt.cat01.rawValue })

        #expect(appearances.count == DateOpt.allCases.count)
        #expect(cat01.nameJa == "起床")
        #expect(cat01.nameEn == "Wake")
        #expect(cat01.iconName == DateOpt.cat01.defaultIcon)
        #expect(cat01.colorKey == DateOpt.cat01.defaultColorKey)
        #expect(appearances[DateOpt.cat02.rawValue] == DateOpt.cat02.defaultAppearance)
    }

    @Test("同一JSON内で同じ秒が重複した場合は最後の値を採用する")
    @MainActor
    func duplicateDatesInPayloadUseLastRecord() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let dateTime = "2026-06-20T09:00:00+09:00"
        let data = Self.envelopeJSON([
            ["dateTime": dateTime, "bpSystolic": 120],
            ["dateTime": dateTime, "bpSystolic": 145],
        ])

        let result = try RecordsJSONIO.importJSON(data, into: ctx)
        let fetched = try ctx.fetch(FetchDescriptor<BodyRecord>())
        #expect(result.inserted == 1)
        #expect(result.updated == 1)
        #expect(fetched.count == 1)
        #expect(fetched.first?.nBpHi_mmHg == 145)
    }
}

// MARK: - パフォーマンス／効率性

@Suite("RecordsJSONIO Performance Tests")
struct JSONImportPerformanceTests {

    @Test("1000件のエクスポート→インポート往復が許容時間内")
    @MainActor
    func bulkRoundTripPerformance() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        for i in 0..<1000 {
            try seedRecord(ctx, daysAgo: i, bpHi: 110 + (i % 50), bpLo: 70 + (i % 20))
        }
        let records = try ctx.fetch(FetchDescriptor<BodyRecord>())

        let start = Date()
        let data = RecordsJSONIO.export(records: records)
        let exportElapsed = Date().timeIntervalSince(start)
        // 1000 件のエクスポートは 2 秒以内
        #expect(exportElapsed < 2.0)

        let destContainer = try makeInMemoryContainer()
        let destCtx = ModelContext(destContainer)
        let importStart = Date()
        let result = try RecordsJSONIO.importJSON(data, into: destCtx)
        let importElapsed = Date().timeIntervalSince(importStart)
        // 1000 件のインポートも 5 秒以内（in-memory ストアで余裕がある想定）
        #expect(importElapsed < 5.0)
        #expect(result.inserted == 1000)
    }

    @Test("同じ JSON を二度インポートしても重複挿入されない（全件 update）")
    @MainActor
    func reimportingIsIdempotent() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        for i in 0..<50 {
            try seedRecord(ctx, daysAgo: i)
        }
        let records = try ctx.fetch(FetchDescriptor<BodyRecord>())
        let data = RecordsJSONIO.export(records: records)

        let destContainer = try makeInMemoryContainer()
        let destCtx = ModelContext(destContainer)
        let first = try RecordsJSONIO.importJSON(data, into: destCtx)
        #expect(first.inserted == 50)
        let second = try RecordsJSONIO.importJSON(data, into: destCtx)
        #expect(second.inserted == 0)
        #expect(second.updated == 50)

        let count = try destCtx.fetch(FetchDescriptor<BodyRecord>()).count
        #expect(count == 50)
    }
}

// MARK: - 血圧の測定箇所（左右）

@Suite("BpSide Tests")
struct BpSideTests {

    @Test("rawValue は保存互換のため固定（不明0/右1/左2）")
    func rawValuesAreStable() {
        #expect(BpSide.unknown.rawValue == 0)
        #expect(BpSide.right.rawValue == 1)
        #expect(BpSide.left.rawValue == 2)
    }

    @Test("allCases の並びは UI 表示順 [左, 不明, 右]")
    func allCasesOrder() {
        #expect(BpSide.allCases == [.left, .unknown, .right])
    }

    @Test("code は全言語共通の L/R（不明は中点）")
    func codeIsFixed() {
        #expect(BpSide.left.code == "L")
        #expect(BpSide.right.code == "R")
        #expect(BpSide.unknown.code == "・")
    }

    @Test("isDefined は不明のみ false")
    func isDefined() {
        #expect(BpSide.left.isDefined)
        #expect(BpSide.right.isDefined)
        #expect(!BpSide.unknown.isDefined)
    }

    @Test("BodyRecord.bpSide アクセサは nBpSide と往復する")
    func accessorRoundTrips() {
        let r = BodyRecord()
        #expect(r.bpSide == .unknown)   // 既定は不明
        r.bpSide = .right
        #expect(r.nBpSide == BpSide.right.rawValue)
        r.nBpSide = BpSide.left.rawValue
        #expect(r.bpSide == .left)
        // 不正な rawValue は不明にフォールバック
        r.nBpSide = 99
        #expect(r.bpSide == .unknown)
    }
}

// MARK: - 左右フラグ JSON 往復・インポート

@Suite("BpSide JSON Tests")
struct BpSideJSONTests {

    private static func envelopeJSON(_ records: [[String: Any]]) -> Data {
        let envelope: [String: Any] = [
            "exportDate": "2026-06-20T10:00:00+09:00",
            "records": records,
        ]
        return try! JSONSerialization.data(withJSONObject: envelope)
    }

    @Test("左右フラグはエクスポート→インポートで往復する", arguments: [BpSide.left, .right, .unknown])
    @MainActor
    func bpSideRoundTrips(_ side: BpSide) throws {
        let container = try makeInMemoryContainer()
        let srcCtx = ModelContext(container)
        let r = try seedRecord(srcCtx, daysAgo: 1, bpSide: side)

        let data = RecordsJSONIO.export(records: [r], style: .pretty)
        let destCtx = ModelContext(try makeInMemoryContainer())
        try RecordsJSONIO.importJSON(data, into: destCtx)

        let restored = try #require(try destCtx.fetch(FetchDescriptor<BodyRecord>()).first)
        #expect(restored.bpSide == side)
    }

    @Test("不明の左右フラグは JSON に bpSide キーを出力しない")
    @MainActor
    func unknownSideOmitsKey() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)
        let r = try seedRecord(ctx, bpSide: .unknown)

        let data = RecordsJSONIO.export(records: [r])
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("bpSide"))
    }

    @Test("血圧の無い記録にインポートで left/right が来ても不明に落とす")
    @MainActor
    func bpSideDroppedWhenNoBP() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)

        // 血圧値なし＋ bpSide=left → 血圧固有のため無視して不明
        let data = Self.envelopeJSON([
            [
                "dateTime": "2026-06-20T09:00:00+09:00",
                "heartRate": 70,
                "bpSide": "left",
            ]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try #require(try ctx.fetch(FetchDescriptor<BodyRecord>()).first)
        #expect(r.nBpHi_mmHg == 0)
        #expect(r.bpSide == .unknown)
    }

    @Test("未知の bpSide 文字列は不明として扱う")
    @MainActor
    func unknownSideStringIsUnknown() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)

        let data = Self.envelopeJSON([
            [
                "dateTime": "2026-06-20T09:00:00+09:00",
                "bpSystolic": 120,
                "bpSide": "middle",   // 未知の値
            ]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try #require(try ctx.fetch(FetchDescriptor<BodyRecord>()).first)
        #expect(r.bpSide == .unknown)
    }

    @Test("旧JSON（bpSide キー無し）は不明として読み込む")
    @MainActor
    func legacyJSONHasUnknownSide() throws {
        let container = try makeInMemoryContainer()
        let ctx = ModelContext(container)

        let data = Self.envelopeJSON([
            ["dateTime": "2026-06-20T09:00:00+09:00", "bpSystolic": 130, "bpDiastolic": 85]
        ])
        try RecordsJSONIO.importJSON(data, into: ctx)
        let r = try #require(try ctx.fetch(FetchDescriptor<BodyRecord>()).first)
        #expect(r.bpSide == .unknown)
    }
}

// MARK: - 左右フラグ 編集ViewModel

@Suite("BpSide RecordEditViewModel Tests")
struct BpSideViewModelTests {

    @Test("新規追加は常に左右不明（・）で開始する")
    @MainActor
    func addNewStartsUnknown() throws {
        let vm = RecordEditViewModel(mode: .addNew)
        #expect(vm.bpSide == .unknown)
    }

    @Test("血圧ありで保存すると選んだ左右が記録される")
    @MainActor
    func savingWithBPStoresSide() throws {
        let ctx = ModelContext(try makeInMemoryContainer())
        let vm = RecordEditViewModel(mode: .addNew)
        vm.bpHiEnabled = true
        vm.bpLoEnabled = true
        vm.nBpHi_mmHg = 120
        vm.nBpLo_mmHg = 80
        vm.bpSide = .left
        try vm.save(context: ctx)

        let saved = try #require(try ctx.fetch(FetchDescriptor<BodyRecord>()).first)
        #expect(saved.bpSide == .left)
    }

    @Test("血圧を両方OFFで保存すると左右は不明になる")
    @MainActor
    func savingWithoutBPForcesUnknown() throws {
        let ctx = ModelContext(try makeInMemoryContainer())
        let vm = RecordEditViewModel(mode: .addNew)
        vm.bpHiEnabled = false
        vm.bpLoEnabled = false
        vm.pulseEnabled = true
        vm.nPulse_bpm = 66
        vm.bpSide = .left   // 明示しても血圧が無いので無視される
        try vm.save(context: ctx)

        let saved = try #require(try ctx.fetch(FetchDescriptor<BodyRecord>()).first)
        #expect(saved.bpSide == .unknown)
    }

    @Test("既存レコードの編集は保存済みの左右を読み込む")
    @MainActor
    func editingLoadsRecordSide() throws {
        let ctx = ModelContext(try makeInMemoryContainer())
        let r = try seedRecord(ctx, bpSide: .right)
        let vm = RecordEditViewModel(mode: .edit(r))
        #expect(vm.bpSide == .right)
    }
}

// MARK: - HealthKit 変換（純粋ロジック）

@Suite("HealthKitSampleBuilder Tests")
struct HealthKitSampleBuilderTests {

    @Test("全項目0なら空配列")
    func emptyValuesProduceNoSamples() {
        #expect(HealthKitSampleBuilder.samples(from: HealthKitValues(date: Date())).isEmpty)
    }

    @Test("体脂肪率のみでも1件のサンプルになる")
    func bodyFatOnlyProducesSample() throws {
        let samples = HealthKitSampleBuilder.samples(from: HealthKitValues(date: Date(), bodyFat: 235))
        #expect(samples.count == 1)
        let q = try #require(samples.first as? HKQuantitySample)
        #expect(q.quantityType == HKQuantityType(.bodyFatPercentage))
        // ×10 の % (23.5%) → HKUnit.percent() は割合 0.235 で格納
        #expect(abs(q.quantity.doubleValue(for: .percent()) - 0.235) < 1e-9)
    }

    @Test("温度・体重・心拍の単位換算")
    func quantityConversions() throws {
        let samples = HealthKitSampleBuilder.samples(
            from: HealthKitValues(date: Date(), pulse: 72, temp: 365, weight: 650)
        )
        func value(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) throws -> Double {
            let s = try #require(samples.compactMap { $0 as? HKQuantitySample }
                .first { $0.quantityType == HKQuantityType(id) })
            return s.quantity.doubleValue(for: unit)
        }
        #expect(try value(.heartRate, HKUnit(from: "count/min")) == 72)
        #expect(abs(try value(.bodyTemperature, .degreeCelsius()) - 36.5) < 1e-9)   // ×10 → ℃
        #expect(abs(try value(.bodyMass, .gramUnit(with: .kilo)) - 65.0) < 1e-9)    // ×10 → kg
    }

    @Test("血圧は上下そろって Correlation 1件になる")
    func bloodPressureCorrelation() throws {
        let samples = HealthKitSampleBuilder.samples(from: HealthKitValues(date: Date(), bpHi: 120, bpLo: 80))
        #expect(samples.count == 1)
        let corr = try #require(samples.first as? HKCorrelation)
        let objs = corr.objects.compactMap { $0 as? HKQuantitySample }
        let sys = try #require(objs.first { $0.quantityType == HKQuantityType(.bloodPressureSystolic) })
        let dia = try #require(objs.first { $0.quantityType == HKQuantityType(.bloodPressureDiastolic) })
        #expect(sys.quantity.doubleValue(for: .millimeterOfMercury()) == 120)
        #expect(dia.quantity.doubleValue(for: .millimeterOfMercury()) == 80)
    }

    @Test("血圧は片方だけならサンプルにしない")
    func bloodPressureNeedsBothSides() {
        #expect(HealthKitSampleBuilder.samples(from: HealthKitValues(date: Date(), bpHi: 120)).isEmpty)
        #expect(HealthKitSampleBuilder.samples(from: HealthKitValues(date: Date(), bpLo: 80)).isEmpty)
    }

    @Test("objectUUIDs は Correlation 配下の血圧サンプルも含む")
    func objectUUIDsIncludeCorrelationMembers() throws {
        let samples = HealthKitSampleBuilder.samples(
            from: HealthKitValues(date: Date(), bpHi: 120, bpLo: 80, pulse: 72)
        )
        let corr = try #require(samples.compactMap { $0 as? HKCorrelation }.first)
        let uuids = HealthKitSampleBuilder.objectUUIDs(in: samples)
        // correlation 自身 + systolic + diastolic + heartRate = 4
        #expect(uuids.contains(corr.uuid))
        for obj in corr.objects { #expect(uuids.contains(obj.uuid)) }
        #expect(uuids.count == 4)
    }
}

// MARK: - DateOptEstimator（区分推定）

// DateOptAppearanceStore（UserDefaults 共有）を退避・復元するため、並列実行での状態競合を避けて直列化する
@Suite("DateOptEstimator Tests", .serialized)
struct DateOptEstimatorTests {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c) ?? Date()
    }
    private func rec(_ opt: DateOpt, _ date: Date) -> BodyRecord {
        BodyRecord(dateTime: date, dateOpt: opt)
    }
    private func hourMap(all opt: DateOpt) -> [Int] {
        Array(repeating: opt.rawValue, count: 24)
    }

    /// 区分マスタ（定義済み/未定義）を明示的に固定してからブロックを実行し、
    /// 端末の UserDefaults 状態に依存せずテストを安定させる。
    /// - definedOnly: 定義済みにしたい区分。ここに無い区分は名称を空にして未定義化する。
    private func withDateOptMaster(
        definedOnly: [DateOpt],
        _ body: () throws -> Void
    ) rethrows {
        let original = DateOptAppearanceStore.appearances()
        defer { DateOptAppearanceStore.save(original) }

        let fixed: [DateOptAppearance] = DateOpt.allCases.map { opt in
            var appearance = opt.defaultAppearance
            if !definedOnly.contains(opt) {
                // 名称を空にして未定義化する（isDefined は名称の有無で判定される）
                appearance.nameJa = ""
                appearance.nameEn = ""
            }
            return appearance
        }
        DateOptAppearanceStore.save(fixed)
        try body()
    }

    @Test("90日より古い履歴は加点されない")
    func historyCutoffAt90Days() {
        let reference = date(2026, 6, 15, 12, 0)
        let cal = Calendar.current
        let inside  = cal.date(byAdding: .day, value: -89, to: reference) ?? reference
        let outside = cal.date(byAdding: .day, value: -91, to: reference) ?? reference
        let result = DateOptEstimator.estimateResult(
            from: [rec(.cat01, inside), rec(.cat03, outside)],
            targetDate: reference, hourMap: hourMap(all: .cat02), referenceDate: reference
        )
        #expect((result.scores[.cat01] ?? 0) > 0)   // 89日前は加点される
        #expect(result.scores[.cat03] == 0)          // 91日前は集計対象外
    }

    @Test("時刻差は日をまたいで最短側で評価する")
    func timeProximityIsCircularAcrossMidnight() {
        let reference = date(2026, 6, 15, 1, 0)   // 01:00
        // 同一日の 23:00(cat01)と 12:00(cat03)。曜日・新しさは同条件なので時刻差だけが効く
        let near = date(2026, 6, 10, 23, 0)
        let far  = date(2026, 6, 10, 12, 0)
        let result = DateOptEstimator.estimateResult(
            from: [rec(.cat01, near), rec(.cat03, far)],
            targetDate: reference, hourMap: hourMap(all: .cat02), referenceDate: reference
        )
        // 23:00 は 01:00 と circular 120分 → 12:00(660分)より高スコア
        #expect((result.scores[.cat01] ?? 0) > (result.scores[.cat03] ?? 0))
    }

    @Test("最大区分が僅差ならマトリクスの既定へ戻す")
    func tiedTopScoresFallBackToMatrix() {
        let reference = date(2026, 6, 15, 9, 0)
        let t1 = date(2026, 6, 8, 9, 0)
        let t2 = date(2026, 6, 1, 9, 0)
        // cat01 と cat03 を同一日時で積み、完全同点にする
        let records = [rec(.cat01, t1), rec(.cat01, t2), rec(.cat03, t1), rec(.cat03, t2)]
        let selected = DateOptEstimator.estimate(
            from: records, targetDate: reference, hourMap: hourMap(all: .cat02), referenceDate: reference
        )
        // 僅差判定でマトリクス既定 cat02 へ戻る
        #expect(selected == .cat02)
    }

    @Test("未定義区分の履歴は選ばれない")
    func undefinedDivisionIsNeverSelected() {
        // 端末の区分マスタに依存しないよう cat01〜cat06 のみ定義済みに固定し、cat07 は未定義にする
        withDateOptMaster(definedOnly: [.cat01, .cat02, .cat03, .cat04, .cat05, .cat06]) {
            #expect(!DateOpt.cat07.isDefined, "前提: cat07 は未定義に固定")
            let reference = date(2026, 6, 15, 9, 0)
            let t = date(2026, 6, 14, 9, 0)
            let cal = Calendar.current
            // cat07 を大量に積んでも、未定義なので選ばれない
            let records = (0..<5).map { rec(.cat07, cal.date(byAdding: .minute, value: -$0, to: t) ?? t) }
            let result = DateOptEstimator.estimateResult(
                from: records, targetDate: reference, hourMap: hourMap(all: .cat02), referenceDate: reference
            )
            #expect(result.selected != .cat07)
            #expect(result.scores[.cat07] == nil)   // 未定義区分はスコア表に存在しない
            #expect(result.selected == .cat02)       // 定義済みのマトリクス既定へ落ち着く
        }
    }

    @Test("hourMap が不正でも未定義区分を返さない")
    func invalidHourMapReturnsDefinedOption() {
        withDateOptMaster(definedOnly: [.cat01, .cat02, .cat03, .cat04, .cat05, .cat06]) {
            let target = date(2026, 6, 15, 12, 0)
            let invalidMaps: [[Int]] = [
                [],                                                  // 空
                Array(repeating: 999, count: 24),                   // 範囲外 rawValue
                [0],                                                // 短すぎる
                Array(repeating: DateOpt.cat07.rawValue, count: 24) // 未定義区分を指す
            ]
            for map in invalidMaps {
                let opt = DateOptEstimator.estimate(from: [], targetDate: target, hourMap: map, referenceDate: target)
                #expect(opt.isDefined, "hourMap=\(map.prefix(3)) で未定義区分が返った")
            }
        }
    }
}

// MARK: - 全区分未使用の自動修復（AppSettings の不変条件）

@Suite("ensuringAtLeastOneDefined Tests")
@MainActor
struct EnsuringAtLeastOneDefinedTests {

    /// 指定区分だけ定義済み（既定名）にし、それ以外は名称を空にして未定義化した appearance 群
    private func appearances(definedOnly: [DateOpt]) -> [DateOptAppearance] {
        DateOpt.allCases.map { opt in
            var a = opt.defaultAppearance
            if !definedOnly.contains(opt) { a.nameJa = ""; a.nameEn = "" }
            return a
        }
    }

    @Test("1区分でも定義済みならそのまま返す（修復しない）")
    func keepsWhenAtLeastOneDefined() {
        let input = appearances(definedOnly: [.cat03])
        let result = AppSettings.ensuringAtLeastOneDefined(input, previouslyDefined: input)
        #expect(result == input)
    }

    @Test("全未使用なら直前まで定義済みだった区分を既定へ戻す")
    func restoresPreviouslyDefinedWhenAllUndefined() throws {
        let allUndefined = appearances(definedOnly: [])
        // 直前は cat04 が定義済みだった
        let previous = appearances(definedOnly: [.cat04])

        let result = AppSettings.ensuringAtLeastOneDefined(allUndefined, previouslyDefined: previous)
        // 少なくとも1区分が定義済みに戻る
        #expect(result.contains { $0.isDefined })
        // 戻ったのは cat04（直前に定義済みだった区分）で、既定名になっている
        let restored = try #require(result.first { $0.dateOptRawValue == DateOpt.cat04.rawValue })
        #expect(restored.isDefined)
        #expect(restored.nameJa == DateOpt.cat04.defaultNameJa)
    }

    @Test("直前も全未使用なら cat01 を既定へ戻す")
    func fallsBackToCat01WhenNoPreviousDefined() {
        let allUndefined = appearances(definedOnly: [])
        let result = AppSettings.ensuringAtLeastOneDefined(allUndefined, previouslyDefined: allUndefined)
        #expect(result.contains { $0.isDefined })
        let cat01 = result.first { $0.dateOptRawValue == DateOpt.cat01.rawValue }
        #expect(cat01?.isDefined == true)
    }

    @Test("修復結果は必ず1区分以上が定義済みになる（冪等の前提）")
    func repairedAlwaysHasDefined() {
        let allUndefined = appearances(definedOnly: [])
        let result = AppSettings.ensuringAtLeastOneDefined(allUndefined, previouslyDefined: allUndefined)
        // もう一度通しても定義済みが保たれ、追加修復は起きない（＝didSet の再帰が止まる）
        let again = AppSettings.ensuringAtLeastOneDefined(result, previouslyDefined: result)
        #expect(again == result)
    }
}

// MARK: - MigrationService（旧DB→SwiftData 移行の純粋ロジック）

@Suite("MigrationService 重複判定 Tests")
@MainActor
struct MigrationClassifyRowsTests {

    private func row(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0, subsec: Double = 0) -> [String: Any] {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        let base = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return ["dateTime": base.addingTimeInterval(subsec)]
    }

    @Test("既存の秒と重複する行はスキップされる")
    func skipsRowsMatchingExistingSeconds() {
        let r = row(2024, 3, 15, 8, 0, 0)
        let existingDate = r["dateTime"] as! Date
        let existing: Set<Date> = [MigrationService.normalizedSecond(existingDate)]

        let result = MigrationService.classifyRows([r], existingSeconds: existing)
        #expect(result.toInsert.isEmpty)
        #expect(result.skipped == 1)
    }

    @Test("移行元内の同一秒重複は1件だけ挿入する（subsecond のズレを吸収）")
    func dedupesWithinSourceBySecond() {
        // 同じ 08:00:00 で subsecond だけ違う3行 → 1件だけ挿入、2件スキップ
        let rows = [
            row(2024, 3, 15, 8, 0, 0, subsec: 0.0),
            row(2024, 3, 15, 8, 0, 0, subsec: 0.4),
            row(2024, 3, 15, 8, 0, 0, subsec: 0.9),
        ]
        let result = MigrationService.classifyRows(rows, existingSeconds: [])
        #expect(result.toInsert.count == 1)
        #expect(result.skipped == 2)
    }

    @Test("異なる秒の行はすべて挿入される")
    func keepsDistinctSeconds() {
        let rows = [
            row(2024, 3, 15, 8, 0, 0),
            row(2024, 3, 15, 8, 0, 1),
            row(2024, 3, 15, 8, 1, 0),
        ]
        let result = MigrationService.classifyRows(rows, existingSeconds: [])
        #expect(result.toInsert.count == 3)
        #expect(result.skipped == 0)
    }

    @Test("目標値レコード（goalDate 以降）は goalRows へ振り分け、重複判定の対象にしない")
    func goalRecordsGoToGoalRows() {
        let goal: [String: Any] = ["dateTime": BodyRecord.goalDate]
        let normal = row(2024, 3, 15, 8, 0, 0)
        let result = MigrationService.classifyRows([goal, normal], existingSeconds: [])
        #expect(result.goalRows.count == 1)
        #expect(result.toInsert.count == 1)
        #expect(result.skipped == 0)
    }

    @Test("dateTime が無い行は無視される")
    func rowsWithoutDateAreIgnored() {
        let bad: [String: Any] = ["nDateOpt": 3]
        let good = row(2024, 3, 15, 8, 0, 0)
        let result = MigrationService.classifyRows([bad, good], existingSeconds: [])
        #expect(result.toInsert.count == 1)
        #expect(result.goalRows.isEmpty)
    }

    @Test("途中保存後の再試行を模した2回目の分類でも既存分は重複扱いになる")
    func retainsIdempotencyAcrossRuns() {
        let rows = [
            row(2024, 3, 15, 8, 0, 0),
            row(2024, 3, 15, 9, 0, 0),
        ]
        // 1回目: 何も存在しない
        let first = MigrationService.classifyRows(rows, existingSeconds: [])
        #expect(first.toInsert.count == 2)

        // 2回目: 1件だけ挿入済み（途中でクラッシュ→再試行）を模す
        let alreadyInserted = MigrationService.normalizedSecond(rows[0]["dateTime"] as! Date)
        let second = MigrationService.classifyRows(rows, existingSeconds: [alreadyInserted])
        #expect(second.toInsert.count == 1)
        #expect(second.skipped == 1)
    }
}

@Suite("MigrationService アーカイブ順序 Tests")
struct MigrationArchiveTests {

    /// 実ファイルは作らず、FileMover を注入して move の呼び出し順序と件数だけを検証する。
    /// テストは @MainActor 上で直列に走るため、共有可変状態は @unchecked Sendable で扱う。
    private final class MoveRecorder: @unchecked Sendable {
        var moves: [(String, String)] = []
        var failMainMove = false
        var existing: Set<String>

        init(existing: Set<String>) { self.existing = existing }

        func mover(mainPath: String) -> MigrationService.FileMover {
            MigrationService.FileMover(
                fileExists: { [self] in existing.contains($0) },
                move: { [self] src, dst in
                    if failMainMove && src.path == mainPath {
                        throw NSError(domain: "test", code: 1)
                    }
                    moves.append((src.lastPathComponent, dst.lastPathComponent))
                }
            )
        }
    }

    @Test("主ファイル移動成功後は補助ファイル(-shm/-wal)も移動する")
    @MainActor
    func movesAuxWhenMainSucceeds() {
        let base = "/tmp/AzBodyNote.sqlite"
        let url = URL(fileURLWithPath: base)
        let rec = MoveRecorder(existing: [base, base + "-shm", base + "-wal"])

        let ok = MigrationService().archiveOldStore(at: url, using: rec.mover(mainPath: base))
        #expect(ok)
        // 主ファイルが最初、その後に -shm/-wal（順不同許容せず定義順）
        #expect(rec.moves.count == 3)
        #expect(rec.moves.first?.0 == "AzBodyNote.sqlite")
        let auxMoved = Set(rec.moves.dropFirst().map(\.0))
        #expect(auxMoved == ["AzBodyNote.sqlite-shm", "AzBodyNote.sqlite-wal"])
    }

    @Test("主ファイル移動失敗時は false を返し WAL/SHM を移動しない")
    @MainActor
    func doesNotMoveAuxWhenMainFails() {
        let base = "/tmp/AzBodyNote.sqlite"
        let url = URL(fileURLWithPath: base)
        let rec = MoveRecorder(existing: [base, base + "-shm", base + "-wal"])
        rec.failMainMove = true

        let ok = MigrationService().archiveOldStore(at: url, using: rec.mover(mainPath: base))
        #expect(!ok)
        // 主ファイル移動が失敗したので、補助ファイルには一切触れない
        #expect(rec.moves.isEmpty)
    }

    @Test("主ファイルが無ければ退避済み扱いで true（補助のみ追従）")
    @MainActor
    func treatsMissingMainAsArchived() {
        let base = "/tmp/AzBodyNote.sqlite"
        let url = URL(fileURLWithPath: base)
        // 主ファイルは既に無く、WAL だけ残っているケース
        let rec = MoveRecorder(existing: [base + "-wal"])

        let ok = MigrationService().archiveOldStore(at: url, using: rec.mover(mainPath: base))
        #expect(ok)
        #expect(rec.moves.map(\.0) == ["AzBodyNote.sqlite-wal"])
    }
}

// MARK: - HealthKit インポート結果の保持フィルタ（純粋ロジック）

@Suite("HealthKit retainedImportValues Tests")
@MainActor
struct HealthKitRetainTests {

    @Test("体脂肪率だけのレコードも保持される")
    func bodyFatOnlyIsRetained() {
        let v = HealthKitValues(date: Date(), bodyFat: 235)
        let result = HealthKitService.retainedImportValues([v], hiddenFields: [])
        #expect(result.count == 1)
        #expect(result.first?.bodyFat == 235)
    }

    @Test("全項目0のレコードは落ちる")
    func emptyRecordIsDropped() {
        let v = HealthKitValues(date: Date())
        #expect(HealthKitService.retainedImportValues([v], hiddenFields: []).isEmpty)
    }

    @Test("体脂肪率が非表示なら体脂肪率だけのレコードは落ちる")
    func hiddenBodyFatDropsBodyFatOnlyRecord() {
        let v = HealthKitValues(date: Date(), bodyFat: 235)
        let result = HealthKitService.retainedImportValues([v], hiddenFields: [GraphKind.bodyFat.rawValue])
        #expect(result.isEmpty)
    }

    @Test("結果は日時昇順に並ぶ")
    func resultsSortedByDate() {
        let cal = Calendar.current
        let base = Date()
        let later   = HealthKitValues(date: cal.date(byAdding: .minute, value: 10, to: base)!, pulse: 70)
        let earlier = HealthKitValues(date: base, pulse: 72)
        let result = HealthKitService.retainedImportValues([later, earlier], hiddenFields: [])
        #expect(result.map(\.date) == [earlier.date, later.date])
    }

    @Test("削除しきれなかった分のレコードは取り込まない（記録の復活を防ぐ）")
    func excludedMinuteIsNotImported() {
        // 削除保留が残る分と、別の分の正常レコード
        let excludedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let keptDate     = excludedDate.addingTimeInterval(120)   // 2分後 → 別の分
        let excluded = HealthKitValues(date: excludedDate, weight: 650)
        let kept     = HealthKitValues(date: keptDate, weight: 651)

        let result = HealthKitService.retainedImportValues(
            [excluded, kept],
            hiddenFields: [],
            excludingMinuteKeys: [HealthKitService.minuteKey(excludedDate)]
        )
        #expect(result.map(\.date) == [keptDate])
    }

    @Test("同じ分の別秒サンプルと統合され代表日時がズレても除外される（分単位除外）")
    func excludedMinuteMatchesDespiteRepresentativeDateShift() {
        // 削除保留は 10:00:30 の体重。統合後の代表日時は同じ分の別秒（10:00:10 の心拍）へズレている。
        // 代表日時が保留の秒と一致しなくても、同じ「分」なので除外されなければならない。
        let deletedWeightDate = Date(timeIntervalSince1970: 1_700_000_030)   // 10:00:30 相当
        let mergedRepresentative = Date(timeIntervalSince1970: 1_700_000_010) // 10:00:10 相当（統合後の代表）
        // 統合済みレコード（代表日時 10:00:10、心拍と体重が同居）
        let merged = HealthKitValues(date: mergedRepresentative, pulse: 72, weight: 650)

        let result = HealthKitService.retainedImportValues(
            [merged],
            hiddenFields: [],
            excludingMinuteKeys: [HealthKitService.minuteKey(deletedWeightDate)]
        )
        // 同じ分なので、代表日時がズレていても丸ごと除外される（体重の再取り込みを防ぐ）
        #expect(result.isEmpty)
    }
}

// MARK: - 記録日時の編集で旧 HealthKit 日時を削除する判定（純粋ロジック）

@Suite("staleHealthKitDate Tests")
@MainActor
struct StaleHealthKitDateTests {

    @Test("日時を変更したら旧日時が削除対象になる")
    func changedDateProducesStaleDate() {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let new = Date(timeIntervalSince1970: 2_000_000)
        #expect(RecordEditViewModel.staleHealthKitDate(previousDate: old, newDate: new) == old)
    }

    @Test("日時が変わらなければ削除不要（nil）")
    func unchangedDateProducesNil() {
        let d = Date(timeIntervalSince1970: 1_000_000)
        #expect(RecordEditViewModel.staleHealthKitDate(previousDate: d, newDate: d) == nil)
    }

    @Test("旧日時が無い（新規追加）なら削除不要（nil）")
    func noPreviousDateProducesNil() {
        #expect(RecordEditViewModel.staleHealthKitDate(previousDate: nil, newDate: Date()) == nil)
    }
}

// MARK: - HealthKit 削除対象日時の判定（記録削除・再試行の前提）

// AppSettings.shared（UserDefaults 共有）を退避・復元するため直列化する
@Suite("appWrittenDateForDeletion Tests", .serialized)
@MainActor
struct AppWrittenDeletionTests {

    /// HK 設定を退避・復元しつつブロックを実行する
    private func withHKSettings(enabled: Bool, direction: HKSyncDirection, _ body: () -> Void) {
        let s = AppSettings.shared
        let savedEnabled = s.hkEnabled
        let savedDirection = s.hkDirection
        defer { s.hkEnabled = savedEnabled; s.hkDirection = savedDirection }
        s.hkEnabled = enabled
        s.hkDirection = direction.rawValue
        body()
    }

    private func record(source: RecordDataSource, at date: Date = Date()) -> BodyRecord {
        let r = BodyRecord(dateTime: date)
        r.dataSource = source
        return r
    }

    @Test("書込許可あり・アプリ入力レコードは日時を返す")
    func appInputReturnsDate() {
        let date = Date(timeIntervalSince1970: 1_500_000)
        withHKSettings(enabled: true, direction: .both) {
            let r = record(source: .appInput, at: date)
            #expect(HealthKitService.shared.appWrittenDateForDeletion(of: r) == date)
        }
    }

    @Test("HealthKit 由来レコード（hkImport/hkModified）は対象外で nil")
    func healthKitSourcedReturnsNil() {
        withHKSettings(enabled: true, direction: .both) {
            #expect(HealthKitService.shared.appWrittenDateForDeletion(of: record(source: .hkImport)) == nil)
            #expect(HealthKitService.shared.appWrittenDateForDeletion(of: record(source: .hkModified)) == nil)
        }
    }

    @Test("連携OFFなら nil")
    func disabledReturnsNil() {
        withHKSettings(enabled: false, direction: .both) {
            #expect(HealthKitService.shared.appWrittenDateForDeletion(of: record(source: .appInput)) == nil)
        }
    }

    @Test("読み取り専用（書込不可）なら nil")
    func readOnlyReturnsNil() {
        withHKSettings(enabled: true, direction: .readOnly) {
            #expect(HealthKitService.shared.appWrittenDateForDeletion(of: record(source: .appInput)) == nil)
        }
    }
}

// MARK: - 書き出しファイル書込の成否（共有・完了表示へ進むかの前提）

@Suite("ExportFileWriter Tests")
@MainActor
struct ExportFileWriterTests {

    @Test("書込可能なパスなら URL を返す")
    func writableReturnsURL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("out.json")
        let data = Data("{}".utf8)
        let result = ExportFileWriter.write(to: url, data: data)
        #expect(result == url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("書込先ディレクトリが存在しなければ nil（共有・完了へ進ませない）")
    func unwritablePathReturnsNil() {
        // 実在しない深い親ディレクトリ配下 → atomic write が失敗する
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)/sub/out.json")
        #expect(ExportFileWriter.write(to: url, data: Data("{}".utf8)) == nil)
    }
}

// MARK: - 編集で日時が別記録と同じ「分」になるかの検出

@Suite("hasSameMinuteConflict Tests")
@MainActor
struct SameMinuteConflictTests {

    /// 指定 timeIntervalSinceReferenceDate の日時でレコードを作って挿入する
    private func insert(_ context: ModelContext, at refSecs: Double) -> BodyRecord {
        let r = BodyRecord(dateTime: Date(timeIntervalSinceReferenceDate: refSecs))
        r.nBpHi_mmHg = 120; r.nBpLo_mmHg = 78
        context.insert(r)
        return r
    }

    /// ある分の開始秒（分ちょうど）。100分ちょうど = 6000 秒を基準に使う
    private let minuteBase: Double = 6000   // 分境界（6000/60=100 分ちょうど）

    @Test("別記録と同じ分へ日時変更したら衝突（true）")
    func conflictsWhenMovedIntoAnotherRecordsMinute() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        // 別記録は minuteBase+10 秒（同じ分）に存在
        _ = insert(context, at: minuteBase + 10)
        // 編集対象は別の分（minuteBase+120）にいたのを、その分へ動かす
        let editing = insert(context, at: minuteBase + 120)
        try context.save()

        let result = RecordEditViewModel.hasSameMinuteConflict(
            newDate: Date(timeIntervalSinceReferenceDate: minuteBase + 30), // 同じ分の別秒へ
            previousDate: Date(timeIntervalSinceReferenceDate: minuteBase + 120),
            editing: editing,
            context: context
        )
        #expect(result)
    }

    @Test("同じ分に他の記録が無ければ衝突なし（false）")
    func noConflictWhenMinuteIsEmpty() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let editing = insert(context, at: minuteBase + 120)
        try context.save()

        let result = RecordEditViewModel.hasSameMinuteConflict(
            newDate: Date(timeIntervalSinceReferenceDate: minuteBase + 30),
            previousDate: Date(timeIntervalSinceReferenceDate: minuteBase + 120),
            editing: editing,
            context: context
        )
        #expect(!result)
    }

    @Test("自分自身は衝突に数えない（移動先の分に自分だけ）")
    func selfDoesNotCountAsConflict() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        // 編集対象は別の分（minuteBase+120）に1件だけ。移動先の分には他の記録が無い
        let editing = insert(context, at: minuteBase + 120)
        try context.save()

        // minuteBase の分へ動かす。分は変わるが、その分にいるのは（移動後の）自分だけ → 衝突なし
        let result = RecordEditViewModel.hasSameMinuteConflict(
            newDate: Date(timeIntervalSinceReferenceDate: minuteBase + 30),
            previousDate: Date(timeIntervalSinceReferenceDate: minuteBase + 120),
            editing: editing,
            context: context
        )
        #expect(!result)
    }

    @Test("分が変わらなければ判定しない（false）")
    func noConflictWhenMinuteUnchanged() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        _ = insert(context, at: minuteBase + 10)   // 同じ分に別記録あり
        let editing = insert(context, at: minuteBase + 20)
        try context.save()

        // previous も new も同じ分（minuteBase）内 → 分は変わっていないので警告しない
        let result = RecordEditViewModel.hasSameMinuteConflict(
            newDate: Date(timeIntervalSinceReferenceDate: minuteBase + 45),
            previousDate: Date(timeIntervalSinceReferenceDate: minuteBase + 20),
            editing: editing,
            context: context
        )
        #expect(!result)
    }

    @Test("隣の分の記録は衝突に数えない（分境界）")
    func adjacentMinuteIsNotConflict() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        // 別記録は次の分（minuteBase+60）に存在
        _ = insert(context, at: minuteBase + 60)
        let editing = insert(context, at: minuteBase + 120)
        try context.save()

        // minuteBase の分へ動かす → 隣の分の記録は数えない
        let result = RecordEditViewModel.hasSameMinuteConflict(
            newDate: Date(timeIntervalSinceReferenceDate: minuteBase + 30),
            previousDate: Date(timeIntervalSinceReferenceDate: minuteBase + 120),
            editing: editing,
            context: context
        )
        #expect(!result)
    }
}
