// SymptomCatalog.swift
// 内蔵の症状辞書（読み取り専用・46件）と薬辞書（17件）
//
// レコードには表示名ではなく ID を保存する。
// 表示名を保存すると、4言語（ja/en/ko/zh-Hant）で集計キーが言語ごとに割れてしまうため。
// ユーザーが辞書から選んだものだけが「症状タグリスト」に入る（SymptomTagStore）。

import Foundation
import SwiftUI

// MARK: - 分類

enum SymptomCategory: String, CaseIterable, Codable, Identifiable {
    case head            // 頭・神経
    case systemic        // 全身
    case digestive       // 消化器
    case respiratory     // 呼吸器・耳鼻
    case musculoskeletal // 筋・骨格
    case circulatory     // 循環器
    case skin            // 皮膚
    case eye             // 眼
    case oral            // 口腔
    case mental          // 精神
    case womens          // 女性

    var id: String { rawValue }

    var labelKey: String { "symptom.category.\(rawValue)" }

    var icon: String {
        switch self {
        case .head:            return "brain.head.profile"
        case .systemic:        return "figure.stand"
        case .digestive:       return "fork.knife"
        case .respiratory:     return "lungs.fill"
        case .musculoskeletal: return "figure.walk"
        case .circulatory:     return "heart.fill"
        case .skin:            return "hand.raised.fill"
        case .eye:             return "eye.fill"
        case .oral:            return "mouth.fill"
        case .mental:          return "cloud.rain.fill"
        case .womens:          return "figure.dress.line.vertical.figure"
        }
    }

    var colorKey: String {
        switch self {
        case .head:            return "purple"
        case .systemic:        return "orange"
        case .digestive:       return "brown"
        case .respiratory:     return "cyan"
        case .musculoskeletal: return "teal"
        case .circulatory:     return "red"
        case .skin:            return "pink"
        case .eye:             return "indigo"
        case .oral:            return "blue"
        case .mental:          return "gray"
        case .womens:          return "pink"
        }
    }
}

// MARK: - 辞書エントリ

struct SymptomCatalogEntry: Identifiable, Equatable {
    /// レコードへ保存する安定キー（slug）
    let id: String
    let category: SymptomCategory
    /// HealthKit の HKCategoryTypeIdentifier 名。空ならアプリ内のみで扱う。
    /// 実際の書き出しはフェーズ6。識別子の綴りと利用可否は実装時に SDK で要確認。
    let healthKitIdentifier: String

    var labelKey: String { "symptom.name.\(id)" }
    var colorKey: String { category.colorKey }

    /// 現在の言語での表示名
    var localizedName: String { NSLocalizedString(labelKey, comment: "") }
}

// MARK: - 症状辞書

enum SymptomCatalog {

    static let all: [SymptomCatalogEntry] = [
        // 頭・神経
        .init(id: "headache",            category: .head, healthKitIdentifier: "headache"),
        .init(id: "dizziness",           category: .head, healthKitIdentifier: "dizziness"),
        .init(id: "lightheadedness",     category: .head, healthKitIdentifier: ""),
        .init(id: "numbness",            category: .head, healthKitIdentifier: ""),
        .init(id: "scintillatingScotoma", category: .head, healthKitIdentifier: ""),
        .init(id: "insomnia",            category: .head, healthKitIdentifier: "sleepChanges"),
        .init(id: "drowsiness",          category: .head, healthKitIdentifier: "sleepChanges"),
        // 全身
        .init(id: "fever",               category: .systemic, healthKitIdentifier: "fever"),
        .init(id: "fatigue",             category: .systemic, healthKitIdentifier: "fatigue"),
        .init(id: "chills",              category: .systemic, healthKitIdentifier: "chills"),
        .init(id: "nightSweats",         category: .systemic, healthKitIdentifier: "nightSweats"),
        .init(id: "edema",               category: .systemic, healthKitIdentifier: ""),
        .init(id: "coldSensitivity",     category: .systemic, healthKitIdentifier: ""),
        // 消化器
        .init(id: "abdominalPain",       category: .digestive, healthKitIdentifier: "abdominalCramps"),
        .init(id: "nausea",              category: .digestive, healthKitIdentifier: "nausea"),
        .init(id: "diarrhea",            category: .digestive, healthKitIdentifier: "diarrhea"),
        .init(id: "constipation",        category: .digestive, healthKitIdentifier: "constipation"),
        .init(id: "heartburn",           category: .digestive, healthKitIdentifier: "heartburn"),
        .init(id: "bloating",            category: .digestive, healthKitIdentifier: "bloating"),
        .init(id: "appetiteLoss",        category: .digestive, healthKitIdentifier: ""),
        // 呼吸器・耳鼻
        .init(id: "cough",               category: .respiratory, healthKitIdentifier: "coughing"),
        .init(id: "phlegm",              category: .respiratory, healthKitIdentifier: ""),
        .init(id: "runnyNose",           category: .respiratory, healthKitIdentifier: "runnyNose"),
        .init(id: "soreThroat",          category: .respiratory, healthKitIdentifier: "soreThroat"),
        .init(id: "shortnessOfBreath",   category: .respiratory, healthKitIdentifier: "shortnessOfBreath"),
        .init(id: "hayFever",            category: .respiratory, healthKitIdentifier: ""),
        .init(id: "tinnitus",            category: .respiratory, healthKitIdentifier: ""),
        .init(id: "earFullness",         category: .respiratory, healthKitIdentifier: ""),
        // 筋・骨格
        .init(id: "backPain",            category: .musculoskeletal, healthKitIdentifier: "lowerBackPain"),
        .init(id: "stiffShoulder",       category: .musculoskeletal, healthKitIdentifier: ""),
        .init(id: "neckPain",            category: .musculoskeletal, healthKitIdentifier: ""),
        .init(id: "jointPain",           category: .musculoskeletal, healthKitIdentifier: ""),
        .init(id: "musclePain",          category: .musculoskeletal, healthKitIdentifier: "generalizedBodyAche"),
        // 循環器
        .init(id: "palpitations",        category: .circulatory, healthKitIdentifier: "rapidPoundingOrFlutteringHeartbeat"),
        .init(id: "chestPain",           category: .circulatory, healthKitIdentifier: "chestTightnessOrPain"),
        // 皮膚
        .init(id: "itching",             category: .skin, healthKitIdentifier: ""),
        .init(id: "rash",                category: .skin, healthKitIdentifier: ""),
        // 眼
        .init(id: "eyeStrain",           category: .eye, healthKitIdentifier: ""),
        .init(id: "blurredVision",       category: .eye, healthKitIdentifier: ""),
        .init(id: "floaters",            category: .eye, healthKitIdentifier: ""),
        // 口腔
        .init(id: "toothache",           category: .oral, healthKitIdentifier: ""),
        .init(id: "dryMouth",            category: .oral, healthKitIdentifier: ""),
        // 精神
        .init(id: "lowMood",             category: .mental, healthKitIdentifier: "moodChanges"),
        .init(id: "anxiety",             category: .mental, healthKitIdentifier: ""),
        .init(id: "irritability",        category: .mental, healthKitIdentifier: ""),
        // 女性
        .init(id: "menstrualPain",       category: .womens, healthKitIdentifier: "pelvicPain"),
    ]

    private static let byID: [String: SymptomCatalogEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func entry(for id: String) -> SymptomCatalogEntry? { byID[id] }

    /// 入力された名前が辞書のどれかと一致すれば、その slug を返す。
    /// 「花粉症」のようにプリセットにある名前を手入力されたとき、
    /// 別IDのユーザー追加タグを作って重複させないために使う。
    /// 表示中の言語だけでなく全対応言語の名前を見る（端末を英語にしていても日本語名で当てられる）
    static func matchingID(forName name: String) -> String? {
        SymptomTagMatching.matchingID(forName: name, in: all.map { ($0.id, $0.labelKey) })
    }

    /// 入力中の文字に似た症状の候補
    static func suggestions(forInput input: String, limit: Int = 5) -> [SymptomCatalogEntry] {
        SymptomTagMatching
            .suggestions(forInput: input, in: all.map { ($0.id, $0.labelKey) }, limit: limit)
            .compactMap { entry(for: $0) }
    }

    /// 分類ごとにまとめた辞書（辞書シートの表示順）
    static var groupedByCategory: [(category: SymptomCategory, entries: [SymptomCatalogEntry])] {
        SymptomCategory.allCases.compactMap { category in
            let entries = all.filter { $0.category == category }
            return entries.isEmpty ? nil : (category: category, entries: entries)
        }
    }

    /// 初回起動時に症状タグリストへ入れておく既定の症状。
    /// 空のリストで始めると記録画面に何も出ず、最初の1件が記録できないため。
    static let defaultTagIDs: [String] = [
        "headache", "abdominalPain", "fever", "fatigue",
        "dizziness", "cough", "runnyNose", "backPain",
    ]
}

// MARK: - 薬辞書

/// 対処の分類。画面では1つの「対処」にまとめて選ばせるが、
/// 統計では「薬あり/なし」を見たいので、項目ごとに種別を持つ
enum RemedyKind: String, Codable {
    case medicine   // 薬
    case action     // 薬以外の対処（休む・通院など）
}

struct MedicineCatalogEntry: Identifiable, Equatable {
    let id: String
    var kind: RemedyKind = .medicine

    var labelKey: String { "medicine.name.\(id)" }
    var localizedName: String { NSLocalizedString(labelKey, comment: "") }
    var isMedicine: Bool { kind == .medicine }
}

/// プリセットは薬効分類で持ち、商品名はユーザー追加とする。
/// 商品名は国ごとに違う（ロキソニンは日本、Advil は米国）ため、
/// 4言語アプリのプリセットには入れられない。
/// 薬以外の対処（休む・通院など）も同じ辞書に入れ、`kind` で区別する。
enum MedicineCatalog {

    /// 薬と薬以外はカプセルの色で見分けるので、見出しでは分けず1つに並べる。
    /// 薬を17件すべて先に置くと「寝た」「安静にした」まで遠いので、
    /// よく使うものから混ぜて並べる（タグリストは使うほど上に来るので初期順の影響は薄れる）
    static let all: [MedicineCatalogEntry] = [
        .init(id: "analgesic"),
        .init(id: "sleep",         kind: .action),
        .init(id: "rest",          kind: .action),
        .init(id: "gastric"),
        .init(id: "antiallergy"),
        .init(id: "cooling",       kind: .action),
        .init(id: "warming",       kind: .action),
        .init(id: "hydration",     kind: .action),
        .init(id: "coldRemedy"),
        .init(id: "antitussive"),
        .init(id: "topicalAnalgesic"),
        .init(id: "bath",          kind: .action),
        .init(id: "meal",          kind: .action),
        .init(id: "stretch",       kind: .action),
        .init(id: "darkQuietRoom", kind: .action),
        .init(id: "nasalSpray"),
        .init(id: "eyeDrops"),
        .init(id: "intestinal"),
        .init(id: "antidiarrheal"),
        .init(id: "laxative"),
        .init(id: "sleepAid"),
        .init(id: "antiemetic"),
        .init(id: "kampo"),
        .init(id: "supplement"),
        .init(id: "antihypertensive"),
        .init(id: "clinicVisit",   kind: .action),
        .init(id: "dayOff",        kind: .action),
        .init(id: "prescriptionOther"),
        .init(id: "noAction",      kind: .action),
    ]

    private static let byID: [String: MedicineCatalogEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func entry(for id: String) -> MedicineCatalogEntry? { byID[id] }

    /// 入力された名前が辞書のどれかと一致すれば、その id を返す
    static func matchingID(forName name: String) -> String? {
        SymptomTagMatching.matchingID(forName: name, in: all.map { ($0.id, $0.labelKey) })
    }

    static let defaultTagIDs: [String] = ["analgesic", "gastric", "antiallergy", "sleep", "rest"]

    /// 入力中の文字に似た対処の候補
    static func suggestions(forInput input: String, limit: Int = 5) -> [MedicineCatalogEntry] {
        SymptomTagMatching
            .suggestions(forInput: input, in: all.map { ($0.id, $0.labelKey) }, limit: limit)
            .compactMap { entry(for: $0) }
    }

    /// 薬だけの ID（統計で「薬あり/なし」を分けるのに使う）
    static func isMedicine(_ id: String) -> Bool {
        // 辞書に無い ID（ユーザー追加）は薬として扱う。
        // ユーザー追加は商品名を想定しているため
        entry(for: id)?.isMedicine ?? true
    }
}


// MARK: - 名前の突き合わせ

/// 手入力された名前を辞書の項目に対応づける。
/// 症状と薬で同じ規則を使う
enum SymptomTagMatching {

    /// 比較用に正規化する。前後の空白を落とし、全角・半角と大文字・小文字の差を無視する
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                     locale: .current)
    }

    /// 対応する全言語の訳で突き合わせる。
    /// 端末が英語でも「花粉症」と打てば hayFever に当たるようにするため
    private static let comparedLanguages = ["ja", "en", "ko", "zh-Hant"]

    /// 入力途中の文字を含む項目を返す（候補表示用）。
    /// 完全一致の matchingID と違い、部分一致で拾う
    static func suggestions(
        forInput input: String,
        in entries: [(id: String, labelKey: String)],
        limit: Int = 5
    ) -> [String] {
        let target = normalized(input)
        guard !target.isEmpty else { return [] }
        var result: [String] = []
        for entry in entries {
            let names = localizedNames(forKey: entry.labelKey)
            // 前方一致を優先したいので、まず含むかどうかだけ判定する
            if names.contains(where: { normalized($0).contains(target) }) {
                result.append(entry.id)
                if result.count >= limit { break }
            }
        }
        return result
    }

    static func matchingID(forName name: String, in entries: [(id: String, labelKey: String)]) -> String? {
        let target = normalized(name)
        guard !target.isEmpty else { return nil }
        for entry in entries {
            for localized in localizedNames(forKey: entry.labelKey)
            where normalized(localized) == target {
                return entry.id
            }
        }
        return nil
    }

    /// 1つのキーについて、対応言語ぶんの訳を集める
    private static func localizedNames(forKey key: String) -> [String] {
        var names = [NSLocalizedString(key, comment: "")]
        for code in comparedLanguages {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            names.append(NSLocalizedString(key, bundle: bundle, comment: ""))
        }
        return names
    }
}
