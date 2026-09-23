// SymptomCatalog.swift
// 内蔵の症状辞書（読み取り専用・46件）と薬辞書（17件）
//
// レコードには表示名ではなく ID を保存する。
// 表示名を保存すると、4言語（ja/en/ko/zh-Hant）で集計キーが言語ごとに割れてしまうため。
// ユーザーが辞書から選んだものだけが「症状タグリスト」に入る（SymptomTagStore）。

import Foundation
import SwiftUI

// MARK: - 色

/// タグの色を ID から決める。
/// 分類ごとの色分けをやめたので、代わりに ID のハッシュで安定して割り当てる。
/// 名前を変えても色は変わらない（ID は変わらないため）
enum SymptomPalette {
    /// 記録一覧の背景にも敷くので、濃さの近い色をそろえる
    static let colorKeys = [
        "purple", "orange", "brown", "cyan", "teal",
        "red", "pink", "indigo", "blue", "green",
    ]

    static func colorKey(for id: String) -> String {
        guard !id.isEmpty else { return "gray" }
        // hashValue は起動ごとに変わるので使えない（色が毎回変わってしまう）。
        // バイト列の総和なら同じ ID から必ず同じ色になる
        let sum = id.utf8.reduce(0) { $0 + Int($1) }
        return colorKeys[sum % colorKeys.count]
    }
}

// MARK: - 辞書エントリ

struct SymptomCatalogEntry: Identifiable, Equatable {
    /// レコードへ保存する安定キー（slug）
    let id: String
    /// HealthKit の HKCategoryTypeIdentifier 名。空ならアプリ内のみで扱う。
    /// 実際の書き出しはフェーズ6。識別子の綴りと利用可否は実装時に SDK で要確認。
    let healthKitIdentifier: String

    var labelKey: String { "symptom.name.\(id)" }
    /// タグの色。分類を廃したので、ID から安定した色を割り当てる。
    /// 同じ症状はいつでも同じ色になり、ユーザー追加分も同じ規則で色が付く
    var colorKey: String { SymptomPalette.colorKey(for: id) }

    /// 現在の言語での表示名
    var localizedName: String { NSLocalizedString(labelKey, comment: "") }
}

// MARK: - 症状辞書

enum SymptomCatalog {

    /// 既定で一覧に出す症状。
    ///
    /// 個人が実際に記録する症状は限られているので、最初から並べるのは10件だけにする。
    /// 多すぎると目的の症状を探すほうが手間になり、ユーザー追加の邪魔にもなる。
    /// 並びは日本の有訴者率（肩こり・腰痛が男女とも上位）と、
    /// 体調記録アプリで扱う中心（頭痛・倦怠感・めまい）を踏まえた順。
    ///
    /// 足りないものはユーザーが名前を打って追加する。辞書に無い症状も
    /// 同じマスタ（症状タグリスト）に入り、プリセットと区別なく扱われる
    static let all: [SymptomCatalogEntry] = [
        .init(id: "stiffShoulder",  healthKitIdentifier: ""),
        .init(id: "backPain",       healthKitIdentifier: ""),
        .init(id: "headache",       healthKitIdentifier: "headache"),
        .init(id: "fatigue",        healthKitIdentifier: "fatigue"),
        .init(id: "dizziness",      healthKitIdentifier: "dizziness"),
        .init(id: "abdominalPain",  healthKitIdentifier: "abdominalCramps"),
        .init(id: "runnyNose",      healthKitIdentifier: "runnyNose"),
        .init(id: "cough",          healthKitIdentifier: "coughing"),
        .init(id: "fever",          healthKitIdentifier: "fever"),
        .init(id: "insomnia",       healthKitIdentifier: "sleepChanges"),
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

    /// 一覧に出す順。辞書がそのまま表示対象になる
    static let visibleIDs: [String] = all.map(\.id)

    /// 初回起動時に症状タグリストへ入れておく既定の症状。
    /// 空のリストで始めると記録画面に何も出ず、最初の1件が記録できないため
    static let defaultTagIDs: [String] = visibleIDs
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

    /// 薬と薬以外を混ぜ、よく使うものから並べる
    /// （タグリストは使うほど上に来るので初期順の影響は薄れる）
    /// 既定で一覧に出す対処。
    ///
    /// 症状プリセット（10件）に対して実際に取る手を10件でカバーする。
    /// 市販薬の主要3系統（解熱鎮痛薬・胃腸薬・抗アレルギー薬）と、
    /// 薬以外の基本動作、そして「受診した」。
    /// 商品名（バファリンPM など）はユーザーが足す前提にする。
    ///
    /// 「何もしなかった」は未選択と意味が重なるので持たない
    static let all: [MedicineCatalogEntry] = [
        .init(id: "analgesic"),        // 解熱鎮痛薬
        .init(id: "sleep"),            // 寝た
        .init(id: "rest"),             // 安静にした
        .init(id: "warming"),          // 温めた
        .init(id: "cooling"),          // 冷やした
        .init(id: "gastric"),          // 胃腸薬
        .init(id: "antiallergy"),      // 抗アレルギー薬
        .init(id: "bath"),             // 入浴した
        .init(id: "stretch"),          // ストレッチ・体操
        .init(id: "clinicVisit"),      // 受診した
    ]

    private static let byID: [String: MedicineCatalogEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func entry(for id: String) -> MedicineCatalogEntry? { byID[id] }

    /// 入力された名前が辞書のどれかと一致すれば、その id を返す
    static func matchingID(forName name: String) -> String? {
        SymptomTagMatching.matchingID(forName: name, in: all.map { ($0.id, $0.labelKey) })
    }

    /// 初回起動時にタグリストへ入れる対処。一覧に出す10件と同じにする
    static let defaultTagIDs: [String] = all.map(\.id)

    /// 入力中の文字に似た対処の候補
    static func suggestions(forInput input: String, limit: Int = 5) -> [MedicineCatalogEntry] {
        SymptomTagMatching
            .suggestions(forInput: input, in: all.map { ($0.id, $0.labelKey) }, limit: limit)
            .compactMap { entry(for: $0) }
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


