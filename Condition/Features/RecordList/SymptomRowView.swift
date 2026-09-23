// SymptomRowView.swift
// 記録一覧の症状セル。測定セル（RecordRowView）と同じ行の中に混ざって並ぶ

import SwiftUI

struct SymptomRowView: View {
    let record: SymptomRecord
    /// 継続／終息を切り替える。true で終息（終了時刻はいま）、false で継続中へ戻す
    var onSetOngoing: ((Bool) -> Void)? = nil

    @ScaledMetric(relativeTo: .title3) private var dateColW: CGFloat = 76
    @ScaledMetric(relativeTo: .caption2) private var scaledMarkSz: CGFloat = 10
    /// 測定セルの区分アイコン列と同じ幅。日付の右にマークを縦積みする場所
    @ScaledMetric(relativeTo: .title3) private var catW: CGFloat = 24
    /// 状態を選ぶアラートを出しているか
    @State private var showProgressDialog = false

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
            contentColumn
        }
        .padding(.vertical, 3)
        // 測定セルと地続きに見えないよう、症状の行だけ薄く色を敷く
        .background(severityColor.opacity(0.07))
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLine
            if let detail = detailLine {
                // 持続時間・対処・メモをつないだ行。1行だと対処名の途中で切れるので
                // 2行まで許す（それでも長いときは末尾を省略する）
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 日付列

    private var dateColumn: some View {
        // 測定セルと同じく dateColW を「日付」と「マーク列(catW)」に分ける。
        // 継続バッジをここへ入れると、症状名の行を圧迫せずに済む
        HStack(alignment: .center, spacing: 0) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            ongoingMark
                .frame(width: catW, alignment: .center)
        }
        .frame(width: dateColW - 8, alignment: .leading)
        .padding(.trailing, 8)
    }

    /// 継続／終息の目印。タップで状態を選び直せる。
    /// 終息済みにも出すのは、間違えて閉じたものを継続へ戻す導線がほかに無いため
    @ViewBuilder
    private var ongoingMark: some View {
        Button {
            showProgressDialog = true
        } label: {
            // 文字だと日付列の幅(24pt)に収まらないのでアイコンで表す。
            // 継続は砂時計、終息はチェックで、色も分けて一目で区別できるようにする
            Image(systemName: record.needsEnding ? "hourglass" : "checkmark.circle")
                .font(.system(size: min(scaledMarkSz + 4, 18)))
                .foregroundStyle(record.needsEnding ? Color.accentColor : .secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(record.needsEnding
            ? "symptom.badge.notEnded" : "symptom.progress.finished"))
        .confirmationDialog(
            // タイトルでいまの状態を伝え、選択肢は切り替えだけにする。
            // 現状のままにしたいときはキャンセルで閉じる
            Text(record.needsEnding
                ? "symptom.progress.stillOngoing" : "symptom.progress.didFinish"),
            isPresented: $showProgressDialog,
            titleVisibility: .visible
        ) {
            if record.needsEnding {
                Button("symptom.progress.didFinish") { onSetOngoing?(true) }
            } else {
                Button("symptom.progress.backToOngoing") { onSetOngoing?(false) }
            }
            Button("action.cancel", role: .cancel) {}
        }
    }

    // MARK: - 症状名・程度

    /// 症状名とバッジ。幅が足りなければバッジを次の行へ送る。
    /// 1行に押し込むと、狭い端末や大きい文字でバッジの中の語が折り返してしまう
    private var titleLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                symptomNameText
                badges
            }
            VStack(alignment: .leading, spacing: 3) {
                symptomNameText
                HStack(spacing: 6) { badges }
            }
        }
    }

    private var symptomNameText: some View {
        // 症状名はアイコンにすると意味が伝わらないので文字で出す。
        // 2行まで許し、「He…」のように1文字で切れるのを避ける
        Text(tag.symptomDisplayName)
            .font(.body)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var badges: some View {
        Text(LocalizedStringKey(record.severity.labelKey))
            .font(.caption.weight(.semibold))
            // バッジの中では折り返さない。折り返すと縦に伸びて行の高さが崩れる
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.2))
            .foregroundStyle(severityColor)
            .clipShape(Capsule())
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
        if record.needsEnding {
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
