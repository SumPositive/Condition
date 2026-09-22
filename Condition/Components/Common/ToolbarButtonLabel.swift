// ToolbarButtonLabel.swift
// ツールバーボタンのラベル。初心者モードのときだけアイコンの下に用途を文字で添える

import SwiftUI

/// アイコンだけでは用途が分からない利用者向けに、初心者モードでは説明を1語添える。
/// 達人モードではアイコンのみになり、ナビゲーションバーがすっきりする。
struct ToolbarButtonLabel: View {
    let systemImage: String
    let captionKey: LocalizedStringKey

    // iOS 26 のツールバー項目はシステムが描くカプセルに収まる。
    // カプセルの高さはアプリから変えられず、中に置ける高さはバー(44pt)より狭い（実測で約30pt）。
    // アイコンと文字の合計をその範囲に収める必要があるので、
    // 文字を大きくしたいぶんはアイコンを削って配分する。
    //   文字は読んで意味が分かるが、アイコンは「測定」「症状」の区別に寄与しないため
    /// キャプションの文字サイズ
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 15
    /// アイコンの大きさ
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 14

    private var settings: AppSettings { AppSettings.shared }

    private var showsCaption: Bool {
        settings.userLevel == .beginner
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsCaption {
                Image(systemName: systemImage)
                    .font(.system(size: min(iconSize, 16)))
                Text(captionKey)
                    .font(.system(size: min(captionSize, 16), weight: .medium))
                    .lineLimit(1)
                    // 中国語・韓国語で崩れないよう、収まらなければ縮める
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Image(systemName: systemImage)
            }
        }
        // VStack にするとボタンの当たり判定が縦に伸びるので、
        // アイコン単体のときと押し心地が変わらないよう最低幅を確保する
        .frame(minWidth: 34)
        .accessibilityLabel(Text(captionKey))
    }
}
