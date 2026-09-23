// SymptomTagRow.swift
// 症状・対処の選択で使う部品（タグの見た目と折り返しレイアウト）。
// 選択そのものは SymptomPickerSheet が担い、記録画面には選択済みだけを出す

import SwiftUI

// MARK: - タグの見た目

/// 選択状態を持つカプセル型のタグ。
/// 症状名・薬名はアイコンでは伝わらないので、文字だけで見せる
struct SymptomTagChip: View {
    let title: String
    let color: Color
    let isSelected: Bool
    /// 長押しの処理。Button の外側に onLongPressGesture を付けても
    /// Button がジェスチャを先に取るため届かないので、ここで受け取る
    var onLongPress: (() -> Void)? = nil
    let action: () -> Void

    /// 長押しが成立したか。離したときにタップを走らせないための目印
    @State private var didLongPress = false

    var body: some View {
        // Button + simultaneousGesture だと、長押しして離したときに
        // Button のアクションも走ってしまう（選択されてシートが閉じる）。
        // タップと長押しを自前で排他にする
        Text(title)
            .lineLimit(1)
            .font(.callout)
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture {
                // 長押し直後に指を離したときのタップは無視する
                if didLongPress {
                    didLongPress = false
                    return
                }
                action()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                guard let onLongPress else { return }
                didLongPress = true
                onLongPress()
            }
            .accessibilityAddTraits(.isButton)
    }

    // 選択は塗りつぶし＋白文字で示す。明度が大きく変わるので一目で分かる
    private var background: Color {
        isSelected ? color : Color(.secondarySystemBackground)
    }

    private var foreground: Color {
        isSelected ? .white : .primary
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
    /// 行内の寄せ方。選択済みタグを右の「＞」に揃えたい場面で .trailing を使う
    var alignment: HorizontalAlignment = .leading

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
            // 右寄せのときは、その行の余りぶんだけ開始位置をずらす
            var x = alignment == .trailing
                ? bounds.maxX - row.width
                : bounds.minX
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

// MARK: - 行の当たり判定

extension View {
    /// Form のセル全体をタップ領域にする。
    /// 既定の行インセットを消して自分で余白を持ち、行いっぱいに広がるようにしないと、
    /// 中身の幅までしか反応せず「ラベルを押しても開かない」状態になる
    func azFullWidthRow() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}
