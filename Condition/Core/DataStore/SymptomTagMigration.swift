// SymptomTagMigration.swift
// 辞書と同じ名前で作られたユーザー追加タグを、辞書の項目へ寄せる後始末
//
// 重複チェックを入れる前は、プリセットにある「花粉症」を手入力すると
// 別IDのユーザー追加タグが作られていた。同じ症状が2つに割れると統計も割れるため、
// 起動時に一度だけタグリストと保存済みレコードをまとめて付け替える。

import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "SymptomTagMigration")

@MainActor
enum SymptomTagMigration {

    /// 最後に寄せたときの辞書の版。
    /// 「一度だけ」にすると、あとから辞書へ語を足したときに生まれる重複を拾えない。
    /// 版を上げれば再度走る
    private static let doneVersionKey = "UDEF_SymptomTagDedupeVersion"
    /// 辞書の内容を変えたら上げる
    private static let catalogVersion = 3

    static func runIfNeeded(context: ModelContext, settings: AppSettings = .shared) {
        let done = UserDefaults.standard.integer(forKey: doneVersionKey)
        guard done < catalogVersion else { return }
        defer { UserDefaults.standard.set(catalogVersion, forKey: doneVersionKey) }

        // 辞書から外した項目のタグを片付ける。
        // 名前の引き先が無くなっており、残すと一覧に生の ID が出てしまう。
        // 自分で名前を付けたタグ（customName あり）は引き先が要らないので残す
        var symptomTags = settings.symptomTags
        if symptomTags.dropOrphans(isKnown: { SymptomCatalog.entry(for: $0) != nil }) {
            settings.symptomTags = symptomTags
        }
        var cleanedMedicine = settings.medicineTags
        if cleanedMedicine.dropOrphans(isKnown: { MedicineCatalog.entry(for: $0) != nil }) {
            settings.medicineTags = cleanedMedicine
        }

        symptomTags = settings.symptomTags
        let symptomReplacements = symptomTags.mergeDuplicatesIntoCatalog {
            SymptomCatalog.matchingID(forName: $0)
        }
        if !symptomReplacements.isEmpty {
            settings.symptomTags = symptomTags
        }

        var medicineTags = settings.medicineTags
        let medicineReplacements = medicineTags.mergeDuplicatesIntoCatalog {
            MedicineCatalog.matchingID(forName: $0)
        }
        if !medicineReplacements.isEmpty {
            settings.medicineTags = medicineTags
        }

        guard !symptomReplacements.isEmpty || !medicineReplacements.isEmpty else { return }

        // 保存済みレコードが旧IDを指したままだと、タグを寄せても集計は割れたままになる
        let records = (try? context.fetch(FetchDescriptor<SymptomRecord>())) ?? []
        var changed = false
        for record in records {
            if let newID = symptomReplacements[record.sSymptomID] {
                record.sSymptomID = newID
                changed = true
            }
            if !medicineReplacements.isEmpty {
                let ids = record.medicineIDs
                let mapped = ids.map { medicineReplacements[$0] ?? $0 }
                if mapped != ids {
                    // 寄せた結果 同じ薬が2つ並ぶことがあるので重複を落とす
                    var seen: Set<String> = []
                    record.medicineIDs = mapped.filter { seen.insert($0).inserted }
                    changed = true
                }
            }
        }
        guard changed else { return }
        do {
            try context.save()
            logger.info("症状タグの重複を統合: 症状\(symptomReplacements.count)件 薬\(medicineReplacements.count)件")
        } catch {
            context.rollback()
            AppAnalytics.shared.record(error: error, name: "symptom_tag_dedupe_failed")
        }
    }
}
