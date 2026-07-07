// ContentView.swift
// ルートタブビュー

import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .records
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
        }
        .onChange(of: selectedTab) { _, tab in
            // タブ切り替えから、よく使われる機能を把握する
            AppAnalytics.shared.logScreen(tab.analyticsName)
            AppAnalytics.shared.logFeature("tab_select", parameters: ["tab": tab.analyticsName])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AppAnalytics.shared.logSettingsSnapshot(settings: settings, reason: "foreground")
            }
            guard phase == .active, settings.openNewRecordOnForeground else { return }
            // 未保存の変更あり・すでに開いている → 何もしない
            guard !settings.newRecordSheetModified, !settings.showNewRecordSheet else { return }
            // 実機でアプリが完全に復帰してから呈示するため少し待つ
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !settings.showNewRecordSheet else { return }
                AppAnalytics.shared.logOperation("open_new_record_on_foreground")
                settings.showNewRecordSheet = true
            }
        }
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
