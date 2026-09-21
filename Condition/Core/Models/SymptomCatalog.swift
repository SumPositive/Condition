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

struct MedicineCatalogEntry: Identifiable, Equatable {
    let id: String

    var labelKey: String { "medicine.name.\(id)" }
    var localizedName: String { NSLocalizedString(labelKey, comment: "") }
}

/// プリセットは薬効分類で持ち、商品名はユーザー追加とする。
/// 商品名は国ごとに違う（ロキソニンは日本、Advil は米国）ため、
/// 4言語アプリのプリセットには入れられない。
enum MedicineCatalog {

    static let all: [MedicineCatalogEntry] = [
        .init(id: "analgesic"),
        .init(id: "gastric"),
        .init(id: "intestinal"),
        .init(id: "antidiarrheal"),
        .init(id: "laxative"),
        .init(id: "antiallergy"),
        .init(id: "nasalSpray"),
        .init(id: "eyeDrops"),
        .init(id: "antitussive"),
        .init(id: "coldRemedy"),
        .init(id: "topicalAnalgesic"),
        .init(id: "sleepAid"),
        .init(id: "antiemetic"),
        .init(id: "kampo"),
        .init(id: "supplement"),
        .init(id: "antihypertensive"),
        .init(id: "prescriptionOther"),
    ]

    private static let byID: [String: MedicineCatalogEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func entry(for id: String) -> MedicineCatalogEntry? { byID[id] }

    /// 入力された名前が辞書のどれかと一致すれば、その id を返す
    static func matchingID(forName name: String) -> String? {
        SymptomTagMatching.matchingID(forName: name, in: all.map { ($0.id, $0.labelKey) })
    }

    static let defaultTagIDs: [String] = ["analgesic", "gastric", "antiallergy"]
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
