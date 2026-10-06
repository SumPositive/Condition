// ConditionApp.swift
// アプリエントリポイント（旧 AppDelegate 相当）

import SwiftUI
import SwiftData
import UserNotifications
import FirebaseCore
@preconcurrency import GoogleMobileAds

@main
@MainActor
struct ConditionApp: App {

    @State private var migrationService = MigrationService()
    @State private var settings = AppSettings.shared
    /// 測定時刻の通知のタップを受け取る
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
                // 日付入力の暦も記録と同じ西暦に揃える
                .environment(\.calendar, AppDateCalendar.gregorian)
                // ロケールの暦も西暦にし、DatePicker などの見出しに元号や「西暦」を出さない
                .environment(\.locale, AppDateCalendar.locale)
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

    /// 起動時に開くシートが表示されるまで待つ（最長3秒）。シートを開かない設定なら待たない
    private func waitForLaunchSheetIfNeeded() async {
        guard settings.launchAction.opensSheet else { return }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if settings.showMeasurementAvgSheet || settings.showSymptomSheet || settings.showNewRecordSheet {
                // シートのスライドインが終わるまで少し置く
                try? await Task.sleep(for: .milliseconds(500))
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
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
            // 起動時にシートを開く設定なら、シートが開くまで広告の準備を待つ。
            // 同意の確認・SDK の初期化・バナー用 WebView の起動がメインスレッドを数秒ふさぎ、
            // 起動時のシートが大きく遅れていたため（計測で 0.35 秒の予定が 4 秒超）
            await waitForLaunchSheetIfNeeded()
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
        // 症状メモの記録シートもルートレベルで呈示する（測定の2種と同じ扱い）
        .sheet(isPresented: Bindable(settings).showSymptomSheet,
               onDismiss: {
                   settings.showSymptomSheet = false
                   settings.symptomSheetModified = false
               }) {
            SymptomEditView(
                mode: .addNew,
                onModifiedChanged: { settings.symptomSheetModified = $0 }
            )
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


// MARK: - 測定時刻の通知

/// 通知のタップを受け取り、測定シートを開く合図を出す
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 通知から起動したときのタップも受け取れるよう、起動直後に設定する
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// アプリを開いているときも、音なしで表示だけする
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// 測定時刻の通知がタップされたら、測定シートを開く
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier.hasPrefix(MeasurementReminder.identifierPrefix) else { return }
        await MainActor.run {
            AppAnalytics.shared.logOperation("measurement_reminder_open")
            AppSettings.shared.pendingReminderMeasurement = true
        }
    }
}

/// 測定時刻の通知を登録する。
/// 記録から推定した曜日ごとの区分で、通知 ON の区分がその曜日に最初に現れる時刻に、毎週くり返しのローカル通知を置く。
/// その曜日に推定が無い（未定）区分は通知しない（時間帯マップでは補わない）。表示だけで音・振動は無い
enum MeasurementReminder {
    /// このアプリの測定時刻の通知の識別子の頭
    static let identifierPrefix = "measurementReminder."
    /// iOS が保持できる予約は 64 件まで
    private static let maxRequests = 60

    /// 区分の時間帯が始まる曜日と時刻（weekday は 1=日曜〜7=土曜）
    struct Slot: Hashable {
        let dateOpt: DateOpt
        let weekday: Int
        let hour: Int
    }

    /// 通知の許可を求める（表示だけ。音・バッジは求めない）
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert])) ?? false
        default:
            return false
        }
    }

    /// 予約を作り直す。起動・復帰時と、通知や区分の設定を変えたときに呼ぶ
    @MainActor
    static func reschedule() {
        let settings = AppSettings.shared
        let targets = Set(settings.reminderDateOpts.compactMap(DateOpt.init(rawValue:)).filter(\.isDefined))
        // 予約を作る材料は画面側で集め、登録だけを後で行う
        let slots: [Slot]
        if targets.isEmpty {
            slots = []
        } else {
            let context = ModelContainer.shared.mainContext
            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate { $0.dateTime < bodyRecordGoalDate }
            )
            let records = (try? context.fetch(descriptor)) ?? []
            slots = firstSlots(
                table: weeklyTable(records: records, hourMap: settings.dateOptHourMap, referenceDate: Date()),
                targets: targets
            )
        }
        let requests = slots.prefix(maxRequests).map(request(for:))
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            )
            guard !requests.isEmpty else { return }
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            for request in requests {
                try? await center.add(request)
            }
        }
    }

    /// 曜日（1〜7）× 時（0〜23）の推定区分表（nil = 未定）。設定画面の分布表と同じ推定
    @MainActor
    static func weeklyTable(
        records: [BodyRecord],
        hourMap: [Int],
        referenceDate: Date
    ) -> [[DateOpt?]] {
        let calendar = AppDateCalendar.gregorian
        return (1...7).map { weekday in
            (0..<24).map { hour in
                // 推定は曜日と時刻を使うため、同じ週の代表日時を作れば十分
                var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
                components.weekday = weekday
                components.hour = hour
                components.minute = 0
                let target = calendar.date(from: components) ?? referenceDate
                return DateOptEstimator.estimateResult(
                    from: records, targetDate: target, hourMap: hourMap, referenceDate: referenceDate
                ).estimated
            }
        }
    }

    /// 曜日ごとに、通知する区分が最初に現れる時刻を集める（その曜日に推定が無い区分は通知しない）
    static func firstSlots(table: [[DateOpt?]], targets: Set<DateOpt>) -> [Slot] {
        var result: [Slot] = []
        for dayIndex in table.indices {
            for target in DateOpt.allCases where targets.contains(target) {
                guard let hour = table[dayIndex].firstIndex(of: target) else { continue }
                result.append(Slot(dateOpt: target, weekday: dayIndex + 1, hour: hour))
            }
        }
        return result
    }

    @MainActor
    private static func request(for slot: Slot) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "reminder.titleFormat"), slot.dateOpt.displayName)
        content.body = String(localized: "reminder.body")
        // 表示だけにする（音・振動なし）
        content.sound = nil
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.weekday = slot.weekday
        components.hour = slot.hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let identifier = "\(identifierPrefix)\(slot.dateOpt.rawValue).\(slot.weekday).\(slot.hour)"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
