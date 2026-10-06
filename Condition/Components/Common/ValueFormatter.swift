// ValueFormatter.swift
// 測定値の数値→表示文字列変換（旧 Global.m strValue() 相当）

import Foundation
import SwiftUI

enum ValueFormatter {

    /// val が 0 以下なら空文字。decimals > 0 なら小数表示。
    /// - Parameters:
    ///   - val: 内部値（体温・体重・体脂肪は x10 で格納）
    ///   - decimals: 表示する小数点桁数（0=整数、1=小数1桁）
    static func format(_ val: Int, decimals: Int) -> String {
        guard val > 0 else { return "" }
        if decimals <= 0 {
            return "\(val)"
        }
        let pow10 = intPow(10, decimals)
        let intPart = val / pow10
        let decPart = val - intPart * pow10
        if decPart <= 0 {
            switch decimals {
            case 1: return "\(intPart).0"
            case 2: return "\(intPart).00"
            default: return "\(intPart)"
            }
        } else {
            return "\(intPart).\(decPart)"
        }
    }

    private static func intPow(_ base: Int, _ exp: Int) -> Int {
        var result = 1
        for _ in 0..<exp { result *= base }
        return result
    }
}

// MARK: - 日時の共通表示

/// 記録・症状の日時を共通の強弱で表示する。
/// 並び順と区切りは iOS の言語・地域の設定に従い、年は西暦で出す
/// 曜日の前後の区切り（( ) , など）は半角スペースにして、すっきり見せる。
/// 年が先頭の地域（ja・ko など）は、年の後ろの区切り（/ や「. 」）も半角スペースにする。
/// 年が最後の地域（en_US・en_GB など）は「10/3/2026」が見慣れた形なので、年の前の / は残して年と同じ小ささ・薄さにする。
/// 半角スペースが続く箇所は1つにまとめる
/// - ja：「2026 10/3 土 16:25」 en_US：「Sat 10/3/2026 4:25 PM」 ko：「2026 10. 3 토 오후 4:25」
/// 年・曜日は小さく薄く、月/日は大きく太く、時刻は太くする
enum DateTimeDisplay {

    /// 強弱を付ける部分の範囲
    struct FieldRanges {
        /// 年・曜日と、残した年の前の区切り（小さく薄く）
        var minor: [Range<AttributedString.Index>] = []
        /// 月/日。間の区切りも含む（大きく太く）
        var monthDay: Range<AttributedString.Index>?
        /// 時刻。午前・午後も含む（太く）
        var time: Range<AttributedString.Index>?
    }

    /// 曜日つきの年月日＋時刻を、iOS の設定の並び・区切りで書式化する。
    /// 各部分には Foundation の日時項目の属性が付く
    static func attributedString(for date: Date, locale: Locale = .current) -> AttributedString {
        // 和暦などの設定でも西暦で出す
        let style = Date.FormatStyle(
            date: .omitted, time: .omitted,
            locale: AppDateCalendar.gregorianLocale(locale), calendar: Calendar(identifier: .gregorian)
        )
        .year()
        .month(.defaultDigits)
        .day()
        .weekday(.abbreviated)
        .hour()
        .minute()
        return simplifiedSeparators(date.formatted(style.attributedStyle))
    }

    /// 曜日に接する区切りは半角スペース1つにする。年に接する区切りは、年が先頭なら半角スペース、
    /// 年が月日より後ろなら括弧・読点だけ除いて残す（空白だけになれば半角スペース1つ）。
    /// 端にある区切りは消す。月/日の間や時刻の中の区切りは iOS の書式のまま残す
    static func simplifiedSeparators(_ source: AttributedString) -> AttributedString {
        var text = source
        let runs = text.runs.map { (range: $0.range, field: $0.foundation.dateField) }
        let keepsYearSeparator = !isYearFirst(runs.map(\.field))
        // 置き換えで後ろの位置がずれないよう、末尾から処理する
        for index in runs.indices.reversed() where runs[index].field == nil {
            let previous = 0 < index ? runs[index - 1].field : nil
            let next = index + 1 < runs.count ? runs[index + 1].field : nil
            let touchesWeekday = previous == .weekday || next == .weekday
            let touchesYear = previous == .year || next == .year
            guard touchesWeekday || touchesYear else { continue }
            let isEdge = index == 0 || index == runs.count - 1
            var replacement = isEdge ? "" : " "
            // 年が後ろの地域だけ年の前の区切り（/ など）を残す。曜日に接するときは括弧なので残さない
            if keepsYearSeparator, !touchesWeekday {
                let kept = String(text[runs[index].range].characters)
                    .filter { !removedSeparatorCharacters.contains($0) }
                if !kept.allSatisfy(\.isWhitespace) { replacement = kept }
            }
            text.replaceSubrange(runs[index].range, with: AttributedString(replacement))
        }
        return collapsedSpaces(text)
    }

    /// 年が月・日より前に並ぶ書式か
    private static func isYearFirst(_ fields: [AttributeScopes.FoundationAttributes.DateFieldAttribute.Field?]) -> Bool {
        guard let year = fields.firstIndex(of: .year) else { return false }
        guard let monthDay = fields.firstIndex(where: { $0 == .month || $0 == .day }) else { return true }
        return year < monthDay
    }

    /// 年の前後の区切りから除く文字（括弧・読点）
    private static let removedSeparatorCharacters: Set<Character> = [
        ",", "，", "、", "(", ")", "（", "）",
    ]

    /// 年の前後に残した区切りか（空白だけのものは除く）
    private static func isYearSeparator(_ separator: AttributedSubstring) -> Bool {
        !String(separator.characters).allSatisfy(\.isWhitespace)
    }

    /// 続いた空白を半角スペース1つにまとめる。項目の文字には空白が無いので、区切りだけが対象になる
    static func collapsedSpaces(_ source: AttributedString) -> AttributedString {
        var text = source
        var spaceRuns: [Range<AttributedString.Index>] = []
        var start: AttributedString.Index?
        var count = 0
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.characters.index(after: index)
            if text.characters[index].isWhitespace {
                if start == nil { start = index }
                count += 1
            } else {
                if let start, 1 < count { spaceRuns.append(start..<index) }
                start = nil
                count = 0
            }
            index = next
        }
        if let start, 1 < count { spaceRuns.append(start..<text.endIndex) }
        // 置き換えで後ろの位置がずれないよう、末尾から処理する
        for range in spaceRuns.reversed() {
            text.replaceSubrange(range, with: AttributedString(" "))
        }
        return text
    }

    /// 1行の文字列
    static func string(for date: Date, locale: Locale = .current) -> String {
        String(attributedString(for: date, locale: locale).characters)
    }

    /// 日時項目の属性から、強弱を付ける範囲を集める
    static func fieldRanges(in text: AttributedString) -> FieldRanges {
        var ranges = FieldRanges()
        func merged(
            _ current: Range<AttributedString.Index>?,
            _ range: Range<AttributedString.Index>
        ) -> Range<AttributedString.Index> {
            guard let current else { return range }
            return min(current.lowerBound, range.lowerBound)..<max(current.upperBound, range.upperBound)
        }
        let runs = Array(text.runs)
        for (index, run) in runs.enumerated() {
            guard let field = run.foundation.dateField else {
                // 年の前に残した区切り（/）は年と同じ小ささ・薄さにする
                let previous = 0 < index ? runs[index - 1].foundation.dateField : nil
                let next = index + 1 < runs.count ? runs[index + 1].foundation.dateField : nil
                if previous == .year || next == .year, isYearSeparator(text[run.range]) {
                    ranges.minor.append(run.range)
                }
                continue
            }
            switch field {
            case .year, .weekday:
                ranges.minor.append(run.range)
            case .month, .day:
                // 月と日の間の区切り（/ など）も一緒に強調するため、両端までつなぐ
                ranges.monthDay = merged(ranges.monthDay, run.range)
            case .hour, .minute, .amPM:
                ranges.time = merged(ranges.time, run.range)
            default:
                break
            }
        }
        return ranges
    }

    /// 強弱を付けた文字列。フォントの大きさは文字サイズ設定に追従する
    static func styledString(for date: Date, locale: Locale = .current) -> AttributedString {
        var text = attributedString(for: date, locale: locale)
        let ranges = fieldRanges(in: text)
        // 年・曜日：小さく薄く
        for range in ranges.minor {
            text[range].swiftUI.font = .footnote
            text[range].swiftUI.foregroundColor = .secondary
        }
        // 月/日：大きく太く
        if let monthDay = ranges.monthDay {
            text[monthDay].swiftUI.font = .title3.weight(.bold)
        }
        // 時刻：太く
        if let time = ranges.time {
            text[time].swiftUI.font = .body.weight(.semibold)
        }
        return text
    }

    /// 読み上げ用。区切り記号を読ませないよう、iOS の完全な日付の書式にする
    static func accessibilityString(for date: Date, locale: Locale = .current) -> String {
        let formatter = AppDateCalendar.formatter()
        formatter.locale = AppDateCalendar.gregorianLocale(locale)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// 日時の共通表示ビュー。読み上げは1つの文として読む
struct DateTimeDisplayText: View {
    let date: Date

    var body: some View {
        Text(DateTimeDisplay.styledString(for: date))
            .accessibilityLabel(DateTimeDisplay.accessibilityString(for: date))
    }
}
