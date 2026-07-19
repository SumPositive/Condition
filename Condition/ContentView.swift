// ContentView.swift
// ルートタブビュー

import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .records
    /// 起動時アクションのシートが開くまで前画面のタップを防ぐブロック層の表示状態
    @State private var isPreparingLaunchSheet = false
    /// 一度でもバックグラウンドへ入ったか（cold launch と復帰を区別して遅延を最小化する）
    @State private var hasEnteredBackground = false
    /// cold launch 時の起動アクションを onAppear と onChange で二重実行しないためのフラグ
    @State private var didRunInitialLaunchAction = false
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordListView()
                .tabItem {
                    Label(
                        "tab.records",
                        systemImage: "list.bullet.clipboard"
                    )
                    // UITest（fastlane snapshot）でデバイス非依存にタブを叩くための識別子
                    // .tabItem の中身（Label）側に付けるとタブボタン自体に反映されやすい
                    .accessibilityIdentifier("tab.records")
                }
                .tag(RootTab.records)

            GraphView()
                .tabItem {
                    Label(
                        "tab.graph",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    .accessibilityIdentifier("tab.graph")
                }
                .tag(RootTab.graph)

            StatisticsView()
                .tabItem {
                    Label(
                        "tab.statistics",
                        systemImage: "chart.dots.scatter"
                    )
                    .accessibilityIdentifier("tab.statistics")
                }
                .tag(RootTab.statistics)

            SettingsView()
                .tabItem {
                    Label(
                        "tab.settings",
                        systemImage: "gear"
                    )
                    .accessibilityIdentifier("tab.settings")
                }
                .tag(RootTab.settings)
        }
        .onAppear {
            AppAnalytics.shared.logScreen(selectedTab.analyticsName)
            // cold launch：フォアグラウンド表示と同時にブロック層を出したいので、
            // scenePhase の onChange を待たず最初の描画時にここで起動アクションを開始する。
            if !didRunInitialLaunchAction {
                didRunInitialLaunchAction = true
                // シート系アクションはこの時点で即ブロック層を立ててチラつき・誤タップを防ぐ
                if isSheetAction(settings.launchAction) {
                    isPreparingLaunchSheet = true
                }
                performLaunchAction(settings.launchAction)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            // タブ切り替えから、よく使われる機能を把握する
            AppAnalytics.shared.logScreen(tab.analyticsName)
            AppAnalytics.shared.logFeature("tab_select", parameters: ["tab": tab.analyticsName])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                hasEnteredBackground = true
            }
            if phase == .active {
                AppAnalytics.shared.logSettingsSnapshot(settings: settings, reason: "foreground")
            }
            // cold launch は onAppear 側で実行済み。ここではバックグラウンド復帰時のみ扱う。
            guard phase == .active, hasEnteredBackground else { return }
            // 復帰と同時にブロック層を立て、前画面を触らせない
            if isSheetAction(settings.launchAction) {
                isPreparingLaunchSheet = true
            }
            performLaunchAction(settings.launchAction)
        }
        // 起動時アクションのシートが開くまで、前画面をタップさせないブロック層を被せる
        .overlay {
            if isPreparingLaunchSheet {
                ZStack {
                    // 待機中だと分かるよう、はっきり暗くする
                    Color.black.opacity(0.45)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isPreparingLaunchSheet)
    }

    /// 起動（フォアグラウンド復帰）時アクションを実行する
    private func performLaunchAction(_ action: LaunchAction) {
        switch action {
        case .none:
            return
        case .newSingle:
            presentSheet(kind: .single)
        case .newMulti:
            presentSheet(kind: .multi)
        case .records:
            switchTab(to: .records)
        case .graph:
            switchTab(to: .graph)
        case .statistics:
            switchTab(to: .statistics)
        }
    }

    /// シートを開くアクションか（ブロック層を先出しすべきか）
    private func isSheetAction(_ action: LaunchAction) -> Bool {
        switch action {
        case .newSingle, .newMulti: return true
        case .none, .records, .graph, .statistics: return false
        }
    }

    private enum LaunchSheetKind { case single, multi }

    private func presentSheet(kind: LaunchSheetKind) {
        // 未保存の変更あり・すでにどちらかのシートが開いている → 何もしない
        // （呼び出し側で先出ししたブロック層はここで確実に下ろす）
        guard !settings.newRecordSheetModified,
              !settings.showNewRecordSheet,
              !settings.showMeasurementAvgSheet else {
            isPreparingLaunchSheet = false
            return
        }
        // 呈示までの間、前画面をタップさせないよう即座にブロック層を出す
        isPreparingLaunchSheet = true
        Task { @MainActor in
            // 暗幕＋プログレスを確実に一度描画・視認させてからシートを開く。
            // この待機は、実機で復帰直後にシートが表示されない事故の回避も兼ねる。
            try? await Task.sleep(for: .milliseconds(350))
            guard !settings.showNewRecordSheet, !settings.showMeasurementAvgSheet else {
                isPreparingLaunchSheet = false
                return
            }
            switch kind {
            case .single:
                AppAnalytics.shared.logOperation("launch_action_new_single")
                settings.showNewRecordSheet = true
            case .multi:
                AppAnalytics.shared.logOperation("launch_action_new_multi")
                settings.showMeasurementAvgSheet = true
            }
            // シートのスライドイン（約0.35s）で画面が覆われてからブロック層を外す。
            // 万一シートが開かなかった場合の保険も兼ねる。
            try? await Task.sleep(for: .milliseconds(400))
            isPreparingLaunchSheet = false
        }
    }

    private func switchTab(to tab: RootTab) {
        // シートを開いている・未保存の編集中はタブ移動で驚かせない
        guard !settings.newRecordSheetModified,
              !settings.showNewRecordSheet,
              !settings.showMeasurementAvgSheet else { return }
        AppAnalytics.shared.logOperation("launch_action_tab_\(tab.analyticsName)")
        selectedTab = tab
    }
}

private enum RootTab: Hashable {
    case records
    case graph
    case statistics
    case settings

    var analyticsName: String {
        switch self {
        case .records: return "records"
        case .graph: return "graph"
        case .statistics: return "statistics"
        case .settings: return "settings"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: BodyRecord.self, inMemory: true)
}
