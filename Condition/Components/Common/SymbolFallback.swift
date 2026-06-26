// SymbolFallback.swift
// SF Symbol の OS 可用性ギャップ対策
//
// 開発機（iOS 26）にしか収録されていないシンボルを最低要件（iOS 18）の端末で使うと、
// Image(systemName:) が無描画になり「アイコンが消える」不具合になる。
// UIImage(systemName:) != nil で実体の有無を確認し、無ければ確実に存在する代替名へ落とす。

import SwiftUI

enum SFSymbol {

    /// 端末にそのシンボルが存在するか
    static func exists(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }

    /// 候補名を先頭から順に確認し、最初に端末へ収録されている名前を返す。
    /// すべて未収録なら最後の要素（= 最も確実なフォールバック）をそのまま返す。
    /// - Parameter candidates: 理想 → 妥協 → 確実、の順に並べる
    static func resolve(_ candidates: String...) -> String {
        resolve(candidates)
    }

    static func resolve(_ candidates: [String]) -> String {
        for name in candidates where exists(name) {
            return name
        }
        return candidates.last ?? "questionmark"
    }
}

extension Image {
    /// 候補名のうち端末に存在する最初のシンボルで Image を生成する。
    /// 例: `Image(systemNameResolving: "inset.filled.righthalf.arrow.right.rectangle", "arrow.right.square", "arrow.right")`
    init(systemNameResolving candidates: String...) {
        self.init(systemName: SFSymbol.resolve(candidates))
    }
}
