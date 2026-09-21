// ToolbarButtonLabel.swift
// ツールバーボタンのラベル。初心者モードのときだけアイコンの下に用途を文字で添える

import SwiftUI

/// アイコンだけでは用途が分からない利用者向けに、初心者モードでは説明を1語添える。
/// 達人モードではアイコンのみになり、ナビゲーションバーがすっきりする。
struct ToolbarButtonLabel: View {
    let systemImage: String
    let captionKey: LocalizedStringKey

    /// キャプションの文字サイズ。ナビゲーションバー（44pt）にアイコンと2段で収める必要があるので、
    /// 文字サイズ設定には追従させつつ上限で頭打ちにする
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 12
    /// アイコンの大きさ。既定（17pt前後）のままだと文字を大きくしたときに2段で溢れるため、
    /// キャプションを出すときだけ少し絞って高さを文字側に回す
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 16

    private var settings: AppSettings { AppSettings.shared }

    private var showsCaption: Bool {
        settings.userLevel == .beginner
    }

    var body: some View {
        VStack(spacing: 1) {
            if showsCaption {
                Image(systemName: systemImage)
                    .font(.system(size: min(iconSize, 19)))
                Text(captionKey)
                    .font(.system(size: min(captionSize, 15), weight: .medium))
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
