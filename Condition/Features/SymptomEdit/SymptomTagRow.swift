// SymptomTagRow.swift
// 症状・薬のタグ行（MRU 上位 n 件＋「＋」で全件シート）と、辞書から選ぶシート

import SwiftUI

// MARK: - タグの見た目

/// 選択状態を持つカプセル型のタグ。
/// 症状名・薬名はアイコンでは伝わらないので、文字だけで見せる
struct SymptomTagChip: View {
    let title: String
    let color: Color
    let isSelected: Bool
    /// 未選択でも色を薄く乗せるか。
    /// 対処の「薬／薬以外」のように、選ぶ前から見分けたい場合に使う
    var tintsWhenUnselected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .font(.callout)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(borderColor, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    // 選択と種別は別々の手段で伝える。
    // 濃淡だけで両方を表すと、片方の差がもう片方に埋もれて見分けられなくなる。
    //   選択／未選択 … 塗りつぶし＋白文字か、淡い塗り＋枠線か（明度が大きく変わる）
    //   薬／薬以外   … 色相（青／オレンジ）
    private var background: Color {
        if isSelected { return color }
        return tintsWhenUnselected ? color.opacity(0.12) : Color(.secondarySystemBackground)
    }

    private var foreground: Color {
        isSelected ? .white : .primary
    }

    private var borderColor: Color {
        guard !isSelected else { return .clear }
        return tintsWhenUnselected ? color.opacity(0.55) : .clear
    }
}

// MARK: - タグ行

/// 記録画面に出すタグ行。MRU 上位 `limit` 件を並べ、末尾の「＋」で辞書シートを開く
struct SymptomTagRow: View {
    let tags: [SymptomTag]
    let kind: SymptomTagKind
    /// 選択中の ID（症状は1件、薬は複数）
    let selectedIDs: Set<String>
    let onTap: (String) -> Void
    let onAdd: () -> Void

    /// 折り返しで並べる（タグ名の長さが言語で大きく変わるため固定列にしない）
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                SymptomTagChip(
                    title: kind == .symptom ? tag.symptomDisplayName : tag.medicineDisplayName,
                    color: kind == .symptom ? tag.symptomColor : tag.remedyColor,
                    isSelected: selectedIDs.contains(tag.id),
                    tintsWhenUnselected: kind == .medicine
                ) {
                    onTap(tag.id)
                }
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(kind == .symptom ? "symptom.picker.title" : "remedy.picker.title"))
        }
    }
}

enum SymptomTagKind {
    case symptom
    case medicine
}

// MARK: - 折り返しレイアウト

/// 幅に収まらなくなったら次の行へ送る単純なレイアウト。
/// タグ名の長さは言語で大きく変わるので、固定の列数では破綻する
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } +
            spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, maxWidth < needed {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
