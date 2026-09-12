// EquipmentCandidateStore.swift
// 測定場所・機器の入力候補を作る共有ロジック

import Foundation
import Observation

/// 測定場所・機器の候補プールを、履歴が変わったときだけ作り直して保持する。
///
/// 候補プールの集計は全記録の走査と並べ替えを伴うため、計算プロパティのままだと
/// 1文字入力するたびに（しかも絞り込みと描画から複数回）同じ集計が走ってしまう。
/// 記録数に比例して重くなるので、履歴の変更を検知したときだけ再集計する。
@Observable
final class EquipmentCandidateStore {
    /// 候補に表示する最大件数
    static let candidateLimit = 20

    /// 利用頻度順に並べた候補プール（プリセット含む）
    private(set) var candidates: [String] = []

    /// 最後に集計したときの履歴の中身。これが変わったときだけ作り直す。
    private var lastSignature: [String]?

    /// 履歴が変わっていれば候補プールを作り直す
    func refresh(with records: [BodyRecord]) {
        // sEquipment だけが候補に効くので、その並びが同じなら再集計しない
        let signature = records.map(\.sEquipment)
        if signature == lastSignature { return }
        lastSignature = signature
        candidates = Self.makeCandidates(from: signature)
    }

    /// 入力語へ前方一致する候補を優先し、部分一致を続ける
    func shownCandidates(matching keyword: String) -> [String] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return Array(candidates.prefix(Self.candidateLimit))
        }
        let lowercasedKeyword = keyword.lowercased()
        var prefixMatches: [String] = []
        var containsMatches: [String] = []
        for candidate in candidates {
            if candidate.lowercased().hasPrefix(lowercasedKeyword) {
                prefixMatches.append(candidate)
            } else if candidate.localizedCaseInsensitiveContains(keyword) {
                containsMatches.append(candidate)
            }
        }
        // 入力語そのものと一致する候補しか残らないなら、選ぶ意味がないので出さない
        if prefixMatches.count + containsMatches.count == 1,
           let only = prefixMatches.first ?? containsMatches.first,
           only.compare(keyword, options: .caseInsensitive) == .orderedSame {
            return []
        }
        return Array((prefixMatches + containsMatches).prefix(Self.candidateLimit))
    }

    /// 履歴の使用回数順（同数なら名前順）に、末尾へプリセットを足した候補を作る
    private static func makeCandidates(from equipments: [String]) -> [String] {
        let presets = [
            String(localized: "record.device.preset.home"),
            String(localized: "record.device.preset.hospital"),
            String(localized: "record.device.preset.gym")
        ]
        var counts: [String: Int] = [:]
        for equipment in equipments {
            let value = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { counts[value, default: 0] += 1 }
        }
        let history = counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount == rhsCount {
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            return rhsCount < lhsCount
        }
        var values: [String] = []
        var seen: Set<String> = []
        for value in history + presets {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || seen.contains(trimmed) { continue }
            seen.insert(trimmed)
            values.append(trimmed)
        }
        return values
    }
}
