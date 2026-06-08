// HealthKitService.swift
// HealthKit 連携サービス

import Foundation
import HealthKit
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "HealthKit")

// MARK: - 連携方向

enum HKSyncDirection: Int, CaseIterable, Identifiable {
    case writeOnly = 0  // アプリ → HealthKit
    case readOnly  = 1  // HealthKit → アプリ
    case both      = 2  // 双方向

    var id: Int { rawValue }

    var canWrite: Bool { self == .writeOnly || self == .both }
    var canRead:  Bool { self == .readOnly  || self == .both }

    var titleKey: String {
        switch self {
        case .writeOnly: return "health.direction.writeOnly"
        case .readOnly:  return "health.direction.readOnly"
        case .both:      return "health.direction.both"
        }
    }
}

// MARK: - データ転送用構造体

struct HealthKitValues {
    var date: Date
    var bpHi:    Int = 0   // mmHg        (0 = 未記録)
    var bpLo:    Int = 0   // mmHg
    var pulse:   Int = 0   // bpm
    var temp:    Int = 0   // ×10 ℃      例: 365 = 36.5℃
    var weight:  Int = 0   // ×10 kg      例: 650 = 65.0kg
    var bodyFat: Int = 0   // ×10 %       例: 235 = 23.5%
}

// MARK: - サービス本体

@Observable
@MainActor
final class HealthKitService {

    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAuthorized = false
    /// HealthKit へ書き込み許可済みの項目名一覧
    var authorizedShareFieldsText: String = ""
    /// 一括インポート実行中フラグ（並走防止）
    var isImporting: Bool = false
    /// 一括インポート中の進捗メッセージ（空文字 = 実行中でない）
    var importProgress: String = ""
    /// 設定変更後に記録タブへ戻ったときに自動インポートを1回実行するフラグ
    var needsAutoImport: Bool = false
    /// タイムアウトが発生したときに true になるフラグ（アラート表示用）
    var importTimedOut: Bool = false
    /// 自動インポート済み時刻画面表示にも使うため、変更時に UserDefaults へ保存する
    var lastAutoImportAt: Date? = UserDefaults.standard.object(forKey: UDefKeys.hkLastAutoImportAt) as? Date {
        didSet {
            if let lastAutoImportAt {
                UserDefaults.standard.set(lastAutoImportAt, forKey: UDefKeys.hkLastAutoImportAt)
            } else {
                UserDefaults.standard.removeObject(forKey: UDefKeys.hkLastAutoImportAt)
            }
        }
    }

    func clearLastAutoImportAt() {
        lastAutoImportAt = nil
    }

    private static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.bloodPressureSystolic),
        HKQuantityType(.bloodPressureDiastolic),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
    ]

    private static let shareFieldLabels: [(type: HKQuantityType, key: String)] = [
        (HKQuantityType(.bloodPressureSystolic), "metric.systolic"),
        (HKQuantityType(.bloodPressureDiastolic), "metric.diastolic"),
        (HKQuantityType(.heartRate), "metric.heartRate"),
        (HKQuantityType(.bodyTemperature), "metric.bodyTemp"),
        (HKQuantityType(.bodyMass), "metric.weight"),
        (HKQuantityType(.bodyFatPercentage), "metric.bodyFat"),
    ]

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.bloodPressureSystolic),
        HKQuantityType(.bloodPressureDiastolic),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {}

    // MARK: - 権限リクエスト

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            refreshAuthorizationStatus()
            logger.info("HealthKit 権限リクエスト完了")
        } catch {
            logger.error("HealthKit 権限エラー: \(error.localizedDescription)")
            AppAnalytics.shared.record(error: error, name: "healthkit_authorization_failed")
        }
    }

    func checkAuthorization() {
        guard isAvailable else { return }
        refreshAuthorizationStatus()
    }

    private func refreshAuthorizationStatus() {
        let authorizedNames = Self.shareFieldLabels.compactMap { item -> String? in
            guard store.authorizationStatus(for: item.type) == .sharingAuthorized else { return nil }
            return Bundle.main.localizedString(forKey: item.key, value: nil, table: nil)
        }
        isAuthorized = !authorizedNames.isEmpty
        authorizedShareFieldsText = authorizedNames.isEmpty
            ? Bundle.main.localizedString(forKey: "health.noWritableFields", value: nil, table: nil)
            : ListFormatter.localizedString(byJoining: authorizedNames)
    }

    // MARK: - 書き込み

    func write(_ values: HealthKitValues) async {
        guard isAvailable, !AppSettings.shared.hkDisabledByDemo else { return }

        // 同日時の既存サンプルを削除してから追加（上書き相当）
        await deleteSamples(at: values.date)

        var samples: [HKSample] = []
        let date = values.date

        // 血圧（Correlation）
        if values.bpHi > 0 && values.bpLo > 0 {
            let systolic = HKQuantitySample(
                type: HKQuantityType(.bloodPressureSystolic),
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double(values.bpHi)),
                start: date, end: date)
            let diastolic = HKQuantitySample(
                type: HKQuantityType(.bloodPressureDiastolic),
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double(values.bpLo)),
                start: date, end: date)
            let bp = HKCorrelation(
                type: HKCorrelationType(.bloodPressure),
                start: date, end: date,
                objects: [systolic, diastolic])
            samples.append(bp)
        }

        // 心拍数
        if values.pulse > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: Double(values.pulse)),
                start: date, end: date))
        }

        // 体温
        if values.temp > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyTemperature),
                quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: Double(values.temp) / 10.0),
                start: date, end: date))
        }

        // 体重
        if values.weight > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: Double(values.weight) / 10.0),
                start: date, end: date))
        }

        // 体脂肪率（HKUnit.percent() は 0–100 のパーセント値）
        if values.bodyFat > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: Double(values.bodyFat) / 10.0 / 100.0),
                start: date, end: date))
        }

        guard !samples.isEmpty else { return }

        do {
            try await store.save(samples)
            logger.info("HealthKit 書き込み完了: \(samples.count) サンプル")
        } catch {
            logger.error("HealthKit 書き込み失敗: \(error.localizedDescription)")
            AppAnalytics.shared.record(error: error, name: "healthkit_write_failed")
        }
    }

    // MARK: - 読み込み

    /// 指定日時より前の最新サンプルを取得
    /// - Parameter hiddenFields: 非表示フィールドの GraphKind.rawValue 集合含まれる種別は取得をスキップする
    func readLatest(before date: Date, hiddenFields: Set<Int> = []) async -> HealthKitValues {
        guard isAvailable else { return HealthKitValues(date: date) }

        var v = HealthKitValues(date: date)

        // 血圧
        if !hiddenFields.contains(GraphKind.bp.rawValue),
           let bp = await mostRecentBloodPressure(before: date) {
            v.bpHi = bp.0
            v.bpLo = bp.1
        }

        // 心拍数
        if !hiddenFields.contains(GraphKind.pulse.rawValue),
           let s = await mostRecentQuantity(.heartRate, before: date) {
            v.pulse = Int(s.quantity.doubleValue(for: HKUnit(from: "count/min")))
        }

        // 体温
        if !hiddenFields.contains(GraphKind.temp.rawValue),
           let s = await mostRecentQuantity(.bodyTemperature, before: date) {
            v.temp = Int(s.quantity.doubleValue(for: .degreeCelsius()) * 10.0)
        }

        // 体重
        if !hiddenFields.contains(GraphKind.weight.rawValue),
           let s = await mostRecentQuantity(.bodyMass, before: date) {
            v.weight = Int(s.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 10.0)
        }

        // 体脂肪率
        if !hiddenFields.contains(GraphKind.bodyFat.rawValue),
           let s = await mostRecentQuantity(.bodyFatPercentage, before: date) {
            // percent() は内部的に fraction (0–1) で格納されるため ×100×10
            v.bodyFat = Int(s.quantity.doubleValue(for: .percent()) * 100.0 * 10.0)
        }

        return v
    }

    // MARK: - Private helpers

    /// 指定日時にこのアプリが書き込んだサンプルをすべて削除する
    private func deleteSamples(at date: Date) async {
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: date, end: date.addingTimeInterval(1)),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        logger.info("deleteSamples 開始: \(date, privacy: .public)")
        // 血圧 Correlation を先に削除（配下の systolic/diastolic も同時に削除される）
        do {
            try await store.deleteObjects(of: HKCorrelationType(.bloodPressure), predicate: pred)
        } catch {
            logger.error("deleteSamples[bloodPressure] エラー: \(error.localizedDescription, privacy: .public)")
        }
        // その他の量的型を削除
        let qtTypes: [HKQuantityTypeIdentifier] = [
            .heartRate, .bodyTemperature, .bodyMass, .bodyFatPercentage
        ]
        for id in qtTypes {
            do {
                try await store.deleteObjects(of: HKQuantityType(id), predicate: pred)
            } catch {
                logger.error("deleteSamples[\(id.rawValue, privacy: .public)] エラー: \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("deleteSamples 完了")
    }

    private func mostRecentQuantity(
        _ id: HKQuantityTypeIdentifier,
        before date: Date
    ) async -> HKQuantitySample? {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        return try? await descriptor.result(for: store).first
    }

    private func mostRecentBloodPressure(before date: Date) async -> (Int, Int)? {
        let type = HKCorrelationType(.bloodPressure)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date)
        return await withCheckedContinuation { continuation in
            let query = HKCorrelationQuery(
                type: type,
                predicate: predicate,
                samplePredicates: nil
            ) { _, results, error in
                guard error == nil,
                      let correlation = results?.sorted(by: { $0.endDate > $1.endDate }).first
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let systolic = correlation.objects
                    .compactMap { $0 as? HKQuantitySample }
                    .first { $0.quantityType == HKQuantityType(.bloodPressureSystolic) }
                let diastolic = correlation.objects
                    .compactMap { $0 as? HKQuantitySample }
                    .first { $0.quantityType == HKQuantityType(.bloodPressureDiastolic) }
                guard let s = systolic, let d = diastolic else {
                    continuation.resume(returning: nil)
                    return
                }
                let hi = Int(s.quantity.doubleValue(for: .millimeterOfMercury()))
                let lo = Int(d.quantity.doubleValue(for: .millimeterOfMercury()))
                continuation.resume(returning: (hi, lo))
            }
            self.store.execute(query)
        }
    }

    // MARK: - 期間一括読み込み

    /// 指定期間の全サンプルを返す（分単位でグループ化）
    /// 10秒以内に完了しない場合は空配列を返し importTimedOut を true にする
    /// - Parameter hiddenFields: 非表示フィールドの GraphKind.rawValue 集合含まれる種別は取得をスキップする
    func readSamples(from startDate: Date, to endDate: Date, hiddenFields: Set<Int> = []) async -> [HealthKitValues] {
        guard isAvailable else {
            logger.error("readSamples: HealthKit 利用不可")
            return []
        }
        logger.info("readSamples 開始: \(startDate, privacy: .public) 〜 \(endDate, privacy: .public)")
        importTimedOut = false
        let startTime = Date()

        let result = await withCheckedContinuation { (cont: CheckedContinuation<[HealthKitValues], Never>) in
            let done = OnceMark()

            // 10 秒タイムアウト
            Task { @MainActor [self] in
                try? await Task.sleep(for: .seconds(10))
                guard done.claim() else { return }
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                logger.warning("readSamples タイムアウト（10秒）: \(elapsed) ms 経過")
                importTimedOut = true
                importProgress = ""
                cont.resume(returning: [])
            }

            // 実際の取得
            Task { @MainActor [self] in
                let values = await _runImport(from: startDate, to: endDate, hiddenFields: hiddenFields)
                guard done.claim() else { return }
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                logger.debug("readSamples 所要時間: \(elapsed) ms（\(values.count) 件）")
                cont.resume(returning: values)
            }
        }

        importProgress = ""
        return result
    }

    private func _runImport(from startDate: Date, to endDate: Date, hiddenFields: Set<Int>) async -> [HealthKitValues] {
        /// 同じ分の測定を1レコードに統合するキー
        func minuteKey(_ d: Date) -> Date {
            let secs = d.timeIntervalSinceReferenceDate
            return Date(timeIntervalSinceReferenceDate: (secs / 60).rounded(.down) * 60)
        }
        var byMinute: [Date: HealthKitValues] = [:]

        // 血圧
        if !hiddenFields.contains(GraphKind.bp.rawValue) {
            importProgress = "health.progress.bloodPressure"
            let bpSamples = await allBPSamples(from: startDate, to: endDate)
            logger.info("血圧サンプル数: \(bpSamples.count)")
            for (date, hi, lo) in bpSamples {
                let k = minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
                if v.bpHi == 0 { v.bpHi = hi; v.bpLo = lo; v.date = date }
                byMinute[k] = v
            }
        }

        // 心拍数
        if !hiddenFields.contains(GraphKind.pulse.rawValue) {
            importProgress = "health.progress.heartRate"
            let hrSamples = await allQtySamples(.heartRate, from: startDate, to: endDate, unit: HKUnit(from: "count/min"))
            logger.info("心拍数サンプル数: \(hrSamples.count)")
            for (date, val) in hrSamples {
                let k = minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
                if v.pulse == 0 { v.pulse = Int(val) }
                byMinute[k] = v
            }
        }

        // 体温
        if !hiddenFields.contains(GraphKind.temp.rawValue) {
            importProgress = "health.progress.bodyTemp"
            let tempSamples = await allQtySamples(.bodyTemperature, from: startDate, to: endDate, unit: .degreeCelsius())
            logger.info("体温サンプル数: \(tempSamples.count)")
            for (date, val) in tempSamples {
                let k = minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
                if v.temp == 0 { v.temp = Int(val * 10) }
                byMinute[k] = v
            }
        }

        // 体重
        if !hiddenFields.contains(GraphKind.weight.rawValue) {
            importProgress = "health.progress.weight"
            let weightSamples = await allQtySamples(.bodyMass, from: startDate, to: endDate, unit: .gramUnit(with: .kilo))
            logger.info("体重サンプル数: \(weightSamples.count)")
            for (date, val) in weightSamples {
                let k = minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
                if v.weight == 0 { v.weight = Int(val * 10) }
                byMinute[k] = v
            }
        }

        // 体脂肪率
        if !hiddenFields.contains(GraphKind.bodyFat.rawValue) {
            importProgress = "health.progress.bodyFat"
            let fatSamples = await allQtySamples(.bodyFatPercentage, from: startDate, to: endDate, unit: .percent())
            logger.info("体脂肪率サンプル数: \(fatSamples.count)")
            for (date, val) in fatSamples {
                let k = minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
                if v.bodyFat == 0 { v.bodyFat = Int(val * 100 * 10) }
                byMinute[k] = v
            }
        }

        // 非表示でないバイタル項目のうち少なくとも1つが入力されているレコードのみ残す
        let result = byMinute.values
            .filter { v in
                (!hiddenFields.contains(GraphKind.bp.rawValue)     && v.bpHi > 0)   ||
                (!hiddenFields.contains(GraphKind.pulse.rawValue)  && v.pulse > 0)  ||
                (!hiddenFields.contains(GraphKind.temp.rawValue)   && v.temp > 0)   ||
                (!hiddenFields.contains(GraphKind.weight.rawValue) && v.weight > 0)
            }
            .sorted { $0.date < $1.date }
        logger.info("readSamples 完了: \(result.count) 件")
        return result
    }

    private func allBPSamples(from start: Date, to end: Date) async -> [(Date, Int, Int)] {
        logger.info("allBPSamples 開始: \(start, privacy: .public) 〜 \(end, privacy: .public)")
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKCorrelationQuery(
                type: HKCorrelationType(.bloodPressure),
                predicate: predicate,
                samplePredicates: nil
            ) { _, results, error in
                if let error {
                    logger.error("allBPSamples エラー: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: [])
                    return
                }
                let pairs = (results ?? [])
                    .sorted { $0.endDate < $1.endDate }
                    .compactMap { corr -> (Date, Int, Int)? in
                        let objs = corr.objects.compactMap { $0 as? HKQuantitySample }
                        guard let sys = objs.first(where: { $0.quantityType == HKQuantityType(.bloodPressureSystolic) }),
                              let dia = objs.first(where: { $0.quantityType == HKQuantityType(.bloodPressureDiastolic) })
                        else { return nil }
                        return (corr.endDate,
                                Int(sys.quantity.doubleValue(for: .millimeterOfMercury())),
                                Int(dia.quantity.doubleValue(for: .millimeterOfMercury())))
                    }
                logger.info("allBPSamples 完了: \(pairs.count) 件")
                continuation.resume(returning: pairs)
            }
            self.store.execute(query)
        }
    }

    private func allQtySamples(
        _ id: HKQuantityTypeIdentifier,
        from start: Date, to end: Date,
        unit: HKUnit
    ) async -> [(Date, Double)] {
        logger.info("allQtySamples[\(id.rawValue, privacy: .public)] 開始")
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)])
        do {
            let samples = try await descriptor.result(for: store)
            logger.info("allQtySamples[\(id.rawValue, privacy: .public)] 完了: \(samples.count) 件")
            return samples.map { ($0.endDate, $0.quantity.doubleValue(for: unit)) }
        } catch {
            logger.error("allQtySamples[\(id.rawValue, privacy: .public)] エラー: \(error.localizedDescription, privacy: .public)")
            AppAnalytics.shared.record(
                error: error,
                name: "healthkit_read_failed",
                parameters: ["sample_type": id.rawValue]
            )
            return []
        }
    }

}

// MARK: - ユーティリティ

/// withCheckedContinuation の二重 resume を防ぐ一回限りのフラグ（スレッドセーフ）
private final class OnceMark: @unchecked Sendable {
    private var _claimed = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_claimed else { return false }
        _claimed = true
        return true
    }
}
