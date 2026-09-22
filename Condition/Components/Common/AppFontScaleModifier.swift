// AppFontScaleModifier.swift
// アプリ内の文字サイズ設定をシートへ確実に伝える
//
// .sheet で呈示されるビューには App 側で付けた dynamicTypeSize の環境値が
// 引き継がれないことがある。各シートの入口でこれを付けて、設定と必ず連動させる。

import SwiftUI

extension View {
    /// アプリの文字サイズ設定を適用する。「自動」のときはシステム設定に委ねる
    @ViewBuilder
    func azAppFontScale(_ settings: AppSettings = .shared) -> some View {
        if settings.fontScale.followsSystem {
            self
        } else {
            self.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
        }
    }
}
