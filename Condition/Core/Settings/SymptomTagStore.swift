// SymptomTagStore.swift
// 症状タグリスト／薬タグリストの保存（UserDefaults に JSON）
//
// 内蔵辞書（SymptomCatalog / MedicineCatalog）は読み取り専用で、
// ユーザーが選んだものだけがこのタグリストへ入る。
// 並び順は「最終使用日時の降順」。手動並べ替えは持たない（使うほど上に来る）。

import Foundation
import SwiftUI

// MARK: - タグ

struct SymptomTag: Codable, Equatable, Identifiable {
    /// 辞書由来は slug（"headache"）、ユーザー追加は "u:<UUID>"
    var id: String
    /// ユーザーが付けた名前。辞書由来で空ならローカライズ名を使う
    var customName: String = ""
    var colorKey: String = ""
    var addedAt: Date = Date()
    var lastUsedAt: Date? = nil
    var useCount: Int = 0
    /// タグリストから外した辞書由来のタグ（過去の記録が参照するため削除はしない）
    var isHidden: Bool = false

    /// ユーザーが辞書外で追加したタグか
    var isUserDefined: Bool { Self.isUserDefinedID(id) }

    static func isUserDefinedID(_ id: String) -> Bool { id.hasPrefix("u:") }

    static func newUserDefinedID() -> String { "u:\(UUID().uuidString)" }

    init(id: String, customName: String = "") {
        self.id = id
        self.customName = customName
    }

    // 欠損キーを既定値で埋めるデコード。
    // 合成された init(from:) は欠損キーで throw するため、あとからフィールドを足すと
    // 保存済みのタグリストが丸ごと復元できなくなる（＝ユーザーが選んだ症状が消える）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        customName = try c.decodeIfPresent(String.self, forKey: .customName) ?? ""
        colorKey   = try c.decodeIfPresent(String.self, forKey: .colorKey) ?? ""
        addedAt    = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        useCount   = try c.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        isHidden   = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}

// MARK: - 表示名・アイコン・色の解決

extension SymptomTag {

    /// 症状としての表示名
    var symptomDisplayName: String {
        if !customName.isEmpty { return customName }
        if let entry = SymptomCatalog.entry(for: id) { return entry.localizedName }
        return id
    }

    /// 薬としての表示名
    var medicineDisplayName: String {
        if !customName.isEmpty { return customName }
        if let entry = MedicineCatalog.entry(for: id) { return entry.localizedName }
        return id
    }

    /// 対処タグの色。薬と薬以外をひと目で見分けられるようにする。
    /// 青×ティールは色相差が22°しかなく、淡く敷くと見分けがつかないので
    /// 補色に近いオレンジ（色相差176°）を使う
    var remedyColor: Color {
        MedicineCatalog.isMedicine(id)
            ? DateOptColorOption.color(for: "blue")
            : DateOptColorOption.color(for: "orange")
    }

    var symptomColor: Color {
        let key = colorKey.isEmpty
            ? (SymptomCatalog.entry(for: id)?.colorKey ?? "gray")
            : colorKey
        return DateOptColorOption.color(for: key)
    }
}

// MARK: - タグリスト（並べ替えと更新の純粋ロジック）

struct SymptomTagList: Codable, Equatable {
    var tags: [SymptomTag] = []

    init(tags: [SymptomTag] = []) {
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = try c.decodeIfPresent([SymptomTag].self, forKey: .tags) ?? []
    }

    /// 表示順。最終使用日時の降順 → 未使用は追加順
    var ordered: [SymptomTag] {
        tags.filter { !$0.isHidden }.sorted(by: Self.isOrderedBefore)
    }

    /// 非表示にしたものも含めた全タグ（選択シートで選び直せるようにするため）。
    /// ユーザー追加タグは辞書に無いので、ここに出さないと復活経路が無くなる
    var orderedIncludingHidden: [SymptomTag] {
        tags.sorted(by: Self.isOrderedBefore)
    }

    /// 記録画面のタグ行に出す上位 n 件
    func frequentlyUsed(limit: Int) -> [SymptomTag] {
        Array(ordered.prefix(limit))
    }

    func contains(_ id: String) -> Bool {
        tags.contains { $0.id == id }
    }

    func tag(for id: String) -> SymptomTag? {
        tags.first { $0.id == id }
    }

    /// 並び順の判定。使ったものが必ず未使用より前に来る
    static func isOrderedBefore(_ lhs: SymptomTag, _ rhs: SymptomTag) -> Bool {
        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case let (l?, r?):
            if l != r { return l > r }
            return lhs.addedAt < rhs.addedAt
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return lhs.addedAt < rhs.addedAt
        }
    }

    // MARK: 更新

    /// 辞書から選ばれたタグを追加する。既にあれば何もしない
    mutating func add(id: String, customName: String = "") {
        guard !contains(id) else { return }
        tags.append(SymptomTag(id: id, customName: Self.limitedName(customName)))
    }

    /// タグ名を切り詰める。追加とリネームで同じ規則にする
    static func limitedName(_ name: String) -> String {
        String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(SymptomLimits.tagNameMaxLength)
        )
    }

    /// 使用を記録する（最終使用日時を今にし、使用回数を1つ増やす）。
    /// リストに無い ID は追加してから記録する（インポート由来の記録を開いた場合など）
    mutating func markUsed(id: String, at date: Date = Date()) {
        guard !id.isEmpty else { return }
        if let index = tags.firstIndex(where: { $0.id == id }) {
            tags[index].lastUsedAt = date
            tags[index].useCount += 1
            tags[index].isHidden = false
        } else {
            var tag = SymptomTag(id: id)
            tag.lastUsedAt = date
            tag.useCount = 1
            tags.append(tag)
        }
    }

    /// タグリストから外す。実体は消さず非表示にするだけ。
    ///
    /// ユーザー追加タグを本当に削除すると、そのタグを使った過去の記録は
    /// `u:<UUID>` を持ったまま名前を引く先を失い、一覧に UUID が出てしまう。
    /// 辞書由来・ユーザー追加のどちらも非表示に留める。
    mutating func remove(id: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].isHidden = true
    }

    /// どの記録からも参照されていないユーザー追加タグだけを本当に消す。
    /// 使用中の ID を呼び出し側から渡してもらう（ここからは記録を見られないため）
    mutating func purgeUnusedUserDefined(usedIDs: Set<String>) {
        tags.removeAll { $0.isUserDefined && $0.isHidden && !usedIDs.contains($0.id) }
    }

    /// 辞書と同じ名前で作られてしまったユーザー追加タグを、辞書の項目へ寄せる。
    /// 重複チェックを入れる前に作られた分（例:「花粉症」）を掃除するために使う。
    /// - Returns: 置き換えが必要だった `旧ID → 新ID` の対応
    @discardableResult
    mutating func mergeDuplicatesIntoCatalog(
        resolve: (String) -> String?
    ) -> [String: String] {
        var replacements: [String: String] = [:]
        for tag in tags where tag.isUserDefined && !tag.customName.isEmpty {
            guard let catalogID = resolve(tag.customName), catalogID != tag.id else { continue }
            replacements[tag.id] = catalogID
        }
        guard !replacements.isEmpty else { return [:] }

        for (oldID, newID) in replacements {
            guard let oldIndex = tags.firstIndex(where: { $0.id == oldID }) else { continue }
            let old = tags[oldIndex]
            tags.remove(at: oldIndex)
            if let newIndex = tags.firstIndex(where: { $0.id == newID }) {
                // 既に辞書側のタグがあるなら使用実績だけ引き継ぐ
                tags[newIndex].useCount += old.useCount
                tags[newIndex].isHidden = false
                if let lastUsed = old.lastUsedAt,
                   tags[newIndex].lastUsedAt.map({ $0 < lastUsed }) ?? true {
                    tags[newIndex].lastUsedAt = lastUsed
                }
            } else {
                var moved = old
                moved.id = newID
                moved.customName = ""   // 辞書のローカライズ名を使う
                tags.append(moved)
            }
        }
        return replacements
    }

    mutating func rename(id: String, to name: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].customName = Self.limitedName(name)
    }
}

// MARK: - 保存

enum SymptomTagStore {

    // MARK: 症状

    static func symptomTags() -> SymptomTagList {
        load(key: SettingsKeys.settSymptomTags, defaultIDs: SymptomCatalog.defaultTagIDs)
    }

    static func saveSymptomTags(_ list: SymptomTagList) {
        save(list, key: SettingsKeys.settSymptomTags)
    }

    // MARK: 薬

    static func medicineTags() -> SymptomTagList {
        load(key: SettingsKeys.settMedicineTags, defaultIDs: MedicineCatalog.defaultTagIDs)
    }

    static func saveMedicineTags(_ list: SymptomTagList) {
        save(list, key: SettingsKeys.settMedicineTags)
    }

    // MARK: 共通

    private static func load(key: String, defaultIDs: [String]) -> SymptomTagList {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SymptomTagList.self, from: data) else {
            // 初回はリストが空だと記録画面に何も出ないので、既定の症状を入れておく
            return SymptomTagList(tags: defaultIDs.map { SymptomTag(id: $0) })
        }
        return decoded
    }

    private static func save(_ list: SymptomTagList, key: String) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
