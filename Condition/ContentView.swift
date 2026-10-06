// ContentView.swift
// ルートタブビュー

import SwiftUI
import UIKit

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .records
    /// 起動時アクションのシートが開くまで前画面のタップを防ぐブロック層の表示状態。
    /// cold launch でシートを開く設定なら、最初の描画からブロック層を出しておく
    /// （onAppear で立てると、一覧が先に一瞬見えてからプログレスが出る）
    @State private var isPreparingLaunchSheet = AppSettings.shared.launchAction.opensSheet
    /// 一度でもバックグラウンドへ入ったか（cold launch と復帰を区別して遅延を最小化する）
    @State private var hasEnteredBackground = false
    /// cold launch 時の起動アクションを onAppear と onChange で二重実行しないためのフラグ
    @State private var didRunInitialLaunchAction = false
    /// 記録タブの再タップで開く記録メニューの表示状態
    @State private var isRecordMenuPresented = false
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        TabView(selection: tabSelection) {
            RecordListView()
                .tabItem {
                    if settings.userLevel == .beginner {
                        Label(
                            "tab.records",
                            systemImage: "list.bullet.clipboard"
                        )
                        // UITestでデバイスに依存せずタブを操作するための識別子
                        .accessibilityIdentifier("tab.records")
                    } else {
                        Image(systemName: "list.bullet.clipboard")
                            .accessibilityIdentifier("tab.records")
                            .accessibilityLabel(Text("tab.records"))
                    }
                }
                .tag(RootTab.records)

            // 選択中の分析ページだけがデータ抽出と図表生成を行う
            AnalysisPageView(page: .one, isActive: selectedTab == .analysis1)
                .tabItem {
                    if settings.userLevel == .beginner {
                        // 初心者には番号アイコンの意味を文字でも示す
                        Label {
                            Text(AnalysisPage.one.displayTitle(in: settings.analysisLayout))
                        } icon: {
                            Image(systemName: AnalysisPage.one.tabSymbol)
                        }
                        .accessibilityIdentifier("tab.graph")
                        .accessibilityLabel(
                            AnalysisPage.one.accessibilityTitle(in: settings.analysisLayout)
                        )
                    } else {
                        Image(systemName: AnalysisPage.one.tabSymbol)
                            .accessibilityIdentifier("tab.graph")
                            .accessibilityLabel(
                                AnalysisPage.one.accessibilityTitle(in: settings.analysisLayout)
                            )
                    }
                }
                .tag(RootTab.analysis1)

            AnalysisPageView(page: .two, isActive: selectedTab == .analysis2)
                .tabItem {
                    if settings.userLevel == .beginner {
                        Label {
                            Text(AnalysisPage.two.displayTitle(in: settings.analysisLayout))
                        } icon: {
                            Image(systemName: AnalysisPage.two.tabSymbol)
                        }
                        .accessibilityIdentifier("tab.statistics")
                        .accessibilityLabel(
                            AnalysisPage.two.accessibilityTitle(in: settings.analysisLayout)
                        )
                    } else {
                        Image(systemName: AnalysisPage.two.tabSymbol)
                            .accessibilityIdentifier("tab.statistics")
                            .accessibilityLabel(
                                AnalysisPage.two.accessibilityTitle(in: settings.analysisLayout)
                            )
                    }
                }
                .tag(RootTab.analysis2)

            AnalysisPageView(page: .three, isActive: selectedTab == .analysis3)
                .tabItem {
                    if settings.userLevel == .beginner {
                        Label {
                            Text(AnalysisPage.three.displayTitle(in: settings.analysisLayout))
                        } icon: {
                            Image(systemName: AnalysisPage.three.tabSymbol)
                        }
                        .accessibilityIdentifier("tab.analysis3")
                        .accessibilityLabel(
                            AnalysisPage.three.accessibilityTitle(in: settings.analysisLayout)
                        )
                    } else {
                        Image(systemName: AnalysisPage.three.tabSymbol)
                            .accessibilityIdentifier("tab.analysis3")
                            .accessibilityLabel(
                                AnalysisPage.three.accessibilityTitle(in: settings.analysisLayout)
                            )
                    }
                }
                .tag(RootTab.analysis3)

            SettingsView()
                .tabItem {
                    if settings.userLevel == .beginner {
                        Label(
                            "tab.settings",
                            systemImage: "gear"
                        )
                        .accessibilityIdentifier("tab.settings")
                    } else {
                        Image(systemName: "gear")
                            .accessibilityIdentifier("tab.settings")
                            .accessibilityLabel(Text("tab.settings"))
                    }
                }
                .tag(RootTab.settings)
        }
        // タブ項目の構成が変わるユーザーレベル変更時だけ再構成する
        // 選択状態は selectedTab にあるので、再構成後も同じタブを維持する
        .id(settings.userLevel)
        .onAppear {
            AppAnalytics.shared.logScreen(selectedTab.analyticsName)
            // cold launch：フォアグラウンド表示と同時にブロック層を出したいので、
            // scenePhase の onChange を待たず最初の描画時にここで起動アクションを開始する。
            // 通知から起動した場合は、起動時アクションより測定シートを優先する
            if settings.pendingReminderMeasurement {
                didRunInitialLaunchAction = true
                openMeasurementFromReminderIfNeeded()
            }
            if !didRunInitialLaunchAction {
                didRunInitialLaunchAction = true
                // シート系アクションはこの時点で即ブロック層を立ててチラつき・誤タップを防ぐ
                if settings.launchAction.opensSheet {
                    isPreparingLaunchSheet = true
                }
                performLaunchAction(settings.launchAction)
            }
            MeasurementReminder.reschedule()
        }
        // 測定時刻の通知がタップされたら測定シートを開く（起動中・復帰時）
        .onChange(of: settings.pendingReminderMeasurement) { _, _ in
            openMeasurementFromReminderIfNeeded()
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
                // 推定は記録が増えると変わるので、復帰のたびに通知の時刻を作り直す
                MeasurementReminder.reschedule()
            }
            // cold launch は onAppear 側で実行済み。ここではバックグラウンド復帰時のみ扱う。
            guard phase == .active, hasEnteredBackground else { return }
            // 通知のタップで戻ったときは、起動時アクションより測定シートを優先する
            if settings.pendingReminderMeasurement {
                openMeasurementFromReminderIfNeeded()
                return
            }
            // 復帰と同時にブロック層を立て、前画面を触らせない。
            // ただし新規記録シートが開いているときは起動アクションを実行しない
            // （performLaunchAction 内で拒否される）ため、暗幕も先出ししない。
            if settings.launchAction.opensSheet,
               !settings.showNewRecordSheet,
               !settings.showMeasurementAvgSheet,
               !settings.showSymptomSheet {
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
        .overlay {
            // タブ位置を固定して描けるiPhoneだけ独自メニューを使う
            if supportsRecordTabMenu {
                recordTabMenuOverlay
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isPreparingLaunchSheet)
        .animation(.easeOut(duration: 0.18), value: isRecordMenuPresented)
    }

    /// 記録タブの上に独自の吹き出しメニューを重ねる
    private var recordTabMenuOverlay: some View {
        GeometryReader { proxy in
            if isRecordMenuPresented {
                let tabBarHorizontalInset: CGFloat = 24
                let menuLeading: CGFloat = 12
                let menuWidth = min(280, proxy.size.width - menuLeading * 2)
                let recordTabCenter = tabBarHorizontalInset
                    + (proxy.size.width - tabBarHorizontalInset * 2) / 10
                let pointerX = recordTabCenter - menuLeading

                ZStack(alignment: .bottomLeading) {
                    // メニュー外のタップで閉じる
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isRecordMenuPresented = false
                        }

                    recordTabMenu
                        .padding(.bottom, 12)
                        .frame(width: menuWidth)
                        .background(
                            .regularMaterial,
                            in: RecordTabMenuShape(pointerX: pointerX)
                        )
                        .overlay {
                            RecordTabMenuShape(pointerX: pointerX)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .padding(.leading, menuLeading)
                        // フローティングタブバーの上端へ矢印を合わせる
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 52)
                        .transition(
                            .scale(scale: 0.92, anchor: .bottomLeading)
                                .combined(with: .opacity)
                        )
                        .accessibilityAction(.escape) {
                            isRecordMenuPresented = false
                        }
                }
                .ignoresSafeArea()
            }
        }
    }

    /// 記録タブから開く追加先メニュー
    private var recordTabMenu: some View {
        VStack(spacing: 0) {
            recordTabMenuButton(
                titleKey: "records.add.measurement",
                systemImage: "text.badge.plus",
                kind: .measurement
            )
            recordTabMenuButton(
                titleKey: "records.add.symptom",
                systemImage: "at.badge.plus",
                kind: .symptom
            )
            // ダイアル式は設定で有効な場合だけ表示する
            if settings.useDialRecordEntry {
                Divider()
                    .padding(.horizontal)
                recordTabMenuButton(
                    titleKey: "records.add.dial",
                    systemImage: "plus.circle.fill",
                    kind: .dial
                )
            }
        }
        .padding(.vertical, 8)
    }

    /// 吹き出し内の追加先ボタン
    private func recordTabMenuButton(
        titleKey: LocalizedStringKey,
        systemImage: String,
        kind: RecordSheetKind
    ) -> some View {
        Button {
            isRecordMenuPresented = false
            // 吹き出しを閉じてから追加シートを開く
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                presentRecordSheet(kind)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                // 吹き出しは幅が決まっているので、長い訳語でも欠けたり改行したりせず1行に収める
                Text(titleKey)
                    .font(.title3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .frame(height: 56)
        }
        .buttonStyle(.plain)
    }

    /// TabView の選択バインディング
    /// 記録タブを再タップしたときだけ記録メニューを開く
    private var tabSelection: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .records, selectedTab == .records {
                    presentRecordMenu()
                } else {
                    selectedTab = newTab
                }
            }
        )
    }

    /// 記録タブ再タップで記録メニューを開く
    private func presentRecordMenu() {
        // iPadではタブ配置が変化するため再タップメニューを表示しない
        guard supportsRecordTabMenu else { return }
        // シート表示中はメニューを重ねない
        guard !settings.showNewRecordSheet,
              !settings.showMeasurementAvgSheet,
              !settings.showSymptomSheet else { return }
        AppAnalytics.shared.logOperation("records_tab_retap_menu")
        isRecordMenuPresented = true
    }

    /// 独自のタブメニューを表示できる端末か
    private var supportsRecordTabMenu: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private enum RecordSheetKind {
        case measurement
        case symptom
        case dial
    }

    /// 記録メニューで選んだ追加シートを開く
    private func presentRecordSheet(_ kind: RecordSheetKind) {
        switch kind {
        case .measurement:
            settings.showMeasurementAvgSheet = true
        case .symptom:
            settings.showSymptomSheet = true
        case .dial:
            settings.showNewRecordSheet = true
        }
    }

    /// 測定時刻の通知がタップされていれば、測定シートを開く
    private func openMeasurementFromReminderIfNeeded() {
        guard settings.pendingReminderMeasurement else { return }
        settings.pendingReminderMeasurement = false
        presentSheet(kind: .multi)
    }

    /// 起動（フォアグラウンド復帰）時アクションを実行する
    private func performLaunchAction(_ action: LaunchAction) {
        switch action {
        case .none:
            return
        case .newSingle:
            // ダイアル式が無効なら起動時に開けないので、複数平均式へ振り替える
            presentSheet(kind: settings.useDialRecordEntry ? .single : .multi)
        case .newMulti:
            presentSheet(kind: .multi)
        case .newSymptom:
            presentSheet(kind: .symptom)
        case .records:
            switchTab(to: .records)
        case .graph:
            switchTab(to: .analysis1)
        case .statistics:
            switchTab(to: .analysis2)
        case .analysis3:
            switchTab(to: .analysis3)
        }
    }


    private enum LaunchSheetKind { case single, multi, symptom }

    private func presentSheet(kind: LaunchSheetKind) {
        // 新規記録シート（単体・表形式）が開いているなら何もしない。
        // （呼び出し側で先出ししたブロック層はここで確実に下ろす）
        guard !settings.showNewRecordSheet,
              !settings.showMeasurementAvgSheet,
              !settings.showSymptomSheet else {
            isPreparingLaunchSheet = false
            return
        }
        // 呈示までの間、前画面をタップさせないよう即座にブロック層を出す
        isPreparingLaunchSheet = true
        Task { @MainActor in
            // 暗幕＋プログレスを確実に一度描画・視認させてからシートを開く。
            // この待機は、実機で復帰直後にシートが表示されない事故の回避も兼ねる。
            try? await Task.sleep(for: .milliseconds(350))
            guard !settings.showNewRecordSheet,
                  !settings.showMeasurementAvgSheet,
                  !settings.showSymptomSheet else {
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
            case .symptom:
                AppAnalytics.shared.logOperation("launch_action_new_symptom")
                settings.showSymptomSheet = true
            }
            // シートのスライドイン（約0.35s）で画面が覆われてからブロック層を外す。
            // 万一シートが開かなかった場合の保険も兼ねる。
            try? await Task.sleep(for: .milliseconds(400))
            isPreparingLaunchSheet = false
        }
    }

    private func switchTab(to tab: RootTab) {
        // 新規記録シートが開いているならタブ移動で驚かせない
        guard !settings.showNewRecordSheet,
              !settings.showMeasurementAvgSheet,
              !settings.showSymptomSheet else { return }
        AppAnalytics.shared.logOperation("launch_action_tab_\(tab.analyticsName)")
        selectedTab = tab
    }
}

private enum RootTab: Hashable {
    case records
    case analysis1
    case analysis2
    case analysis3
    case settings

    var analyticsName: String {
        switch self {
        case .records: return "records"
        case .analysis1: return "analysis_1"
        case .analysis2: return "analysis_2"
        case .analysis3: return "analysis_3"
        case .settings: return "settings"
        }
    }
}

/// 記録タブへ向けた矢印を持つ吹き出し形状
private struct RecordTabMenuShape: Shape {
    let pointerX: CGFloat

    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 24
        let pointerWidth: CGFloat = 24
        let pointerHeight: CGFloat = 12
        let bubbleRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - pointerHeight
        )
        let adjustedPointerX = min(
            max(pointerX, cornerRadius + pointerWidth / 2),
            rect.width - cornerRadius - pointerWidth / 2
        )
        var path = Path()
        path.move(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY))
        path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY + cornerRadius),
            control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY)
        )
        path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.maxY),
            control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY)
        )
        path.addLine(
            to: CGPoint(x: adjustedPointerX + pointerWidth / 2, y: bubbleRect.maxY)
        )
        path.addLine(to: CGPoint(x: adjustedPointerX, y: rect.maxY))
        path.addLine(
            to: CGPoint(x: adjustedPointerX - pointerWidth / 2, y: bubbleRect.maxY)
        )
        path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY - cornerRadius),
            control: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY)
        )
        path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY),
            control: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [BodyRecord.self, SymptomRecord.self], inMemory: true)
}
