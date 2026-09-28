//
//  ConditionUITests.swift
//  ConditionUITests
//
//  fastlane snapshot 用の UI テスト
//  記録一覧 / 分析1 / 分析2 / 分析3 を順に撮影する（設定は撮らない）。
//  分析3は症状の図表が縦に長いので、上部と下へ送った位置の2カットにする
//
//  言語切替の方針（DialSplit / CreditMemo と同じ）:
//   - 言語は SnapshotHelper が language.txt の値で -AppleLanguages に設定済み
//   - サンプルデータは -FASTLANE_SNAPSHOT YES を検知して in-memory 投入
//
//  タブ切替（診断で確定した挙動・2026-07-07）:
//   - タブは accessibilityIdentifier("tab.xxx") 付きの Button
//   - iPad では app.buttons[id] は exists=true だが isHittable=false と報告される
//     （座標タップも不安定）。一方 app.buttons.element(boundBy: index) は
//     hittable=true で確実にタップできた（index は 記録0/分析1=1/分析2=2/分析3=3/設定4）。
//   - よって「id 直接 → タブバー index → 全 button index」の多段フォールバックにする。
//
//  文字サイズ:
//   - iPad は余白が目立つので撮影時だけ文字サイズを「大」に固定する
//     （-SNAPSHOT_FONT_SCALE large をアプリの DEBUG フックが読む）
//

import XCTest

final class ConditionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTakeScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)

        // iPad のときだけ文字サイズを「特大」に固定して余白を締める
        // （large=.xxxLarge では 13インチだと控えめだったので xlarge=.accessibility2 へ）
        if UIDevice.current.userInterfaceIdiom == .pad {
            app.launchArguments += ["-SNAPSHOT_FONT_SCALE", "xlarge"]
        }

        app.launch()

        // 本編（タブUI）が描画されるまで待つ（記録タブのボタン出現で判定）
        _ = app.buttons["tab.records"].waitForExistence(timeout: 20)
        sleep(1)

        // 1 カット目: 記録一覧（起動時に選択済み）
        snapshot("01Records")

        // 2 カット目: グラフ
        selectTab(app, id: "tab.graph", index: 1)
        snapshot("02Graph")

        // 3 カット目: 統計
        selectTab(app, id: "tab.statistics", index: 2)
        snapshot("03Statistics")

        // 4 カット目: 分析3（発症カレンダー・発症の周期性）
        selectTab(app, id: "tab.analysis3", index: 3)
        snapshot("04Symptoms")

        // 5 カット目: 分析3を下へ送り、発症と環境・発症と直前の状況を映す
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        snapshot("05SymptomFactors")
    }

    /// タブを多段フォールバックで叩く。
    /// 識別子で hittable な要素があればそれを、無ければ index（記録0/分析1=1/分析2=2/分析3=3/設定4）で叩く。
    @MainActor
    private func selectTab(_ app: XCUIApplication, id: String, index: Int) {
        // 手法1: 識別子で見つかり hittable ならそれをタップ（iPhone など）
        let byId = app.buttons[id]
        if byId.exists && byId.isHittable {
            byId.tap(); sleep(1); return
        }

        // 手法2: 下部タブバーの index（iPhone のタブバー）
        let tabBtn = app.tabBars.firstMatch.buttons.element(boundBy: index)
        if tabBtn.exists && tabBtn.isHittable {
            tabBtn.tap(); sleep(1); return
        }

        // 手法3: アプリ全体の button index（iPad はこれで確実に当たる）
        let anyBtn = app.buttons.element(boundBy: index)
        if anyBtn.exists && anyBtn.isHittable {
            anyBtn.tap(); sleep(1); return
        }
    }
}
