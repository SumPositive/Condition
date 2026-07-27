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

// MARK: - サンプル変換（store 非依存の純粋ロジック）

/// HealthKitValues と HKSample の変換をまとめた純粋ロジック。
/// HKHealthStore に依存しないので単体テストできる（値>0 の項目だけをサンプル化する）。
enum HealthKitSampleBuilder {

    /// HealthKitValues から保存対象の HKSample 群を組み立てる。値が 0（未記録）の項目は含めない。
    static func samples(from values: HealthKitValues) -> [HKSample] {
        var samples: [HKSample] = []
        let date = values.date

        // 血圧（Correlation）: 上下そろって初めて1件にする
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

        // 体温（×10 保持 → ℃）
        if values.temp > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyTemperature),
                quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: Double(values.temp) / 10.0),
                start: date, end: date))
        }

        // 体重（×10 保持 → kg）
        if values.weight > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: Double(values.weight) / 10.0),
                start: date, end: date))
        }

        // 体脂肪率（×10 保持の % → HKUnit.percent() は 0–1 の割合で格納）
        if values.bodyFat > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: Double(values.bodyFat) / 10.0 / 100.0),
                start: date, end: date))
        }

        return samples
    }

    /// 保存した新サンプル（Correlation 配下の血圧サンプルも含む）の UUID 一覧。
    /// 上書き時の旧サンプル削除で、保存したばかりの新サンプルを除外するために使う。
    static func objectUUIDs(in samples: [HKSample]) -> Set<UUID> {
        var uuids: Set<UUID> = []
        for sample in samples {
            uuids.insert(sample.uuid)
            if let correlation = sample as? HKCorrelation {
                correlation.objects.forEach { uuids.insert($0.uuid) }
            }
        }
        return uuids
    }
}

// MARK: - 削除保留ストア（テストで差し替え可能にする）

/// 削除待ち日時（timeIntervalSince1970）の集合を永続化するストア。
/// 本番は UserDefaults、テストはインメモリ実装を注入して UserDefaults を汚さずに検証する。
/// HealthKitService（@MainActor）からのみ使うため MainActor 隔離にする。
@MainActor
protocol PendingDeletionStore: AnyObject {
    var timestamps: Set<Double> { get set }
}

/// UserDefaults 実装（本番）
@MainActor
final class UserDefaultsPendingDeletionStore: PendingDeletionStore {
    var timestamps: Set<Double> {
        get { Set(UserDefaults.standard.array(forKey: UDefKeys.hkPendingDeletionDates) as? [Double] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: UDefKeys.hkPendingDeletionDates) }
    }
}

// MARK: - サービス本体

@Observable
@MainActor
final class HealthKitService {

    static let shared = HealthKitService()

    private let store = HKHealthStore()

    /// 削除保留の永続化先（テストで差し替え可能）
    private let pendingDeletionStore: PendingDeletionStore

    /// `write` が行う HealthKit I/O を注入するためのフック（テストで遅延・失敗を仕込む）。
    /// これらを差し替えても `write` 本体（空値分岐・save→delete 順序・削除保留解除）はそのまま走るので、
    /// キュー制御と保留解除まで含めて検証できる。nil の本番は HKHealthStore を用いる既定実装を使う。
    /// - injectedSaveSamples: 新サンプルの保存（本番は store.save）
    /// - injectedDeleteAppSamples: 同日時のアプリ書込サンプル削除（本番は deleteSamples）。第2引数は保護する新サンプルUUID。
    private let injectedSaveSamples: (@MainActor ([HKSample]) async throws -> Void)?
    private let injectedDeleteAppSamples: (@MainActor (Date, Set<UUID>) async throws -> Void)?

    /// I/O が注入されている（＝テスト）か。true のとき `write` は HKHealthStore の可用性・デモ判定を
    /// スキップし、注入された save/delete を必ず実行する（キュー制御・保留解除を実機なしで検証するため）。
    private var usesInjectedIO: Bool { injectedSaveSamples != nil || injectedDeleteAppSamples != nil }

    /// 実際に使う保存処理（注入があればそれ、なければ HKHealthStore.save）
    private func performSave(_ samples: [HKSample]) async throws {
        if let injectedSaveSamples {
            try await injectedSaveSamples(samples)
        } else {
            try await store.save(samples)
        }
    }

    /// 実際に使う削除処理（注入があればそれ、なければ deleteSamples）
    private func performDelete(_ date: Date, excludingUUIDs: Set<UUID>) async throws {
        if let injectedDeleteAppSamples {
            try await injectedDeleteAppSamples(date, excludingUUIDs)
        } else {
            try await deleteSamples(at: date, excludingUUIDs: excludingUUIDs)
        }
    }

    /// 同一日時に対する書込タスクを集約するためのキャッシュ。
    /// 連続編集で多重キューイングされないよう、新しい書込を予約する前に既存タスクを cancel する。
    /// 各予約に世代番号を持たせ、古いタスクの完了時に後発タスクの登録を誤って消さないようにする。
    /// `isDeletionRetry` は「削除保留の再処理（空値クリア）」かを表す。ユーザー由来の書込（作り直し）が
    /// 未完了のときに、削除再試行がそれを cancel して上書きするのを防ぐために使う。
    private var pendingWriteTasks: [Date: (generation: Int, task: Task<Void, Never>, isDeletionRetry: Bool)] = [:]
    /// 書込予約ごとに増やす世代番号（同日時の後発予約を識別する）
    private var writeGeneration = 0

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

    /// - Parameters:
    ///   - pendingDeletionStore: 削除保留の永続化先。既定は UserDefaults。
    ///   - saveSamples: 新サンプルの保存処理。既定（nil）は HKHealthStore.save。
    ///   - deleteAppSamples: 同日時のアプリ書込サンプル削除処理。既定（nil）は deleteSamples。
    ///     テストではここに遅延・失敗を仕込み、キュー制御・保留解除まで検証する（HKHealthStore は使わない）。
    init(
        pendingDeletionStore: PendingDeletionStore = UserDefaultsPendingDeletionStore(),
        saveSamples: (@MainActor ([HKSample]) async throws -> Void)? = nil,
        deleteAppSamples: (@MainActor (Date, Set<UUID>) async throws -> Void)? = nil
    ) {
        self.pendingDeletionStore = pendingDeletionStore
        self.injectedSaveSamples = saveSamples
        self.injectedDeleteAppSamples = deleteAppSamples
    }

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
        // 未反映の削除待ちがあれば、この機会に再試行する
        retryPendingDeletions()
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

    /// 同一日時の書込を集約する safe な書込予約。
    /// 同日時では処理を直列化し、先行タスク（保存・削除）が完了してから後発を開始する。
    /// これにより、空値クリアの全削除が後発保存の直後に走って新しい値まで消す事故を防ぐ。
    /// 呼び出し側で `Task { try await write(...) }` するより、こちらを使うと多重キューを防げる。
    /// - Parameter isDeletionRetry: 削除保留の再処理（空値クリア）なら true。
    ///   このとき、同日時にユーザー由来の未完了書込（記録の作り直し）が既にキューにいれば、
    ///   それを cancel せず予約自体をスキップし、その書込に処理を委ねる（新しい記録を消さない）。
    /// - Returns: 予約したタスク。スキップした場合は先行タスクを返すので、`await task.value` で
    ///   その日時の最終的な処理完了を待てる。
    @discardableResult
    func scheduleWrite(_ values: HealthKitValues, isDeletionRetry: Bool = false) -> Task<Void, Never> {
        let key = Date(timeIntervalSince1970: floor(values.date.timeIntervalSince1970))
        let previous = pendingWriteTasks[key]

        // 削除保留の再処理は、ユーザー由来の未完了書込（＝作り直し）を上書きしない。
        // その書込が非空なら成功時に removePendingDeletion するので、削除保留はそちらで解消される。
        if Self.deletionRetryShouldYield(isDeletionRetry: isDeletionRetry,
                                         previousIsDeletionRetry: previous?.isDeletionRetry),
           let previous {
            return previous.task
        }

        // 先行タスクを控える。cancel は「まだ開始していない先行」を早期に譲らせる合図
        previous?.task.cancel()
        writeGeneration += 1
        let generation = writeGeneration
        let task = Task { @MainActor [weak self] in
            // 先行タスクを必ず完了させてから開始する（削除と後発保存を交錯させない）
            if let previous { await previous.task.value }
            // 待機中に後発へ置き換えられていたら、処理せず後発へ譲る
            guard self?.pendingWriteTasks[key]?.generation == generation else { return }
            do {
                try await self?.write(values)
            } catch is CancellationError {
                // 後発の書込に処理を譲っただけなので無視する
            } catch {
                // write は失敗を握りつぶさず throw するので、ここで記録する
                logger.error("HealthKit 書き込み失敗: \(error.localizedDescription)")
                AppAnalytics.shared.record(error: error, name: "healthkit_write_failed")
            }
            // 自分の世代がまだ最新のときだけ辞書から外す（後発タスクの登録を消さない）
            if self?.pendingWriteTasks[key]?.generation == generation {
                self?.pendingWriteTasks[key] = nil
            }
        }
        pendingWriteTasks[key] = (generation, task, isDeletionRetry)
        return task
    }

    /// 記録削除に伴い HealthKit から消すべき「アプリ書込分」の日時を返す。
    /// 連携OFF・書込不可・HK由来（hkImport/hkModified）レコードは対象外で nil を返す。
    /// 実削除は保存成功後に `scheduleDelete(at:)`（空値クリア＋削除待ち永続化）で行う。
    func appWrittenDateForDeletion(of record: BodyRecord) -> Date? {
        let s = AppSettings.shared
        guard s.hkEnabled, HKSyncDirection(rawValue: s.hkDirection)?.canWrite == true else { return nil }
        // HK から取り込んだ／HK由来の変更レコードはアプリの書込ではないので触らない
        if record.dataSource == .hkImport || record.dataSource == .hkModified { return nil }
        return record.dateTime
    }

    // MARK: - 削除待ちの永続化と再試行
    //
    // 双方向同期では、削除がHealthKitへ反映されないと次回インポートで記録が復活する。
    // 削除待ちの日時を UserDefaults に永続化し、成功するまで（起動時・設定表示時・インポート前に）再試行する。

    private var pendingDeletionTimestamps: Set<Double> {
        get { pendingDeletionStore.timestamps }
        set { pendingDeletionStore.timestamps = newValue }
    }

    private func addPendingDeletion(_ date: Date) {
        var set = pendingDeletionTimestamps
        set.insert(date.timeIntervalSince1970)
        pendingDeletionTimestamps = set
    }

    private func removePendingDeletion(_ date: Date) {
        var set = pendingDeletionTimestamps
        guard set.remove(date.timeIntervalSince1970) != nil else { return }
        pendingDeletionTimestamps = set
    }

    /// アプリ書込分の同日時サンプルを HealthKit から削除する（記録削除・日時変更で使う）。
    /// 削除待ちを永続化してから空値クリアを予約するので、失敗しても成功するまで再試行される。
    /// - Returns: 予約したタスク（テストで完了を待つために返す）。
    @discardableResult
    func scheduleDelete(at date: Date) -> Task<Void, Never> {
        addPendingDeletion(date)
        // 空値=クリア。直列化された書込経路を通す。成功すれば write が削除待ちから外す
        return scheduleWrite(HealthKitValues(date: date))
    }

    /// 永続化された削除待ちを再試行する（fire-and-forget）。起動時や設定画面表示時に呼ぶ。
    /// 再試行なので、同日時にユーザーが記録を作り直していれば（未完了の非削除書込がキューにいれば）
    /// それを上書きしない（isDeletionRetry: true）。
    func retryPendingDeletions() {
        for ts in pendingDeletionTimestamps {
            scheduleWrite(HealthKitValues(date: Date(timeIntervalSince1970: ts)), isDeletionRetry: true)
        }
    }

    /// 削除待ちを消化して待つ。インポート直前に呼び、削除済み記録の再登録を防ぐ。
    ///
    /// 削除は `deleteSamples` を直接呼ばず、必ず `scheduleWrite`（空値クリア）を通して
    /// **日時別の書込直列化キューに載せる**。これにより、同日時への新規保存と削除が交錯して
    /// 保存直後のサンプルを消してしまう競合を防ぐ。予約タスクの完了を待ち、
    /// 空値クリアが成功していれば `write` 側が保留を外すので、待機後に残っている保留＝削除失敗と判定する。
    /// - Returns: 削除に失敗して保留が残った記録の「分キー」（`minuteKey(_:)` で正規化した値）。
    ///   呼び出し側（インポート）は、この分に該当するレコードを取り込み対象から除外し、
    ///   削除しきれなかった記録が復活しないようにする。分単位にするのは、インポートが分単位で
    ///   1レコードに統合するため（秒単位だと統合で代表日時がズレて除外をすり抜ける）。
    @discardableResult
    private func flushPendingDeletions() async -> Set<Double> {
        let s = AppSettings.shared
        // 書込不可・デモ中などで削除を試せない場合は、現在の保留をすべて「未解消」として扱う。
        // インポート側はこれらの分を除外し、削除できていない記録の再登録を防ぐ。
        guard isAvailable, !s.hkDisabledByDemo,
              HKSyncDirection(rawValue: s.hkDirection)?.canWrite == true else {
            return Set(pendingDeletionTimestamps.map { Self.minuteKey(Date(timeIntervalSince1970: $0)) })
        }

        // 消化対象を確定（消化中に scheduleDelete で増えた分は次回に回す）
        let targets = pendingDeletionTimestamps
        guard !targets.isEmpty else { return [] }

        // 各日時の削除を書込キューへ予約し、その完了を待つ。
        // 空値クリアの write は成功時に removePendingDeletion(values.date) するため、
        // 待機後にも保留へ残っている日時＝削除失敗（未解消）と判定できる。
        // 再試行なので、ユーザーが同日時に記録を作り直していればその書込を上書きしない
        // （isDeletionRetry: true）。その書込が非空なら成功時に保留が解消される。
        var tasks: [(ts: Double, task: Task<Void, Never>)] = []
        for ts in targets {
            let task = scheduleWrite(HealthKitValues(date: Date(timeIntervalSince1970: ts)), isDeletionRetry: true)
            tasks.append((ts, task))
        }
        for entry in tasks {
            await entry.task.value
        }

        // 待機後に保留へ残っている（＝クリアに失敗した）記録の分キーを未解消として返す
        let stillPending = pendingDeletionTimestamps
        var unresolved: Set<Double> = []
        for ts in targets where stillPending.contains(ts) {
            unresolved.insert(Self.minuteKey(Date(timeIntervalSince1970: ts)))
        }
        return unresolved
    }

    /// 同日時の値を HealthKit へ上書き保存する。
    /// 先に新サンプルを保存し、成功した後にだけ旧サンプルを削除するので、
    /// 保存に失敗しても既存の HealthKit データを失わない。失敗は呼び出し元へ throw する。
    func write(_ values: HealthKitValues) async throws {
        // 本番のみ可用性・デモ判定で早期return。注入I/O（テスト）では必ず実行してキュー制御を検証する。
        if !usesInjectedIO {
            guard isAvailable, !AppSettings.shared.hkDisabledByDemo else { return }
        }
        // cancel 済みなら即抜ける（後発の書込に処理を譲る）
        if Task.isCancelled { return }

        let samples = HealthKitSampleBuilder.samples(from: values)

        // 値がすべて未記録ならクリア操作。既存サンプルの削除だけ行う
        guard !samples.isEmpty else {
            if Task.isCancelled { return }
            try await performDelete(values.date, excludingUUIDs: [])
            // クリア成功。この日時の削除待ちがあれば解消する
            removePendingDeletion(values.date)
            return
        }

        // 先に新サンプルを保存する。失敗すれば旧データを削除しないまま throw される（データ喪失なし）
        try await performSave(samples)
        logger.info("HealthKit 書き込み完了: \(samples.count) サンプル")

        // 後発の書込があれば、その最新書込の削除にまとめて委ねる（残った重複は次回掃除される）
        if Task.isCancelled { return }

        // 保存できた新サンプルを除外し、同日時の旧サンプルだけ削除して上書きを完成させる。
        // 削除に失敗しても重複が残るだけでデータ喪失ではないため、記録に留めて throw しない。
        do {
            try await performDelete(values.date, excludingUUIDs: HealthKitSampleBuilder.objectUUIDs(in: samples))
        } catch {
            logger.error("HealthKit 旧サンプル削除失敗: \(error.localizedDescription)")
            AppAnalytics.shared.record(error: error, name: "healthkit_stale_delete_failed")
        }
        // 保存に成功したので、この日時の削除待ち（過去の削除失敗）は不要になった
        removePendingDeletion(values.date)
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

    /// 指定日時にこのアプリが書き込んだサンプルを削除する。
    /// - Parameter excludingUUIDs: 削除対象から除外する UUID（保存したばかりの新サンプルを守る）。
    /// 一部の型が失敗しても残りの型は削除を試み、最初のエラーを呼び出し元へ返す。
    private func deleteSamples(at date: Date, excludingUUIDs: Set<UUID>) async throws {
        var pred: NSPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: date, end: date.addingTimeInterval(1)),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        if !excludingUUIDs.isEmpty {
            // 保存したばかりの新サンプルを削除しないよう除外する
            let notNew = NSCompoundPredicate(
                notPredicateWithSubpredicate: HKQuery.predicateForObjects(with: excludingUUIDs))
            pred = NSCompoundPredicate(andPredicateWithSubpredicates: [pred, notNew])
        }
        logger.info("deleteSamples 開始: \(date, privacy: .public)")

        var firstError: Error?
        // 血圧 Correlation を先に削除（配下の systolic/diastolic も同時に削除される）
        do {
            try await store.deleteObjects(of: HKCorrelationType(.bloodPressure), predicate: pred)
        } catch {
            // 「該当サンプル無し」（既にヘルスケア側で削除済み等）は成功扱いにし、再試行対象にしない
            if !Self.isNoDataError(error) {
                firstError = firstError ?? error
                logger.error("deleteSamples[bloodPressure] エラー: \(error.localizedDescription, privacy: .public)")
            }
        }
        // その他の量的型を削除
        let qtTypes: [HKQuantityTypeIdentifier] = [
            .heartRate, .bodyTemperature, .bodyMass, .bodyFatPercentage
        ]
        for id in qtTypes {
            do {
                try await store.deleteObjects(of: HKQuantityType(id), predicate: pred)
            } catch {
                if !Self.isNoDataError(error) {
                    firstError = firstError ?? error
                    logger.error("deleteSamples[\(id.rawValue, privacy: .public)] エラー: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        logger.info("deleteSamples 完了")
        if let firstError { throw firstError }
    }

    /// HealthKit の「該当データ無し」エラーか。既に消えているサンプルの削除を成功扱いにするために使う。
    private static func isNoDataError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == HKError.errorDomain && ns.code == HKError.Code.errorNoData.rawValue
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
        // インポート前に削除待ちを消化し、削除済み記録が再登録されるのを防ぐ。
        // 削除しきれず保留が残った記録の「分」は、この回のインポートから除外して記録の復活を防ぐ。
        let unresolvedDeletionMinutes = await flushPendingDeletions()
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
                let values = await _runImport(
                    from: startDate, to: endDate,
                    hiddenFields: hiddenFields,
                    excludingMinuteKeys: unresolvedDeletionMinutes
                )
                guard done.claim() else { return }
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                logger.debug("readSamples 所要時間: \(elapsed) ms（\(values.count) 件）")
                cont.resume(returning: values)
            }
        }

        importProgress = ""
        return result
    }

    private func _runImport(
        from startDate: Date, to endDate: Date,
        hiddenFields: Set<Int>,
        excludingMinuteKeys: Set<Double> = []
    ) async -> [HealthKitValues] {
        // キーは分単位に丸めた timeIntervalSinceReferenceDate（minuteKey）。同じ分の測定を1件に統合する。
        var byMinute: [Double: HealthKitValues] = [:]

        // 血圧
        if !hiddenFields.contains(GraphKind.bp.rawValue) {
            importProgress = "health.progress.bloodPressure"
            let bpSamples = await allBPSamples(from: startDate, to: endDate)
            logger.info("血圧サンプル数: \(bpSamples.count)")
            for (date, hi, lo) in bpSamples {
                let k = Self.minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
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
                let k = Self.minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
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
                let k = Self.minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
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
                let k = Self.minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
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
                let k = Self.minuteKey(date); var v = byMinute[k] ?? HealthKitValues(date: date)
                if v.bodyFat == 0 { v.bodyFat = Int(val * 100 * 10) }
                byMinute[k] = v
            }
        }

        // 非表示でないバイタル項目のうち少なくとも1つが入力されているレコードのみ残す。
        // 削除しきれなかった記録は「分単位」で除外し、削除済み記録の復活を防ぐ。
        // （インポートは分単位で1レコードに統合されるため、除外も同じ分粒度で行う。
        //   秒単位で判定すると、同じ分の別サンプルと統合されて代表日時がズレたとき除外をすり抜ける）
        let result = Self.retainedImportValues(
            Array(byMinute.values),
            hiddenFields: hiddenFields,
            excludingMinuteKeys: excludingMinuteKeys
        )
        logger.info("readSamples 完了: \(result.count) 件")
        return result
    }

    /// 同じ分の測定を1レコードに統合するためのキー（分単位に丸めた timeIntervalSinceReferenceDate）。
    /// 削除保留の除外判定もこのキーで行い、統合とインポート除外の粒度を一致させる。
    static func minuteKey(_ d: Date) -> Double {
        let secs = d.timeIntervalSinceReferenceDate
        return (secs / 60).rounded(.down) * 60
    }

    /// 削除保留の再処理が、同日時の先行タスクに処理を譲るべきか。
    /// 「再処理（isDeletionRetry）」かつ「先行がユーザー由来の書込（削除再試行でない）」のときだけ true。
    /// このとき削除再処理は予約せず、先行の書込（記録の作り直し）を上書きしない。
    /// - Parameter previousIsDeletionRetry: 先行タスクの種別。先行が無ければ nil（＝譲る必要なし）。
    static func deletionRetryShouldYield(isDeletionRetry: Bool, previousIsDeletionRetry: Bool?) -> Bool {
        guard isDeletionRetry else { return false }
        guard let previousIsDeletionRetry else { return false }
        return !previousIsDeletionRetry
    }

    /// インポート結果のうち「表示対象の非表示でないバイタルが少なくとも1つ入っている」レコードだけを
    /// 日時昇順で残す純粋ロジック。体脂肪率だけのレコードが落ちないことなどを単体テストできる。
    /// - Parameter excludingMinuteKeys: 除外する分キー（`minuteKey(_:)` で正規化した値）。
    ///   HealthKit から削除しきれなかった記録が再取り込みで復活するのを防ぐために使う。
    ///   同じ分に統合された全バイタルをまとめて除外するので、統合で代表日時がズレても取りこぼさない。
    ///
    /// 粒度が「分」なのは、インポートが分単位で1レコードに統合するため（統合と除外を同粒度に揃える）。
    /// アプリの記録は実質「1分1件」前提なので通常は問題ないが、仕様上は同じ分に複数記録を作ることも可能で、
    /// その場合「削除に失敗した記録と同じ分の別記録」も巻き込んで除外され得る。ただし除外対象は
    /// HealthKit からの再取り込み結果だけで、アプリ側の元データは消えず、削除保留が解消すれば次回の
    /// インポートで別記録は正常に戻る（＝一時的な取りこぼし）。「削除済みが復活する」重大側を避けるため、
    /// この安全側（復活させない）の割り切りを採用している。UUID ベースの厳密な除外は将来の改善余地。
    static func retainedImportValues(
        _ values: [HealthKitValues],
        hiddenFields: Set<Int>,
        excludingMinuteKeys: Set<Double> = []
    ) -> [HealthKitValues] {
        values
            .filter { v in
                // 削除しきれなかった記録の「分」に該当するレコードは取り込まない
                if !excludingMinuteKeys.isEmpty,
                   excludingMinuteKeys.contains(minuteKey(v.date)) {
                    return false
                }
                return
                    (!hiddenFields.contains(GraphKind.bp.rawValue)      && v.bpHi > 0)    ||
                    (!hiddenFields.contains(GraphKind.pulse.rawValue)   && v.pulse > 0)   ||
                    (!hiddenFields.contains(GraphKind.temp.rawValue)    && v.temp > 0)    ||
                    (!hiddenFields.contains(GraphKind.weight.rawValue)  && v.weight > 0)  ||
                    (!hiddenFields.contains(GraphKind.bodyFat.rawValue) && v.bodyFat > 0)
            }
            .sorted { $0.date < $1.date }
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
