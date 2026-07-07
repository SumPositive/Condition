// ModelContainer+Setup.swift
// SwiftData ModelContainer の設定

import SwiftData
import Foundation
import SQLite3
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "ModelContainer")

// SwiftData は ModelConfiguration の name を使って "<name>.store" という
// ファイルを Application Support に作成する（.sqlite ではない）
private let storeExt = ".store"

extension ModelContainer {

    @MainActor
    static var shared: ModelContainer = {
        #if DEBUG
        // fastlane snapshot 撮影時は in-memory ストアにサンプルを入れて撮る
        // 実ストアやマイグレーションには一切触れない
        if SnapshotSeed.isActive {
            let config = ModelConfiguration(schema: Schema([BodyRecord.self]),
                                            isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(for: BodyRecord.self, configurations: config)
                SnapshotSeed.seedIfNeeded(context: container.mainContext)
                logger.info("snapshot 撮影用の in-memory ストアを使用")
                return container
            } catch {
                fatalError("snapshot 用 ModelContainer の作成に失敗しました: \(error)")
            }
        }
        #endif

        let schema = Schema([BodyRecord.self])
        let storeName = resolveStoreName()
        logger.info("使用ストア: \(storeName)\(storeExt)")

        let config = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: BodyRecord.self, configurations: config)
        } catch {
            AppAnalytics.shared.record(error: error, name: "model_container_create_failed")
            fatalError("ModelContainer の作成に失敗しました: \(error)")
        }
    }()

    // MARK: - ストア名決定

    private static func resolveStoreName() -> String {
        let fm          = FileManager.default
        let appSupport  = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let conditionURL  = appSupport.appendingPathComponent("Condition\(storeExt)")
        let azBodyNoteURL = appSupport.appendingPathComponent("AzBodyNote\(storeExt)")

        let conditionExists  = fm.fileExists(atPath: conditionURL.path)
        let azBodyNoteExists = fm.fileExists(atPath: azBodyNoteURL.path)
        let migrationDone    = UserDefaults.standard.bool(forKey: UDefKeys.migrationDone)

        switch (conditionExists, azBodyNoteExists, migrationDone) {

        // ケース1: Condition のみ存在 → 通常ケース
        case (true, false, _):
            return "Condition"

        // ケース2: どちらも存在しない → 新規インストール
        case (false, false, _):
            return "Condition"

        // ケース3: AzBodyNote のみ存在 かつ migrationDone=true
        //   → renameSwiftDataStoreIfNeeded が未実行または失敗
        case (false, true, true):
            logger.warning("ケース3: Condition なし・AzBodyNote あり → リネーム再試行")
            let renamed = attemptRename(from: azBodyNoteURL, to: conditionURL, fm: fm)
            return renamed ? "Condition" : "AzBodyNote"

        // ケース4: 両方存在 かつ migrationDone=true
        //   → リネーム失敗後に空の Condition が作られた可能性
        case (true, true, true):
            logger.warning("ケース4: 両方存在 → レコード有無を確認して判定")
            return resolveConflict(conditionURL: conditionURL,
                                   azBodyNoteURL: azBodyNoteURL, fm: fm)

        // migrationDone=false → CoreData 移行前ユーザー
        // AzBodyNote.store は CoreData ファイルではないが移行前は触らない
        default:
            return "Condition"
        }
    }

    /// ケース4: 両方存在する場合にレコード有無で判定
    private static func resolveConflict(conditionURL: URL,
                                        azBodyNoteURL: URL,
                                        fm: FileManager) -> String {
        let conditionHasData  = sqliteHasRecords(at: conditionURL)
        let azBodyNoteHasData = sqliteHasRecords(at: azBodyNoteURL)

        switch (conditionHasData, azBodyNoteHasData) {
        case (true, _):
            logger.info("ケース4: Condition にデータあり → Condition を使用")
            return "Condition"
        case (false, true):
            logger.warning("ケース4: Condition が空・AzBodyNote にデータあり → 復元")
            archiveEmpty(conditionURL, fm: fm)
            let renamed = attemptRename(from: azBodyNoteURL, to: conditionURL, fm: fm)
            return renamed ? "Condition" : "AzBodyNote"
        case (false, false):
            logger.info("ケース4: 両方空 → Condition を使用")
            return "Condition"
        }
    }

    // MARK: - SQLite レコード有無チェック

    /// ユーザーデータのレコードが1件以上あるか確認
    /// SwiftData/CoreData の .store ファイルは中身は SQLite なので sqlite3 で直接読める
    private static func sqliteHasRecords(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            logger.error("SQLite open 失敗: \(url.lastPathComponent)")
            return false
        }
        defer { sqlite3_close(db) }

        var tableStmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            -1, &tableStmt, nil
        ) == SQLITE_OK, let tableStmt else { return false }
        defer { sqlite3_finalize(tableStmt) }

        var tables: [String] = []
        while sqlite3_step(tableStmt) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(tableStmt, 0) {
                tables.append(String(cString: ptr))
            }
        }
        logger.info("\(url.lastPathComponent) テーブル: \(tables.joined(separator: ", "))")

        let metadataTables: Set<String> = ["Z_METADATA", "Z_MODELCACHE", "Z_PRIMARYKEY"]
        let userTables = tables.filter { !metadataTables.contains($0) }

        for table in userTables {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT 1 FROM \"\(table)\" LIMIT 1",
                                   -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    logger.info("\(url.lastPathComponent).\(table): レコードあり")
                    return true
                }
            }
        }
        logger.info("\(url.lastPathComponent): ユーザーデータなし")
        return false
    }

    // MARK: - ユーティリティ

    /// 空の Condition.store を .empty にリネーム（デバッグ用に保持）
    private static func archiveEmpty(_ url: URL, fm: FileManager) {
        for ext in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: url.path + ext)
            let dst = URL(fileURLWithPath: url.path + ext + ".empty")
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dst)
            }
        }
        logger.info("空の \(url.lastPathComponent) を .empty にリネーム")
    }

    /// リネーム実行（ログ付き）。主ファイルのリネーム成否を返す
    @discardableResult
    private static func attemptRename(from srcBase: URL, to dstBase: URL,
                                      fm: FileManager) -> Bool {
        var mainSucceeded = false
        for ext in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: srcBase.path + ext)
            let dst = URL(fileURLWithPath: dstBase.path + ext)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try fm.moveItem(at: src, to: dst)
                if ext == "" { mainSucceeded = true }
                logger.info("リネーム成功: \(src.lastPathComponent) → \(dst.lastPathComponent)")
            } catch {
                logger.error("リネーム失敗: \(src.lastPathComponent) - \(error)")
            }
        }
        return mainSucceeded
    }

    // MARK: - 事前リネーム（ConditionApp.init から呼ぶ）

    /// SwiftData ストアを "AzBodyNote" → "Condition" へ事前リネーム
    /// 失敗しても resolveStoreName() がフォールバックするので致命的にならない
    static func renameSwiftDataStoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: UDefKeys.migrationDone) else { return }

        let fm         = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let srcBase    = appSupport.appendingPathComponent("AzBodyNote\(storeExt)")
        let dstBase    = appSupport.appendingPathComponent("Condition\(storeExt)")

        guard fm.fileExists(atPath: srcBase.path)  else { return }
        guard !fm.fileExists(atPath: dstBase.path) else { return }

        attemptRename(from: srcBase, to: dstBase, fm: fm)
    }
}
