// ConditionApp.swift
// アプリエントリポイント（旧 AppDelegate 相当）

import SwiftUI
import SwiftData
import FirebaseCore
@preconcurrency import GoogleMobileAds

@main
@MainActor
struct ConditionApp: App {

    @State private var migrationService = MigrationService()
    @State private var settings = AppSettings.shared

    init() {
        // FirebaseはAnalytics/Crashlyticsの利用前に初期化する
        FirebaseApp.configure()
        AppAnalytics.shared.configure()

        // 改善案2: ModelContainer.shared を初期化する前に
        // SwiftData ストアファイルを "AzBodyNote" → "Condition" へリネーム
        // （CoreData 移行完了済みユーザーのみ対象。未移行ユーザーの旧ファイルは触らない）
        ModelContainer.renameSwiftDataStoreIfNeeded()

        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        UITabBarItem.appearance().setTitleTextAttributes(attrs, for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes(attrs, for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            RootSceneView(migrationService: migrationService, settings: settings)
        }
        .modelContainer(ModelContainer.shared)
    }
}

private struct RootSceneView: View {
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    let migrationService: MigrationService
    let settings: AppSettings

    private var effectiveDynamicTypeSize: DynamicTypeSize {
        #if DEBUG
        // fastlane snapshot 撮影時は起動引数で文字サイズを固定できる
        // （iPad は余白が目立つので UITest 側から "large" 等を渡して見映えを上げる）
        if let forced = SnapshotSeed.forcedDynamicTypeSize {
            return forced
        }
        #endif
        // 自動ではシステム文字サイズをそのまま使い、ビュー構造は常に同じに保つ。
        return settings.fontScale.followsSystem ? systemDynamicTypeSize : settings.fontScale.dynamicTypeSize
    }

    var body: some View {
        Group {
            switch migrationService.phase {
            case .idle, .checking:
                ProgressView("app.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .migrating(let progress):
                MigrationProgressView(progress: progress)

            case .done:
                ContentView()

            case .failed(let message):
                MigrationErrorView(message: message) {
                    // 再試行
                    Task {
                        let context = ModelContainer.shared.mainContext
                        await migrationService.migrateIfNeeded(context: context)
                    }
                } onSkip: {
                    // スキップして続行
                    // migrationDone フラグは立てない → 次回アップデートで自動再試行
                    migrationService.skipMigration()
                }
            }
        }
        .task {
            let context = ModelContainer.shared.mainContext
            await migrationService.migrateIfNeeded(context: context)
        }
        .task {
            #if DEBUG || targetEnvironment(simulator)
            // テストデバイス登録は必ず start() の前に行う（後だと初回リクエストに反映されない）。
            // 未登録の実機で広告を初回リクエストすると、SDK が Xcode コンソールへ
            //   <Google> To get test ads on this device, set:
            //   GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = @[ @"xxxx" ];
            // というログを出すので、その "xxxx" を下の配列へ転記すると常にテスト広告が返る。
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
                // シミュレータをテストデバイスとして明示登録する（"Simulator" は SDK 予約値）。
                // 実機でテスト広告を見たいときは、起動ログに出るIDをここへ一時的に追加する。
                "Simulator",
            ]
            #endif
            // 広告リクエスト前に UMP 同意情報を解決する（未解決だと全ユニット No fill になり得る）
            await AdConsentManager.gatherConsent()
            // Google公式の推奨どおりアプリ起動時にSDKを一度だけ初期化する
            await MobileAds.shared.start()
            // 初期化完了後にだけバナーをロードさせる（start前リクエストの No fill を防ぐ）
            AdReadyState.shared.markReady()
        }
        .preferredColorScheme(settings.appearanceMode.colorScheme)
        .dynamicTypeSize(effectiveDynamicTypeSize)
        // 新規記録シートをルートレベルで呈示：TabView の選択タブに関わらず確実に表示される
        .sheet(isPresented: Bindable(settings).showNewRecordSheet,
               onDismiss: {
                   // 保険：シート閉じ完了時に状態を確実にリセット
                   // （ネストされた衝突シート併用時にバインディングが戻らないケースの安全装置）
                   settings.showNewRecordSheet = false
                   settings.newRecordSheetModified = false
               }) {
            RecordEditView(
                mode: .addNew,
                onModifiedChanged: { settings.newRecordSheetModified = $0 }
            )
        }
        // 複数回測定（平均）シートもルートレベルで呈示：起動時アクション・一覧の「＋」の
        // どちらからも settings.showMeasurementAvgSheet 経由で開く（TabView の選択に関わらず表示）。
        .sheet(isPresented: Bindable(settings).showMeasurementAvgSheet,
               onDismiss: {
                   // 保険：シート閉じ完了時に状態を確実にリセット（戻り漏れの安全装置）
                   settings.showMeasurementAvgSheet = false
               }) {
            MeasurementAverageView()
        }
    }
}

private extension AppAppearanceMode {
    var colorScheme: ColorScheme? {
        // 自動はシステム設定へ任せる
        switch self {
        case .automatic: return nil
        case .light:     return .light
        case .dark:      return .dark
        }
    }
}

// MARK: - 移行中画面

private struct MigrationProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 68))
                .foregroundStyle(Color.azuki)

            Text("migration.inProgress")
                .font(.title3)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 240)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

// MARK: - 移行エラー画面

private struct MigrationErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onSkip: () -> Void

    @State private var showDetail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 54))
                    .foregroundStyle(.orange)

                Text("migration.failed")
                    .font(.title3.weight(.semibold))

                Text("migration.failedDescription")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button("action.retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Button("migration.skipAndContinue", role: .destructive, action: onSkip)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                VStack(spacing: 6) {
                    Text("migration.skipNote")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Text("migration.originalProtected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                // 技術的な詳細は折りたたみで表示
                DisclosureGroup(isExpanded: $showDetail) {
                    Text(message)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Text("migration.errorDetail")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
            }
            .padding(40)
        }
    }
}
