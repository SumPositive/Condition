// MigrationService.swift
// Core Data（旧 AzBodyNote）→ SwiftData（新 Condition）への移行処理
// 初回起動時のみ1度だけ実行する。失敗しても旧データは保全する。

import Foundation
import CoreData
import SwiftData
import SQLite3
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "Migration")

@Observable
@MainActor
final class MigrationService {

    // MARK: - 状態
    enum Phase: Equatable {
        case idle
        case checking
        case migrating(progress: Double)
        case done
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.done, .done): return true
            case (.migrating(let a), .migrating(let b)): return a == b
            case (.failed(let a), .failed(let b)):       return a == b
            default: return false
            }
        }
    }

    var phase: Phase = .idle

    // MARK: - エントリポイント

    func migrateIfNeeded(context: ModelContext) async {
        phase = .checking

        #if DEBUG
        // fastlane snapshot 撮影時は in-memory の投入済みデータをそのまま使う
        // 移行処理には触れず即座に本編へ進める
        if SnapshotSeed.isActive {
            phase = .done
            return
        }
        #endif

        // 旧 SQLite ファイル検索（フラグより先に確認）
        // iCloud バックアップから migrationDone フラグが復元される場合があるため
        // ファイルの有無を正とする
        guard let oldStoreURL = findOldStoreURL() else {
            if !UserDefaults.standard.bool(forKey: UDefKeys.migrationDone) {
                logger.info("旧データなし → 新規インストール")
                UserDefaults.standard.set(true, forKey: UDefKeys.migrationDone)
            }
            phase = .done
            return
        }

        logger.info("旧データ発見: \(oldStoreURL.path)")
        await performMigration(from: oldStoreURL, context: context)
    }

    /// 移行をスキップして続行（migrationDone は立てない → 次回アップデートで自動再試行）
    func skipMigration() {
        logger.info("移行スキップ → 次回アップデートで自動再試行")
        phase = .done
    }

    // MARK: - 旧ファイル検索

    private func findOldStoreURL() -> URL? {
        // migrationDone=true の場合 AzBodyNote.sqlite は SwiftData のストア
        // CoreData 移行元と混同しないよう検索しない
        guard !UserDefaults.standard.bool(forKey: UDefKeys.migrationDone) else { return nil }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let documents  = fm.urls(for: .documentDirectory,           in: .userDomainMask).first!
        // 旧 Objective-C アプリは Documents/ に保存していた可能性があるため両方探す
        let candidates = [
            appSupport.appendingPathComponent("AzBodyNote.sqlite"),
            appSupport.appendingPathComponent("AzBodyNote/AzBodyNote.sqlite"),
            documents.appendingPathComponent("AzBodyNote.sqlite"),
            documents.appendingPathComponent("AzBodyNote/AzBodyNote.sqlite"),
        ]
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    // MARK: - 移行実行

    private func performMigration(from oldStoreURL: URL, context: ModelContext) async {
        do {
            // 改善案3: WAL 欠損補修（iCloud 復元後にファイルだけ残るケース対策）
            repairWALIfNeeded(at: oldStoreURL)

            // 改善案4: CoreData で取得を試み、失敗したら SQLite 直接読み取りへフォールバック
            let rows: [[String: Any]]
            do {
                let oldContainer = try await makeOldContainer(storeURL: oldStoreURL)
                rows = try fetchViaCoreData(container: oldContainer)
                logger.info("CoreData 経由で取得: \(rows.count) 件")
            } catch {
                logger.warning("CoreData open 失敗、SQLite 直接読み取りへフォールバック: \(error)")
                AppAnalytics.shared.record(error: error, name: "migration_coredata_open_failed")
                rows = try fetchViaSQLite(from: oldStoreURL)
                logger.info("SQLite 直接読み取りで取得: \(rows.count) 件")
            }

            // SwiftData へ挿入
            try insertRows(rows, context: context)

            // データ移行成功。旧ファイルを .done へ退避できたときだけ移行完了フラグを立てる。
            // 退避に失敗したらフラグを立てず、次回起動で自動再試行する
            // （データは移行済みなので画面は先へ進める。再移行は秒単位重複チェックで冪等）
            if archiveOldStore(at: oldStoreURL) {
                UserDefaults.standard.set(true, forKey: UDefKeys.migrationDone)
            } else {
                logger.warning("旧ファイルのアーカイブに失敗 → migrationDone を立てず次回再試行")
            }
            phase = .done

        } catch {
            logger.error("移行失敗: \(error.localizedDescription)")
            AppAnalytics.shared.record(error: error, name: "migration_failed")
            // 旧ファイルはそのまま残す → 次回アップデートで自動再試行
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - 改善案3: WAL 欠損補修

    private func repairWALIfNeeded(at storeURL: URL) {
        let fm = FileManager.default
        for ext in ["-wal", "-shm"] {
            let auxURL = URL(fileURLWithPath: storeURL.path + ext)
            if !fm.fileExists(atPath: auxURL.path) {
                fm.createFile(atPath: auxURL.path, contents: Data())
                logger.info("WAL 補修: \(auxURL.lastPathComponent) を空ファイルで作成")
            }
        }
    }

    // MARK: - 改善案5: CoreData コンテナ生成（async / withCheckedThrowingContinuation）

    private func makeOldContainer(storeURL: URL) async throws -> NSPersistentContainer {
        let entity = NSEntityDescription()
        entity.name = "E2record"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let attrs: [(String, NSAttributeType)] = [
            ("bCaution",       .stringAttributeType),
            ("dateTime",       .dateAttributeType),
            ("nDateOpt",       .integer32AttributeType),
            ("nYearMM",        .integer32AttributeType),
            ("sEventID",       .stringAttributeType),
            ("sGSpreadID",     .stringAttributeType),
            ("sNote1",         .stringAttributeType),
            ("sNote2",         .stringAttributeType),
            ("sEquipment",     .stringAttributeType),
            ("nBpHi_mmHg",     .integer16AttributeType),
            ("nBpLo_mmHg",     .integer16AttributeType),
            ("nPulse_bpm",     .integer16AttributeType),
            ("nTemp_10c",      .integer16AttributeType),
            ("nWeight_10Kg",   .integer32AttributeType),
            ("nBodyFat_10p",   .integer32AttributeType),
            ("nSkMuscle_10p",  .integer32AttributeType),
        ]

        for (name, type) in attrs {
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = true
            entity.properties.append(attr)
        }

        let model = NSManagedObjectModel()
        model.entities = [entity]

        let container = NSPersistentContainer(name: "AzBodyNote", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.isReadOnly = true
        desc.setOption(true as NSNumber, forKey: NSIgnorePersistentStoreVersioningOption)
        desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [desc]

        // 改善案5: コールバックを async/await でラップ
        return try await withCheckedThrowingContinuation { continuation in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: container)
                }
            }
        }
    }

    // MARK: - CoreData 経由フェッチ

    private func fetchViaCoreData(container: NSPersistentContainer) throws -> [[String: Any]] {
        let oldContext = container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "E2record")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "dateTime", ascending: true)]
        let allRecords = try oldContext.fetch(fetchRequest)

        let keys = ["nDateOpt", "bCaution", "sNote1", "sNote2", "sEquipment",
                    "nBpHi_mmHg", "nBpLo_mmHg", "nPulse_bpm", "nTemp_10c",
                    "nWeight_10Kg", "nBodyFat_10p", "nSkMuscle_10p"]

        return allRecords.compactMap { obj -> [String: Any]? in
            guard let dateTime = obj.value(forKey: "dateTime") as? Date else { return nil }
            var row: [String: Any] = ["dateTime": dateTime]
            for key in keys {
                if let v = obj.value(forKey: key) { row[key] = v }
            }
            return row
        }
    }

    // MARK: - 改善案4: SQLite 直接読み取り（CoreData open 失敗時のフォールバック）
    //
    // CoreData の SQLite 列名規則: "Z" + attributeName.uppercased()
    //   dateTime      → ZDATETIME
    //   nDateOpt      → ZNDATEOPT
    //   bCaution      → ZBCAUTION  (TEXT "YES"/"NO")
    //   nBpHi_mmHg    → ZNBPHI_MMHG
    //   nSkMuscle_10p → ZNSKMUSCLE_10P
    // テーブル名: "Z" + entityName.uppercased() = ZE2RECORD
    // 日付: 2001-01-01 UTC (NSDate reference date) からの秒数 (REAL)

    private func fetchViaSQLite(from storeURL: URL) throws -> [[String: Any]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            throw MigrationError.sqliteOpenFailed(storeURL.path)
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
                ZDATETIME,
                ZNDATEOPT,
                ZBCAUTION,
                ZSNOTE1,
                ZSNOTE2,
                ZSEQUIPMENT,
                ZNBPHI_MMHG,
                ZNBPLO_MMHG,
                ZNPULSE_BPM,
                ZNTEMP_10C,
                ZNWEIGHT_10KG,
                ZNBODYFAT_10P,
                ZNSKMUSCLE_10P
            FROM ZE2RECORD
            ORDER BY ZDATETIME ASC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MigrationError.sqliteQueryFailed
        }
        defer { sqlite3_finalize(stmt) }

        // CoreData の日付基準: 2001-01-01 00:00:00 UTC
        let coreDataEpoch: TimeInterval = 978_307_200

        var rows: [[String: Any]] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            // ZDATETIME: 2001-01-01 からの秒数 (REAL)
            guard sqlite3_column_type(stmt, 0) != SQLITE_NULL else { continue }
            let rawDate = sqlite3_column_double(stmt, 0)
            let dateTime = Date(timeIntervalSince1970: rawDate + coreDataEpoch)

            var row: [String: Any] = ["dateTime": dateTime]

            if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                row["nDateOpt"] = Int(sqlite3_column_int(stmt, 1))
            }
            // bCaution: TEXT "YES"/"NO" または INTEGER 0/1 の両方を許容
            if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                switch sqlite3_column_type(stmt, 2) {
                case SQLITE_TEXT:
                    if let ptr = sqlite3_column_text(stmt, 2) { row["bCaution"] = String(cString: ptr) }
                case SQLITE_INTEGER:
                    row["bCaution"] = sqlite3_column_int(stmt, 2) != 0 ? "YES" : "NO"
                default: break
                }
            }
            if let ptr = sqlite3_column_text(stmt, 3) { row["sNote1"]     = String(cString: ptr) }
            if let ptr = sqlite3_column_text(stmt, 4) { row["sNote2"]     = String(cString: ptr) }
            if let ptr = sqlite3_column_text(stmt, 5) { row["sEquipment"] = String(cString: ptr) }

            let intCols: [(Int32, String)] = [
                (6,  "nBpHi_mmHg"),
                (7,  "nBpLo_mmHg"),
                (8,  "nPulse_bpm"),
                (9,  "nTemp_10c"),
                (10, "nWeight_10Kg"),
                (11, "nBodyFat_10p"),
                (12, "nSkMuscle_10p"),
            ]
            for (idx, key) in intCols where sqlite3_column_type(stmt, idx) != SQLITE_NULL {
                row[key] = Int(sqlite3_column_int(stmt, idx))
            }

            rows.append(row)
        }

        return rows
    }

    // MARK: - SwiftData への挿入（CoreData / SQLite 両パス共通）

    /// CoreData→SQLite フォールバック等で発生する subsecond 精度のズレを吸収するため、
    /// 重複判定は秒単位に丸めた日時で行う
    private static func normalizedSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private func insertRows(_ rows: [[String: Any]], context: ModelContext) throws {
        // 再試行時の重複防止：既存レコードの dateTime（秒単位に正規化）を収集
        // スキップ後に新規入力したデータは別の dateTime を持つため消えない
        let existing = try context.fetch(FetchDescriptor<BodyRecord>())
        // 挿入のたびに秒単位の日時を追加していくので var（移行元内の同一秒重複も弾く）
        var existingDates = Set(existing.map { Self.normalizedSecond($0.dateTime) })
        if !existingDates.isEmpty {
            logger.info("既存レコード \(existingDates.count) 件を重複チェック対象に追加")
        }

        let batchSize = 100
        var processed = 0
        var skipped   = 0

        for row in rows {
            guard let dateTime = row["dateTime"] as? Date else { continue }

            if dateTime >= BodyRecord.goalDate {
                migrateGoalRecord(row)
                processed += 1
                continue
            }

            // 同じ dateTime（秒単位）が既にあればスキップ（重複挿入防止）
            let normalized = Self.normalizedSecond(dateTime)
            guard !existingDates.contains(normalized) else {
                skipped += 1
                continue
            }

            let body = convertToBodyRecord(row, dateTime: dateTime)
            context.insert(body)
            // 移行元に同一秒の行が複数あっても二重挿入しないよう、挿入した秒をセットへ加える
            existingDates.insert(normalized)
            processed += 1

            if processed % batchSize == 0 {
                try context.save()
                let progress = Double(processed) / Double(rows.count)
                phase = .migrating(progress: progress)
                logger.info("移行中: \(processed)/\(rows.count)")
            }
        }

        try context.save()
        logger.info("移行完了: \(processed) 件挿入, \(skipped) 件スキップ（重複）")
    }

    // MARK: - レコード変換（[String: Any] → BodyRecord）

    private func convertToBodyRecord(_ row: [String: Any], dateTime: Date) -> BodyRecord {
        let record = BodyRecord(dateTime: dateTime)

        if let v = row["nDateOpt"] as? Int { record.nDateOpt = v }

        if let v = row["bCaution"] as? String {
            record.bCaution = (v == "YES")
        } else if let v = row["bCaution"] as? Bool {
            record.bCaution = v
        }

        record.sNote1     = (row["sNote1"]     as? String) ?? ""
        record.sNote2     = (row["sNote2"]     as? String) ?? ""
        record.sEquipment = (row["sEquipment"] as? String) ?? ""

        record.nBpHi_mmHg    = (row["nBpHi_mmHg"]    as? Int) ?? 0
        record.nBpLo_mmHg    = (row["nBpLo_mmHg"]    as? Int) ?? 0
        record.nPulse_bpm    = (row["nPulse_bpm"]    as? Int) ?? 0
        record.nTemp_10c     = (row["nTemp_10c"]     as? Int) ?? 0
        record.nWeight_10Kg  = (row["nWeight_10Kg"]  as? Int) ?? 0
        record.nBodyFat_10p  = (row["nBodyFat_10p"]  as? Int) ?? 0
        record.nSkMuscle_10p = (row["nSkMuscle_10p"] as? Int) ?? 0

        return record
    }

    // MARK: - 目標値レコード → AppSettings へ書き出し

    private func migrateGoalRecord(_ row: [String: Any]) {
        let settings = AppSettings.shared
        if let v = row["nBpHi_mmHg"]    as? Int, v > 0 { settings.goalBpHi      = v }
        if let v = row["nBpLo_mmHg"]    as? Int, v > 0 { settings.goalBpLo      = v }
        if let v = row["nPulse_bpm"]    as? Int, v > 0 { settings.goalPulse     = v }
        if let v = row["nWeight_10Kg"]  as? Int, v > 0 { settings.goalWeight    = v }
        if let v = row["nTemp_10c"]     as? Int, v > 0 { settings.goalTemp      = v }
        if let v = row["nBodyFat_10p"]  as? Int, v > 0 { settings.goalBodyFat   = v }
        if let v = row["nSkMuscle_10p"] as? Int, v > 0 { settings.goalSkMuscle  = v }
        logger.info("目標値レコードを AppSettings へ書き出し完了")
    }

    // MARK: - 旧ファイルアーカイブ（データ移行成功時のみ呼ぶ）
    //
    // 成功 → 主ファイル(.sqlite)を .done にリネーム（findOldStoreURL は .sqlite のみ検索するので再検出されない）
    // 失敗 → リネームしない（.sqlite のまま残る）。呼び出し元は migrationDone を立てず、
    //        次回アップデートで自動再試行する（再移行は秒単位重複チェックで冪等）

    /// 旧ファイルを .done へリネームする。主ファイル(.sqlite)を確実に退避できたかを返す。
    @discardableResult
    private func archiveOldStore(at url: URL) -> Bool {
        let fm = FileManager.default
        var mainArchived = false
        for ext in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: url.path + ext)
            let dst = URL(fileURLWithPath: url.path + ext + ".done")
            guard fm.fileExists(atPath: src.path) else {
                // 主ファイルが無ければ既に退避済み扱い（.sqlite が残らないので再検出されない）
                if ext.isEmpty { mainArchived = true }
                continue
            }
            do {
                try fm.moveItem(at: src, to: dst)
                if ext.isEmpty { mainArchived = true }
            } catch {
                logger.error("旧ファイルの .done リネーム失敗: \(src.lastPathComponent, privacy: .public) - \(error.localizedDescription, privacy: .public)")
                AppAnalytics.shared.record(error: error, name: "migration_archive_failed")
            }
        }
        if mainArchived {
            logger.info("旧ファイルを .done にリネーム完了")
        }
        return mainArchived
    }
}

// MARK: - エラー型

private enum MigrationError: LocalizedError {
    case sqliteOpenFailed(String)
    case sqliteQueryFailed

    var errorDescription: String? {
        switch self {
        case .sqliteOpenFailed(let path): return "SQLite ファイルを開けませんでした: \(path)"
        case .sqliteQueryFailed:          return "SQLite クエリに失敗しました"
        }
    }
}
