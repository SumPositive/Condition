// ConditionTests.swift

import Testing
import Foundation
import SwiftData
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

@Suite("DateOpt Tests")
struct DateOptTests {

    @Test("autoDateOpt: 6時台は dateOptHourMap で設定された区分を返す")
    @MainActor
    func autoDateOptByHourMap() {
        let settings = AppSettings.shared
        // 6時台に cat01（起床時 既定）を割り当てる
        var map = settings.dateOptHourMap
        if map.count > 6 { map[6] = DateOpt.cat01.rawValue }
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
