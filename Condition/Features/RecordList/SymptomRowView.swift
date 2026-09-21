// SymptomRowView.swift
// 記録一覧の症状セル。測定セル（RecordRowView）と同じ行の中に混ざって並ぶ

import SwiftUI

struct SymptomRowView: View {
    let record: SymptomRecord
    /// 継続中の記録を1タップで終了させる
    var onFinish: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .title3) private var dateColW: CGFloat = 76
    @ScaledMetric(relativeTo: .caption2) private var scaledMarkSz: CGFloat = 10

    private var settings: AppSettings { AppSettings.shared }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "E"
        return f
    }()

    /// 1桁の日は図形スペースで右詰めし、測定セルと日付の桁を揃える
    private var dayString: String {
        let s = Self.dateFormatter.string(from: record.startAt)
        return s.count == 1 ? "\u{2007}\(s)" : s
    }

    private var tag: SymptomTag {
        settings.symptomTags.tag(for: record.sSymptomID) ?? SymptomTag(id: record.sSymptomID)
    }

    private var severityColor: Color {
        DateOptColorOption.color(for: record.severity.colorKey)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            dateColumn
            Divider()
                .padding(.trailing, 8)
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                if let detail = detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if record.bOngoing, let onFinish {
                Button(action: onFinish) {
                    Text("symptom.action.finish")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
        // 測定セルと地続きに見えないよう、症状の行だけ薄く色を敷く
        .background(severityColor.opacity(0.07))
    }

    // MARK: - 日付列

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(dayString)
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text(Self.weekdayFormatter.string(from: record.startAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(Self.timeFormatter.string(from: record.startAt))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: dateColW - 8, alignment: .leading)
        .padding(.trailing, 8)
    }

    // MARK: - 症状名・程度

    private var titleLine: some View {
        HStack(spacing: 6) {
            // 症状名はアイコンにすると意味が伝わらないので文字で出す
            Text(tag.symptomDisplayName)
                .font(.body)
                .lineLimit(1)
            Text(LocalizedStringKey(record.severity.labelKey))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(severityColor.opacity(0.2))
                .foregroundStyle(severityColor)
                .clipShape(Capsule())
            if record.bOngoing {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(Text("symptom.ongoing"))
            }
        }
    }

    /// 持続時間・薬・メモを1行にまとめる。空の要素は出さない
    private var detailLine: String? {
        var parts: [String] = []
        if let text = durationText { parts.append(text) }
        let medicines = record.medicineIDs
            .map { id in
                (settings.medicineTags.tag(for: id) ?? SymptomTag(id: id)).medicineDisplayName
            }
        if !medicines.isEmpty { parts.append(medicines.joined(separator: "・")) }
        let note = record.sNote
            .components(separatedBy: .newlines)
            .first(where: { !$0.isEmpty }) ?? ""
        if !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }

    private var durationText: String? {
        guard let duration = record.duration else { return nil }
        let text = SymptomDurationFormatter.string(from: duration)
        if record.bOngoing {
            return String(format: NSLocalizedString("symptom.duration.ongoing", comment: ""), text)
        }
        return text
    }
}

// MARK: - 持続時間の表記

/// 持続時間は分から月までレンジが広い（閃輝暗点20分〜花粉症2か月）ので、
/// 桁に応じて単位を切り替える
enum SymptomDurationFormatter {
    static func string(from duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        if minutes < 60 {
            return String(format: NSLocalizedString("symptom.duration.minutes", comment: ""), minutes)
        }
        let hours = minutes / 60
        if hours < 24 {
            let remainder = minutes % 60
            if remainder == 0 {
                return String(format: NSLocalizedString("symptom.duration.hours", comment: ""), hours)
            }
            return String(format: NSLocalizedString("symptom.duration.hoursMinutes", comment: ""), hours, remainder)
        }
        let days = hours / 24
        return String(format: NSLocalizedString("symptom.duration.days", comment: ""), days)
    }
}
