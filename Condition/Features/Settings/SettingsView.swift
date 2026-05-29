// SettingsView.swift
// 設定メイン画面（旧 SettingTVC 相当）

import SwiftUI
import SwiftData
import AZDial
import StoreKit
import UniformTypeIdentifiers
import WebKit

private enum RecordJSONExportStyle: Int, CaseIterable, Identifiable {
    case compact = 0
    case pretty = 1

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .compact: return "settings.exportFormat.compact"
        case .pretty:  return "settings.exportFormat.pretty"
        }
    }

    var jsonOptions: JSONSerialization.WritingOptions {
        switch self {
        case .compact:
            return [.sortedKeys]
        case .pretty:
            return [.prettyPrinted, .sortedKeys]
        }
    }
}

private struct SettingsPickerOption: Hashable, Identifiable {
    let id: Int
    let titleKey: String
}

struct SettingsView: View {

    @Environment(\.modelContext) private var context
    @AppStorage("settings.shareExportFormat") private var exportFormatRaw = RecordJSONExportStyle.compact.rawValue
    @State private var settings = AppSettings.shared
    @State private var healthKit = HealthKitService.shared
    @State private var showHKSettings = false
    @State private var showSafari = false
    @State private var showDialSettings = false
    @State private var showImportPicker = false
    @State private var showPruneOldRecordsConfirmSheet = false
    @State private var alertItem: SettingsAlertItem?
    @State private var isWorking = false
    @State private var progressMessage = ""
    @State private var progressHint = ""
    @State private var isMergeWindowExpanded = false
    @State private var isMergeDefaultActionExpanded = false

    private static let mergeWindowOptions = [
        SettingsPickerOption(id: 0, titleKey: "settings.merge.off"),
        SettingsPickerOption(id: 5, titleKey: "settings.merge.5min"),
        SettingsPickerOption(id: 10, titleKey: "settings.merge.10min"),
        SettingsPickerOption(id: 15, titleKey: "settings.merge.15min"),
        SettingsPickerOption(id: 30, titleKey: "settings.merge.30min"),
    ]

    private var aboutURL: URL {
        let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        let urlString = isJapanese
            ? "https://docs.azukid.com/jp/sumpo/Condition/condition.html"
            : "https://docs.azukid.com/en/sumpo/Condition/condition.html"
        var components = URLComponents(string: urlString)!
        components.queryItems = [
            URLQueryItem(name: "fontScale", value: webFontScaleValue)
        ]
        return components.url!
    }

    private var webFontScaleValue: String {
        // Web側のCSSで扱いやすい3段階へ変換する
        switch settings.fontScale {
        case .standard:
            return "standard"
        case .large:
            return "large"
        case .xLarge:
            return "xLarge"
        case .system:
            return currentSystemWebFontScaleValue
        }
    }

    private var currentSystemWebFontScaleValue: String {
        // 自動設定では現在のiOS文字サイズをWeb用の3段階へ丸める
        switch UIApplication.shared.preferredContentSizeCategory {
        case .extraSmall, .small, .medium, .large:
            return "standard"
        case .extraLarge, .extraExtraLarge, .extraExtraExtraLarge:
            return "large"
        default:
            return "xLarge"
        }
    }

    private var exportFormat: RecordJSONExportStyle {
        RecordJSONExportStyle(rawValue: exportFormatRaw) ?? .compact
    }

    private var mergeWindowBinding: Binding<SettingsPickerOption> {
        Binding(
            get: {
                // 保存値をAZPicker用の選択肢へ変換する
                Self.mergeWindowOptions.first { $0.id == settings.mergeWindowMinutes } ?? Self.mergeWindowOptions[2]
            },
            set: { settings.mergeWindowMinutes = $0.id }
        )
    }

    private var mergeDefaultActionBinding: Binding<ConflictAction> {
        Binding(
            get: {
                // 保存値をConflictActionへ戻して選択状態を作る
                ConflictAction(rawValue: settings.mergeDefaultAction) ?? .useAverage
            },
            set: { settings.mergeDefaultAction = $0.rawValue }
        )
    }

    private var exportFormatBinding: Binding<RecordJSONExportStyle> {
        Binding(
            get: {
                // AppStorageの整数値を出力形式へ戻す
                RecordJSONExportStyle(rawValue: exportFormatRaw) ?? .compact
            },
            set: { exportFormatRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 表示
                Section("settings.display") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("settings.userLevel")
                                .font(.subheadline)
                            // ユーザレベルはDynamic Typeに強いラジオPickerで選ぶ
                            AZRadioPicker(
                                options: AppUserLevel.allCases,
                                selection: $settings.userLevel,
                                minOptionWidth: 0,
                                maxOptionWidth: 120,
                                horizontalPadding: 4,
                                optionSpacing: 4,
                                groupPadding: 5,
                                wrapsOptions: false,
                                fillsWidth: true
                            ) { level in
                                Text(LocalizedStringKey(level.titleKey))
                            }
                        }
                        if settings.userLevel == .beginner {
                            Text("settings.help.userLevel")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("appearance.mode")
                            .font(.subheadline)
                        // 外観モードも同じラジオPickerで揃える
                        AZRadioPicker(
                            options: AppAppearanceMode.allCases,
                            selection: $settings.appearanceMode,
                            minOptionWidth: 0,
                            maxOptionWidth: 120,
                            horizontalPadding: 4,
                            optionSpacing: 4,
                            groupPadding: 5,
                            wrapsOptions: false,
                            fillsWidth: true
                        ) { mode in
                            Text(LocalizedStringKey(mode.titleKey))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("settings.fontScale")
                                .font(.subheadline)
                            // 文字サイズは選択肢が欠けないようラジオPickerで表示する
                            AZRadioPicker(
                                options: AppFontScale.allCases,
                                selection: $settings.fontScale,
                                minOptionWidth: 0,
                                maxOptionWidth: 120,
                                horizontalPadding: 4,
                                optionSpacing: 4,
                                groupPadding: 5,
                                wrapsOptions: false,
                                fillsWidth: true
                            ) { scale in
                                Text(LocalizedStringKey(scale.titleKey))
                            }
                        }
                        if settings.userLevel == .beginner {
                            Text("settings.help.fontScale")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        showDialSettings = true
                    } label: {
                        LabeledContent(
                            "settings.dialSettings",
                            value: DialStyle.builtin(id: settings.dialStyle)?.label ?? DialStyle.shape.label
                        )
                    }
                }

                // MARK: - 記録
                Section("tab.records") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("settings.openNewRecordOnForeground", isOn: $settings.openNewRecordOnForeground)
                        if settings.userLevel == .beginner {
                            Text("settings.help.openNewRecordOnForeground")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    NavigationLink("settings.fieldOrder") {
                        FieldOrderSettingsView()
                    }
                    NavigationLink {
                        DateOptMatrixView()
                    } label: {
                        Text("settings.category")
                    }

                    // ヘルスケア
                    if healthKit.isAvailable && !settings.hkDisabledByDemo {
                        NavigationLink {
                            HealthKitSettingsView()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(
                                    "health.integration",
                                    isOn: $settings.hkEnabled
                                )
                                .onChange(of: settings.hkEnabled) { _, enabled in
                                    if enabled {
                                        Task { await healthKit.requestAuthorization() }
                                        showHKSettings = true
                                        healthKit.needsAutoImport = true
                                    } else {
                                        healthKit.clearLastAutoImportAt()
                                    }
                                }

                                if settings.userLevel == .beginner {
                                    // 初心者向けに、削除が連携されない点を明示する
                                    Text("health.integrationHelp")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    // 記録をまとめる（衝突検出）
                    VStack(alignment: .leading, spacing: 8) {
                        AZAdaptiveControlRow {
                            Text("settings.merge.window")
                                .font(.subheadline)
                        } control: {
                            // 記録をまとめる時間は共通のドロップダウンPickerで選ぶ
                            AZDropdownPicker(
                                options: Self.mergeWindowOptions,
                                selection: mergeWindowBinding,
                                isExpanded: $isMergeWindowExpanded,
                                minWidth: 150
                            ) { option in
                                Text(LocalizedStringKey(option.titleKey))
                            }
                        }
                        .zIndex(isMergeWindowExpanded ? 61 : 0)
                        AZAdaptiveControlRow {
                            Text("settings.merge.defaultAction")
                                .font(.subheadline)
                        } control: {
                            // 衝突時の初期選択も同じドロップダウンPickerで選ぶ
                            AZDropdownPicker(
                                options: ConflictAction.allCases,
                                selection: mergeDefaultActionBinding,
                                isExpanded: $isMergeDefaultActionExpanded,
                                minWidth: 170
                            ) { action in
                                Text(action.labelKey)
                            }
                        }
                        .zIndex(isMergeDefaultActionExpanded ? 60 : 0)
                        if settings.userLevel == .beginner {
                            Text("settings.help.merge")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .onAppear { if healthKit.isAvailable { healthKit.checkAuthorization() } }
                .navigationDestination(isPresented: $showHKSettings) {
                    HealthKitSettingsView()
                }

                // MARK: - 分析
                Section("settings.analysis") {
                    NavigationLink("graph.settings") {
                        GraphSettingsView()
                    }
                    NavigationLink("statistics.settings") {
                        StatSettingsView()
                    }
                }

                // MARK: - 共有
                Section("settings.panel.share") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            exportRecordsJSON()
                        } label: {
                            Label("settings.share.exportRecords", systemImage: "square.and.arrow.up")
                        }

                        if settings.userLevel != .beginner {
                            HStack(spacing: 8) {
                                Spacer(minLength: 40)
                                Text("settings.exportFormat.title")
                                    .font(.subheadline)
                                // JSON形式はラジオPickerで現在値を明示する
                                AZRadioPicker(
                                    options: RecordJSONExportStyle.allCases,
                                    selection: exportFormatBinding,
                                    minOptionWidth: 0,
                                    maxOptionWidth: 120,
                                    horizontalPadding: 4,
                                    optionSpacing: 4,
                                    groupPadding: 5,
                                    wrapsOptions: false,
                                    fillsWidth: true
                                ) { style in
                                    Text(LocalizedStringKey(style.titleKey))
                                }
                            }
                        }

                        if settings.userLevel == .beginner {
                            Text("settings.help.exportRecords")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("settings.share.importRecords", systemImage: "square.and.arrow.down")
                        }

                        if settings.userLevel == .beginner {
                            Text("settings.help.importRecords")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showPruneOldRecordsConfirmSheet = true
                        } label: {
                            Label("settings.share.pruneOldRecords", systemImage: "trash")
                        }

                        if settings.userLevel == .beginner {
                            Text("settings.help.pruneOldRecords")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // MARK: - アプリ情報
                Section {
                    Button("app.about") {
                        showSafari = true
                    }
                }

                // MARK: - 開発者を応援
                Section {
                    SupportDeveloperView()
                }

                // MARK: - バージョン
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                Text(String(format: String(localized: "format.version"), version, build))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("tab.settings")
        }
        .sheet(isPresented: $showSafari) {
            SafariView(url: aboutURL)
        }
        .sheet(isPresented: $showDialSettings) {
            let content = NavigationStack {
                AZDialSettingsView(
                    tuning: $settings.dialTuning,
                    style: dialStyleBinding,
                    configuration: dialSettingsConfiguration
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("action.done") {
                            showDialSettings = false
                        }
                    }
                }
            }
            // sheetは親の文字サイズ環境を引き継がないことがあるため、アプリ設定を優先する
            if settings.fontScale.followsSystem {
                content
            } else {
                content.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
            }
        }
        .sheet(isPresented: $showPruneOldRecordsConfirmSheet) {
            PruneOldRecordsConfirmSheet {
                pruneOldRecords()
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importRecordsJSON(from: url)
            case .failure(let error):
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
        .alert(item: $alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .cancel(Text("action.ok"))
            )
        }
        .overlay {
            if isWorking {
                progressOverlay
            }
        }
    }

    private var dialStyleBinding: Binding<DialStyle> {
        Binding(
            get: { DialStyle.builtin(id: settings.dialStyle) ?? .shape },
            set: { settings.dialStyle = $0.id }
        )
    }

    private var dialSettingsConfiguration: AZDialSettingsConfiguration {
        AZDialSettingsConfiguration(
            title: "settings.dialSettings",
            localizationBundle: .main
        )
    }

    private func exportRecordsJSON() {
        Task { @MainActor in
            isWorking = true
            progressMessage = String(localized: "settings.share.exportPreparing")
            progressHint = String(localized: "settings.share.exportHint")
            await Task.yield()
            defer { isWorking = false }

            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate { $0.dateTime < bodyRecordGoalDate },
                sortBy: [SortDescriptor(\BodyRecord.dateTime)]
            )
            let records = (try? context.fetch(descriptor)) ?? []
        let data = makeExportJSON(records: records, style: exportFormat)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "Condition_\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try data.write(to: url, options: Data.WritingOptions.atomic)
                progressMessage = String(localized: "settings.share.exportOpening")
                await Task.yield()
                presentShareSheet(url: url)
            } catch {
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
    }

    private func importRecordsJSON(from url: URL) {
        Task { @MainActor in
            isWorking = true
            progressMessage = String(localized: "settings.share.importPreparing")
            progressHint = String(localized: "settings.share.importHint")
            await Task.yield()
            defer { isWorking = false }

            let startedAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if startedAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let envelope = try decoder.decode(RecordImportEnvelope.self, from: data)
                if let categoryAppearances = envelope.categoryAppearances {
                    // バックアップに同梱された区分表示マスタを復元する
                    settings.dateOptAppearances = normalizedDateOptAppearances(categoryAppearances)
                }
                let result = try mergeImportedRecords(envelope.records)
                alertItem = .raw(
                    title: String(localized: "settings.share.importDoneTitle"),
                    message: String(
                        format: String(localized: "settings.share.importDoneMessage"),
                        result.inserted,
                        result.updated
                    )
                )
            } catch {
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
    }

    private func pruneOldRecords() {
        Task { @MainActor in
            isWorking = true
            progressMessage = String(localized: "settings.share.prunePreparing")
            progressHint = String(localized: "settings.share.pruneHint")
            await Task.yield()
            defer { isWorking = false }

            let cutoff = Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate { $0.dateTime < cutoff && $0.dateTime < bodyRecordGoalDate }
            )
            let targets = (try? context.fetch(descriptor)) ?? []

            for record in targets {
                context.delete(record)
            }

            do {
                try context.save()
                alertItem = .raw(
                    title: String(localized: "settings.share.pruneDoneTitle"),
                    message: String(format: String(localized: "settings.share.pruneDoneMessage"), targets.count)
                )
            } catch {
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
    }

    private func presentShareSheet(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            alertItem = .raw(
                title: String(localized: "settings.share.errorTitle"),
                message: String(localized: "settings.share.presenterUnavailable")
            )
            try? FileManager.default.removeItem(at: url)
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        topVC.present(activityVC, animated: true)
    }

    private func makeExportJSON(records: [BodyRecord], style: RecordJSONExportStyle) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]

        var result: [[String: Any]] = []
        for record in records {
            var object: [String: Any] = [
                "dateTime": iso.string(from: record.dateTime),
                "condition": record.dateOpt.displayName,
                "conditionRaw": record.nDateOpt,
                "dataSourceRaw": record.nDataSource,
                "cautionFlag": record.bCaution,
                "memo1": record.sNote1,
                "memo2": record.sNote2,
                "device": record.sEquipment,
            ]
            if 0 < record.nBpHi_mmHg { object["bpSystolic"] = record.nBpHi_mmHg }
            if 0 < record.nBpLo_mmHg { object["bpDiastolic"] = record.nBpLo_mmHg }
            if 0 < record.nPulse_bpm { object["heartRate"] = record.nPulse_bpm }
            if 0 < record.nTemp_10c { object["bodyTemp"] = decimalNumber(record.nTemp_10c, scale: 1) }
            if 0 < record.nWeight_10Kg { object["weight"] = decimalNumber(record.nWeight_10Kg, scale: 1) }
            if 0 < record.nBodyFat_10p { object["bodyFat"] = decimalNumber(record.nBodyFat_10p, scale: 1) }
            if 0 < record.nSkMuscle_10p { object["skeletalMuscle"] = decimalNumber(record.nSkMuscle_10p, scale: 1) }
            result.append(object)
        }

        let envelope: [String: Any] = [
            "categoryAppearances": categoryAppearanceObjects(),
            "exportDate": iso.string(from: Date()),
            "records": result,
        ]

        return (try? JSONSerialization.data(withJSONObject: envelope, options: style.jsonOptions)) ?? Data()
    }

    private func decimalNumber(_ value: Int, scale: Int) -> NSDecimalNumber {
        // JSON出力でDoubleの2進小数誤差が長く出ないよう、10進数として出力する
        NSDecimalNumber(value: value).dividing(by: NSDecimalNumber(mantissa: 1, exponent: Int16(scale), isNegative: false))
    }

    private func mergeImportedRecords(_ importedRecords: [RecordImportRecord]) throws -> (inserted: Int, updated: Int) {
        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime < bodyRecordGoalDate }
        )
        let existingRecords = try context.fetch(descriptor)
        var existingByDate: [Date: BodyRecord] = [:]
        for record in existingRecords {
            existingByDate[record.dateTime] = record
        }

        var inserted = 0
        var updated = 0
        for imported in importedRecords {
            guard let date = imported.parsedDate else { continue }
            let record: BodyRecord
            if let existing = existingByDate[date] {
                record = existing
                updated += 1
            } else {
                record = BodyRecord(dateTime: date, dateOpt: imported.dateOpt ?? .cat02)
                context.insert(record)
                existingByDate[date] = record
                inserted += 1
            }

            record.dateTime = date
            record.dateOpt = imported.dateOpt ?? .cat02
            record.dataSource = imported.dataSource ?? .appInput
            record.bCaution = imported.cautionFlag ?? false
            record.sNote1 = imported.memo1 ?? ""
            record.sNote2 = imported.memo2 ?? ""
            record.sEquipment = imported.device ?? ""
            record.nBpHi_mmHg = imported.bpSystolic ?? 0
            record.nBpLo_mmHg = imported.bpDiastolic ?? 0
            record.nPulse_bpm = imported.heartRate ?? 0
            record.nTemp_10c = imported.bodyTemp.map { Int(($0 * 10).rounded()) } ?? 0
            record.nWeight_10Kg = imported.weight.map { Int(($0 * 10).rounded()) } ?? 0
            record.nBodyFat_10p = imported.bodyFat.map { Int(($0 * 10).rounded()) } ?? 0
            record.nSkMuscle_10p = imported.skeletalMuscle.map { Int(($0 * 10).rounded()) } ?? 0
        }

        try context.save()
        return (inserted, updated)
    }

    private func categoryAppearanceObjects() -> [[String: Any]] {
        DateOpt.allCases.map { dateOpt in
            let appearance = settings.dateOptAppearances.first { $0.dateOptRawValue == dateOpt.rawValue } ?? dateOpt.defaultAppearance
            return [
                "dateOptRawValue": appearance.dateOptRawValue,
                "nameJa": appearance.nameJa,
                "nameEn": appearance.nameEn,
                "iconName": appearance.iconName,
                "colorKey": appearance.colorKey,
            ]
        }
    }

    private func normalizedDateOptAppearances(_ imported: [DateOptAppearance]) -> [DateOptAppearance] {
        DateOpt.allCases.map { dateOpt in
            if let appearance = imported.first(where: { $0.dateOptRawValue == dateOpt.rawValue }) {
                // 既存区分だけを採用し、新しい区分や欠落区分は既定値で補完する
                return appearance
            }
            return dateOpt.defaultAppearance
        }
    }

    private var progressOverlay: some View {
        ZStack {
            // 入出力処理中は背面操作を受け付けない
            Color.black.opacity(0.24)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text(progressMessage)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(progressHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
        }
    }

}

private extension SettingsView {
    struct SettingsAlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String

        static func raw(title: String, message: String) -> SettingsAlertItem {
            SettingsAlertItem(title: title, message: message)
        }
    }
}

private struct RecordImportEnvelope: Decodable {
    let categoryAppearances: [DateOptAppearance]?
    let records: [RecordImportRecord]
}

private struct RecordImportRecord: Decodable {
    let dateTime: String
    let condition: String?
    let conditionRaw: Int?
    let dataSourceRaw: Int?
    let cautionFlag: Bool?
    let memo1: String?
    let memo2: String?
    let device: String?
    let bpSystolic: Int?
    let bpDiastolic: Int?
    let heartRate: Int?
    let bodyTemp: Double?
    let weight: Double?
    let bodyFat: Double?
    let skeletalMuscle: Double?

    var parsedDate: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return iso.date(from: dateTime)
    }

    var dateOpt: DateOpt? {
        if let conditionRaw {
            return DateOpt(rawValue: conditionRaw)
        }
        guard let condition, !condition.isEmpty else { return nil }
        if let exact = DateOpt.allCases.first(where: { $0.label == condition }) {
            return exact
        }
        if let custom = DateOpt.allCases.first(where: { $0.displayName == condition }) {
            return custom
        }
        // 旧export JSONは旧キー名をconditionに持つ可能性があるため、import互換として残す
        if let legacy = legacyDateOpt(for: condition) {
            return legacy
        }
        return DateOpt.allCases.first {
            NSLocalizedString($0.label, comment: "") == condition
        }
    }

    var dataSource: RecordDataSource? {
        guard let dataSourceRaw else { return nil }
        return RecordDataSource(rawValue: dataSourceRaw)
    }

    private func legacyDateOpt(for condition: String) -> DateOpt? {
        let legacyPairs: [(String, DateOpt)] = [
            ("category.wake", .cat01),
            ("category.rest", .cat02),
            ("category.beforeBed", .cat03),
            ("category.bedtime", .cat04),
            ("category.preExercise", .cat05),
            ("category.postExercise", .cat06),
        ]
        return legacyPairs.first { $0.0 == condition }?.1
    }
}

// MARK: - 古い記録整理の確認シート

private struct PruneOldRecordsConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("settings.share.pruneConfirmTitle")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    Text("settings.share.pruneConfirmMessage")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 14) {
                        Button(role: .destructive) {
                            dismiss()
                            onConfirm()
                        } label: {
                            Text("action.delete")
                        }
                        .buttonStyle(.bordered)

                        Button("action.cancel") {
                            dismiss()
                        }
                        .font(.title3.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


// MARK: - SafariView

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = WebViewController(url: url)
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

private class WebViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private var webView: WKWebView!

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let closeImage = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(scale: .large)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: closeImage,
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        webView = WKWebView()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        webView.load(URLRequest(url: url))
    }

    @objc private func doneTapped() { dismiss(animated: true) }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              url.host?.contains("apps.apple.com") == true else {
            return .allow
        }
#if targetEnvironment(simulator)
        let alert = UIAlertController(title: nil,
                                      message: String(localized: "error.simulatorCannotOpen"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
        present(alert, animated: true)
#else
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#endif
        return .cancel
    }
}

// MARK: - 開発者を応援

private struct SupportDeveloperView: View {
    @State private var store = TipStore.shared
    @State private var showTip = false
    @State private var showAd = false
    @State private var showAdThankYou = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("support.title")
                    .font(.body.weight(.medium))
            } icon: {
                Image(systemName: "heart.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.periodic(delay: 0.0)))
            }

            Button {
                showTip = true
            } label: {
                Text("support.tip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .sheet(isPresented: $showTip) {
                TipSheetView()
            }

            Button {
                showAd = true
            } label: {
                Text("support.watchAd")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brown)
            .sheet(isPresented: $showAd) {
                AdMobAdSheetView {
                    showAdThankYou = true
                }
            }
        }
        .padding(.vertical, 4)
        .task { await store.loadProducts() }
        .alert(
            "support.thanks.title",
            isPresented: $showAdThankYou
        ) {
            Button("action.ok") {}
        } message: {
            Text("support.thankYouForWatchingTheAd")
        }
    }
}

private struct TipSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = TipStore.shared
    @State private var showThankYou = false
    @State private var activeThrow: CoinThrow? = nil
    @State private var targetScale: CGFloat = 1.0
    private var settings: AppSettings { AppSettings.shared }

    private struct CoinThrow: Identifiable {
        let id = UUID()
        let buttonIndex: Int
        let color: Color
        let product: Product
    }

    var body: some View {
        let content = NavigationStack {
            GeometryReader { geo in
                ZStack {
                    sheetContent(geo: geo)
                    if let toss = activeThrow {
                        let startX = toss.buttonIndex == 0
                            ? geo.size.width * 0.33
                            : geo.size.width * 0.67
                        TossedCoin(
                            key: toss.id,
                            start: CGPoint(x: startX, y: geo.size.height - 130),
                            end: CGPoint(x: geo.size.width * 0.5, y: 90),
                            color: toss.color
                        ) {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) {
                                targetScale = 1.22
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                withAnimation(.spring) { targetScale = 1.0 }
                            }
                            let product = toss.product
                            activeThrow = nil
                            Task {
                                if await store.purchase(product) {
                                    showThankYou = true
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("support.tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .task { await store.loadProducts() }
            .alert(
                "support.thanks.title",
                isPresented: $showThankYou
            ) {
                Button("action.ok") { dismiss() }
            } message: {
                Text("support.thankYouForYourSupportWe")
            }
        }
        if settings.fontScale.followsSystem {
            content
        } else {
            content.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
        }
    }

    @ViewBuilder
    private func sheetContent(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            developerTarget
                .padding(.top, 32)

            TossArcHint()
                .frame(height: 52)
                .padding(.horizontal, 56)
                .padding(.top, 6)

            Text("support.yourSupportHelpsKeepThisApp")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .padding(.top, 16)

            Spacer()
            coinSection
                .padding(.bottom, 56)
        }
    }

    private var developerTarget: some View {
        ZStack {
            Circle()
                .fill(.pink.opacity(0.10))
                .frame(width: 108, height: 108)
            Circle()
                .stroke(.pink.opacity(0.22), lineWidth: 1.5)
                .frame(width: 108, height: 108)
            Image(systemName: "person.fill")
                .font(.system(size: 50))
                .foregroundStyle(.pink)
            Image(systemName: "heart.fill")
                .font(.system(size: 18))
                .foregroundStyle(.pink)
                .offset(x: 24, y: -24)
        }
        .scaleEffect(targetScale)
    }

    @ViewBuilder
    private var coinSection: some View {
        if store.isLoadingProducts {
            ProgressView()
        } else if store.products.isEmpty {
            Text("text.notAvailableAtThisTime")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 40) {
                ForEach(Array(store.products.enumerated()), id: \.element.id) { index, product in
                    let isLarge = index == store.products.count - 1
                    let coinColor: Color = isLarge
                        ? Color(red: 0.90, green: 0.72, blue: 0.18)
                        : Color(red: 0.72, green: 0.45, blue: 0.20)
                    TipCoinButton(
                        price: product.displayPrice,
                        color: coinColor,
                        disabled: activeThrow != nil || store.isPurchasing
                    ) {
                        activeThrow = CoinThrow(
                            buttonIndex: index,
                            color: coinColor,
                            product: product
                        )
                    }
                }
            }
        }
    }
}

// MARK: - コインボタン

private struct TipCoinButton: View {
    let price: String
    let color: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 1)
                    .padding(10)
                Text(price)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(color)
            }
            .frame(width: 100, height: 100)
            .shadow(color: color.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(TipCoinPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }
}

private struct TipCoinPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - 軌跡ヒント

private struct TossArcHint: View {
    var body: some View {
        Canvas { ctx, size in
            let width = size.width
            let height = size.height
            for (startRatio, controlRatio) in [(0.25, 0.82), (0.75, 0.18)] as [(Double, Double)] {
                var path = Path()
                path.move(to: CGPoint(x: width * startRatio, y: height))
                path.addQuadCurve(
                    to: CGPoint(x: width * 0.5, y: 0),
                    control: CGPoint(x: width * controlRatio, y: height * 0.12)
                )
                ctx.stroke(
                    path,
                    with: .color(.secondary.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 5])
                )
            }
        }
    }
}

// MARK: - 飛ぶコイン

private struct TossedCoin: View {
    let key: UUID
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let onLanded: () -> Void

    private struct KeyframeValue {
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        var rotation: Double = 0
        var scale: CGFloat = 1
        var opacity: Double = 1
    }

    @State private var fire = false
    private let duration: Double = 1.8
    private let sway: CGFloat = 24

    private var deltaX: CGFloat { end.x - start.x }
    private var deltaY: CGFloat { end.y - start.y }

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [color.opacity(0.95), color.opacity(0.70)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(
                ZStack {
                    Circle().stroke(.white.opacity(0.28), lineWidth: 1.5).padding(5)
                    Text(verbatim: "¥").font(.title3.bold()).foregroundStyle(.white)
                }
            )
            .shadow(color: color.opacity(0.55), radius: 10, x: 0, y: 4)
            .frame(width: 50, height: 50)
            .keyframeAnimator(initialValue: KeyframeValue(), trigger: fire) { content, value in
                content
                    .offset(x: value.offsetX, y: value.offsetY)
                    .scaleEffect(value.scale)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.offsetX) {
                    LinearKeyframe(0,                    duration: 0.01)
                    CubicKeyframe(deltaX * 0.25 + sway,  duration: duration * 0.25)
                    CubicKeyframe(deltaX * 0.50 - sway,  duration: duration * 0.25)
                    CubicKeyframe(deltaX * 0.75 + sway,  duration: duration * 0.25)
                    CubicKeyframe(deltaX,                duration: duration * 0.25)
                }
                KeyframeTrack(\.offsetY) {
                    LinearKeyframe(0,      duration: 0.01)
                    LinearKeyframe(deltaY, duration: duration * 0.99)
                }
                KeyframeTrack(\.rotation) {
                    LinearKeyframe(0, duration: duration)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1.0,  duration: duration * 0.35)
                    CubicKeyframe(1.12,  duration: duration * 0.30)
                    CubicKeyframe(1.0,   duration: duration * 0.25)
                    LinearKeyframe(0.2,  duration: duration * 0.10)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1.0, duration: duration * 0.90)
                    LinearKeyframe(0.0, duration: duration * 0.10)
                }
            }
            .position(start)
            .allowsHitTesting(false)
            .onAppear {
                fire = true
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                    onLanded()
                }
            }
            .id(key)
    }
}

// MARK: - 時間帯と区分の初期値マトリックス

struct DateOptMatrixView: View {
    @State private var settings = AppSettings.shared

    private let kinds = DateOpt.allCases

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 区分の表示名・アイコン・色を編集する
                NavigationLink {
                    DateOptAppearanceListView()
                } label: {
                    HStack {
                        Text("settings.category.appearance")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 8)

                // 新しい記録の区分推定を切り替えるスイッチ
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("settings.category.estimate", isOn: $settings.estimateDateOpt)
                    if settings.userLevel == .beginner {
                        Text("settings.category.estimate.help")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 8)

                if settings.estimateDateOpt {
                    // 推定分布表は別画面で広く表示する
                    NavigationLink {
                        DateOptEstimateDistributionView()
                    } label: {
                        HStack {
                            Text("settings.category.estimateDistribution")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 10)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("settings.dateCategoryDefaults")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("settings.dateCategoryDefaults.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)

                // ヘッダー行
                HStack(spacing: 1) {
                    Spacer().frame(width: 28)
                    ForEach(kinds, id: \.rawValue) { kind in
                        VStack(spacing: 1) {
                            Image(systemName: kind.icon)
                                .font(.caption)
                                .foregroundStyle(kind.color)
                            Text(kind.isDefined ? kind.displayName : kind.placeholderName)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))

                Divider()

                // 時間行（0〜23時）
                ForEach(0..<24, id: \.self) { hour in
                    HStack(spacing: 1) {
                        Text(String(format: "%d", hour))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                            .padding(.trailing, 2)
                        ForEach(kinds, id: \.rawValue) { kind in
                            let isOn = settings.dateOptHourMap[hour] == kind.rawValue
                            ZStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isOn ? kind.color : Color(.systemFill))
                                if isOn {
                                    Image(systemName: kind.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .onTapGesture {
                                guard !isOn else { return }
                                settings.dateOptHourMap[hour] = kind.rawValue
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        // 区分のアイコン・名称・色を変更したら時間帯マップも再生成する
        .id(settings.dateOptAppearanceRevision)
        .navigationTitle("settings.category")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DateOptAppearanceListView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                ForEach(DateOpt.allCases) { dateOpt in
                    let appearance = appearance(for: dateOpt)
                    NavigationLink {
                        DateOptAppearanceEditView(
                            dateOpt: dateOpt,
                            appearance: appearanceBinding(for: dateOpt)
                        )
                    } label: {
                        HStack(spacing: 12) {
                            // セル左端は番号だけにして、改行を防ぐ
                            Text("\(dateOpt.rawValue + 1)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 24, alignment: .leading)
                            Image(systemName: appearance.isDefined ? appearance.iconName : dateOpt.undefinedIcon)
                                .foregroundStyle(dateOpt.color)
                                .frame(width: 24)
                            Text(appearance.isDefined ? appearance.displayName : String(localized: "settings.category.undefinedPreview"))
                                .foregroundStyle(appearance.isDefined ? Color.primary : Color.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("settings.category.appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearance(for dateOpt: DateOpt) -> DateOptAppearance {
        settings.dateOptAppearances.first { $0.dateOptRawValue == dateOpt.rawValue } ?? dateOpt.defaultAppearance
    }

    private func appearanceBinding(for dateOpt: DateOpt) -> Binding<DateOptAppearance> {
        Binding {
            appearance(for: dateOpt)
        } set: { newValue in
            // 配列全体を差し替えて、@Observable と UserDefaults 保存を確実に発火させる
            var values = settings.dateOptAppearances
            if let index = values.firstIndex(where: { $0.dateOptRawValue == dateOpt.rawValue }) {
                values[index] = newValue
            } else {
                values.append(newValue)
            }
            settings.dateOptAppearances = values
        }
    }
}

private struct DateOptAppearanceEditView: View {
    let dateOpt: DateOpt
    @Binding var appearance: DateOptAppearance

    private let japaneseLimit = 4
    private let englishLimit = 8
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]
    private var isJapaneseLocale: Bool {
        Locale.current.language.languageCode?.identifier == "ja"
    }

    var body: some View {
        VStack(spacing: 8) {
            // 現在の名称・アイコン・色をタイトル直下で軽く確認できるようにする
            previewContent
                .padding(.top, 6)

            Form {
                Section {
                    if isJapaneseLocale {
                        TextField("settings.category.name.ja", text: $appearance.nameJa, prompt: Text(dateOpt.namePlaceholder))
                            .onChange(of: appearance.nameJa) { _, value in
                                // 日本語名は日本語だけを残し、4文字以内に制限する
                                appearance.nameJa = limitedJapanese(value, count: japaneseLimit)
                            }
                    } else {
                        TextField("settings.category.name.en", text: $appearance.nameEn, prompt: Text(dateOpt.namePlaceholder))
                            .textInputAutocapitalization(.words)
                            .onChange(of: appearance.nameEn) { _, value in
                                // 英語名は英数字と空白だけを残し、省略名として8文字までにする
                                appearance.nameEn = limitedEnglish(value, count: englishLimit)
                            }
                    }
                } header: {
                    HStack {
                        Text("settings.category.name")
                        Spacer()
                        Text(isJapaneseLocale ? "settings.category.name.limit.ja" : "settings.category.name.limit.en")
                    }
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(DateOptIconOption.all, id: \.self) { iconName in
                            Button {
                                appearance.iconName = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.title3)
                                    .foregroundStyle(appearance.iconName == iconName ? Color.white : Color.primary)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        Circle()
                                            .fill(appearance.iconName == iconName ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("settings.category.icon")
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(DateOptColorOption.all) { option in
                            Button {
                                appearance.colorKey = option.id
                            } label: {
                                let isSelected = appearance.colorKey == option.id
                                ZStack {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            // 選択中の色は外枠で明確にする
                                            Circle()
                                                .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                                        }
                                    if appearance.colorKey == option.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("settings.category.color")
                }
            }
        }
        .navigationTitle(String(format: NSLocalizedString("settings.category.number", comment: ""), dateOpt.rawValue + 1))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewContent: some View {
        HStack(spacing: 8) {
            Image(systemName: appearance.isDefined ? appearance.iconName : dateOpt.undefinedIcon)
                .font(.title3)
                .foregroundStyle(dateOpt.color)
            if appearance.isDefined {
                Text(appearance.displayName)
            } else {
                HStack(spacing: 6) {
                    Text(dateOpt.placeholderName)
                    Text("settings.category.undefinedPreview")
                }
            }
        }
        .font(.headline)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func limited(_ value: String, count: Int) -> String {
        if value.count <= count {
            return value
        }
        return String(value.prefix(count))
    }

    private func limitedJapanese(_ value: String, count: Int) -> String {
        let japaneseOnly = value.filter { character in
            character.unicodeScalars.allSatisfy { scalar in
                (0x3040...0x30FF).contains(scalar.value)
                    || (0x3400...0x9FFF).contains(scalar.value)
                    || (0xFF00...0xFFEF).contains(scalar.value)
            }
        }
        return limited(String(japaneseOnly), count: count)
    }

    private func limitedEnglish(_ value: String, count: Int) -> String {
        let englishOnly = value.filter { character in
            character.unicodeScalars.allSatisfy { scalar in
                scalar.value == 0x20
                    || (0x30...0x39).contains(scalar.value)
                    || (0x41...0x5A).contains(scalar.value)
                    || (0x61...0x7A).contains(scalar.value)
            }
        }
        return limited(String(englishOnly), count: count)
    }
}

private struct DateOptEstimateDistributionView: View {
    @State private var settings = AppSettings.shared
    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var records: [BodyRecord]

    @ScaledMetric(relativeTo: .caption2) private var distributionCellSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var distributionHourWidth: CGFloat = 28

    var body: some View {
        let referenceDate = Date()
        ScrollView {
            distributionTable(referenceDate: referenceDate)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        // 区分のアイコン・名称・色を変更したら推定分布も再生成する
        .id(settings.dateOptAppearanceRevision)
        .navigationTitle("settings.category.estimateDistribution")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func distributionTable(referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 横軸は曜日、縦軸は時刻。各セルに推定区分アイコンを置く
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    Spacer().frame(width: distributionHourWidth)
                    ForEach(1...7, id: \.self) { weekday in
                        Text(weekdayLabel(weekday))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(0..<24, id: \.self) { hour in
                    HStack(spacing: 1) {
                        Text(String(format: "%d", hour))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: distributionHourWidth, alignment: .trailing)
                            .padding(.trailing, 2)
                        ForEach(1...7, id: \.self) { weekday in
                            let dateOpt = estimatedDateOpt(
                                weekday: weekday,
                                hour: hour,
                                referenceDate: referenceDate
                            )
                            ZStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(dateOpt.color.opacity(0.18))
                                // 分布表は密度を優先し、アイコンで行高が膨らまないようにする
                                Image(systemName: dateOpt.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(dateOpt.color)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: distributionCellSize)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func estimatedDateOpt(weekday: Int, hour: Int, referenceDate: Date) -> DateOpt {
        let target = targetDate(weekday: weekday, hour: hour, referenceDate: referenceDate)
        return DateOptEstimator.estimate(
            from: records,
            targetDate: target,
            hourMap: settings.dateOptHourMap,
            referenceDate: referenceDate
        )
    }

    private func targetDate(weekday: Int, hour: Int, referenceDate: Date) -> Date {
        var calendar = Calendar.current
        calendar.locale = Locale.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        components.second = 0
        // 推定器は曜日と時刻を使うため、同じ週の代表日時を作れば十分
        return calendar.date(from: components) ?? referenceDate
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        guard 1 <= weekday, weekday <= symbols.count else {
            return ""
        }
        return symbols[weekday - 1]
    }
}

// MARK: - グラフ設定

struct GraphSettingsView: View {
    var isModal: Bool = false
    @State private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    private var hiddenSet: Set<Int> { Set(settings.graphHiddenPanels) }

    var body: some View {
        List {
            Section("settings.helperGraphs") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("metric.heightForBMI")
                            .font(.callout)
                        Spacer()
                        NumpadValueText(value: $settings.graphBMITall, min: 100, max: 250, decimals: 0, color: .primary)
                        Text("unit.cm")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    AZDialView(
                        value: $settings.graphBMITall,
                        min: 100,
                        max: 250,
                        step: 1,
                        stepperStep: 5,
                        style: DialStyle.builtin(id: settings.dialStyle) ?? .shape,
                        tuning: settings.dialTuning
                    )
                }
                .padding(.vertical, 4)
                NavigationLink {
                    GoalSettingsView()
                } label: {
                    Text("goal.line")
                }
            }

            Section {
                ForEach(settings.graphDisplayOrder, id: \.self) { raw in
                    if let kind = GraphKind(rawValue: raw) {
                        graphDisplayOrderRow(kind: kind, raw: raw)
                    }
                }
                .onMove { from, to in
                    settings.graphDisplayOrder.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("graph.displayOrder")
            } footer: {
                Text("chart.orderIsReflectedInGraphView")
            }
            .environment(\.editMode, .constant(.active))
        }
        .scrollIndicators(.hidden)
        .navigationTitle("graph.settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func graphDisplayOrderRow(kind: GraphKind, raw: Int) -> some View {
        let hasChildSettings = kind == .bp || kind == .weight
        VStack(alignment: .leading, spacing: hasChildSettings ? 4 : 0) {
            HStack {
                Toggle(isOn: graphPanelVisibleBinding(raw: raw)) {
                    Text(LocalizedStringKey(kind.title))
                }
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
            }

            if kind == .bp {
                childGraphVisibilityRow(
                    isVisible: $settings.graphBpMean,
                    titleKey: "metric.meanBloodPressure"
                )
            }
            if kind == .weight {
                childGraphVisibilityRow(
                    isVisible: $settings.graphWeightMA,
                    titleKey: "metric.weightMovingAverage"
                )
            }
        }
        .padding(.top, hasChildSettings ? 4 : 0)
        .padding(.bottom, hasChildSettings ? 0 : 0)
    }

    private func childGraphVisibilityRow(isVisible: Binding<Bool>, titleKey: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye" : "eye.slash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isVisible.wrappedValue ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(titleKey)
            Text(titleKey)
                .font(.callout)
            Spacer()
        }
        .padding(.leading, 28)
    }

    private func graphPanelVisibleBinding(raw: Int) -> Binding<Bool> {
        Binding(
            get: { !hiddenSet.contains(raw) },
            set: { visible in
                if visible {
                    settings.graphHiddenPanels.removeAll { $0 == raw }
                } else if !settings.graphHiddenPanels.contains(raw) {
                    settings.graphHiddenPanels.append(raw)
                }
            }
        )
    }
}

// MARK: - 項目の表示と順序

struct FieldOrderSettingsView: View {
    @State private var settings = AppSettings.shared

    private var hiddenSet: Set<Int> { Set(settings.hiddenFields) }

    var body: some View {
        List {
            Section {
                BeginnerHelpBanner("help.fieldOrder", storageKey: "helpDismissed.fieldOrder")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(settings.graphPanelOrder, id: \.self) { raw in
                    if let kind = GraphKind(rawValue: raw), kind.isRecordField {
                        Toggle(isOn: Binding(
                            get: { !hiddenSet.contains(raw) },
                            set: { visible in
                                if visible {
                                    settings.hiddenFields.removeAll { $0 == raw }
                                } else {
                                    if !settings.hiddenFields.contains(raw) {
                                        settings.hiddenFields.append(raw)
                                    }
                                }
                            }
                        )) {
                            Text(LocalizedStringKey(kind.title))
                        }
                    }
                }
                .onMove { from, to in
                    settings.graphPanelOrder.move(fromOffsets: from, toOffset: to)
                }
            } footer: {
                Text("settings.orderIsReflectedInRecordInput")
            }
        }
        .scrollIndicators(.hidden)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("settings.fieldOrder")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 統計設定

struct StatSettingsView: View {
    var isModal: Bool = false
    @State private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    private var hiddenSet: Set<Int> { Set(settings.statHiddenSections) }

    var body: some View {
        List {
            Section {
                ForEach(settings.statSectionOrder, id: \.self) { raw in
                    if let section = StatSection(rawValue: raw) {
                        Toggle(isOn: Binding(
                            get: { !hiddenSet.contains(raw) },
                            set: { visible in
                                if visible {
                                    settings.statHiddenSections.removeAll { $0 == raw }
                                } else if !settings.statHiddenSections.contains(raw) {
                                    settings.statHiddenSections.append(raw)
                                }
                            }
                        )) {
                            Text(LocalizedStringKey(section.title))
                        }
                    }
                }
                .onMove { from, to in
                    settings.statSectionOrder.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("statistics.displayOrder")
            } footer: {
                Text("stat.orderIsReflectedInStatisticsView")
            }
        }
        .scrollIndicators(.hidden)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("statistics.settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

}

// MARK: - 目標値設定

struct GoalSettingsView: View {
    @State private var settings = AppSettings.shared

    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var records: [BodyRecord]

    private var latest: BodyRecord? { records.first }

    // 最新値（0 = 未記録）
    private var latestBpHi:    Int? { latest?.nBpHi_mmHg }
    private var latestBpLo:    Int? { latest?.nBpLo_mmHg }
    private var latestBpPp:    Int? {
        guard let hi = latest?.nBpHi_mmHg, let lo = latest?.nBpLo_mmHg,
              hi > 0, lo > 0 else { return nil }
        return hi - lo
    }
    private var latestPulse:   Int? { latest?.nPulse_bpm }
    private var latestWeight:  Int? { latest?.nWeight_10Kg }
    private var latestTemp:    Int? { latest?.nTemp_10c }
    private var latestBodyFat: Int? { latest?.nBodyFat_10p }
    private var latestSkMuscle:Int? { latest?.nSkMuscle_10p }
    private var latestBMI:     Int? {
        guard let w = latest?.nWeight_10Kg, w > 0,
              settings.graphBMITall > 0 else { return nil }
        let hm = Double(settings.graphBMITall) / 100.0
        return Int((Double(w) / 10.0 / (hm * hm) * 10).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("goal.values") {
                    goalDialRow(title: "metric.systolic.long", value: $settings.goalBpHi,      spec: MeasureRange.bpHi,      recordVal: latestBpHi,   unit: "unit.mmHg", stepperStep: 10, color: .red)
                    goalDialRow(title: "metric.diastolic.long", value: $settings.goalBpLo,      spec: MeasureRange.bpLo,      recordVal: latestBpLo,   unit: "unit.mmHg", stepperStep: 5,  color: .blue)
                    goalDialRow(title: "metric.pulsePressure",             value: $settings.goalBpPp,      spec: MeasureRange.bpPp,      recordVal: latestBpPp,   unit: "unit.mmHg", stepperStep: 5,  color: .orange)
                    goalDialRow(title: "metric.heartRate",           value: $settings.goalPulse,     spec: MeasureRange.pulse,     recordVal: latestPulse,  unit: "unit.bpm",  stepperStep: 5,  color: .orange)
                    goalDialRow(title: "metric.weight",             value: $settings.goalWeight,    spec: MeasureRange.weight,    recordVal: latestWeight, unit: "unit.kg",   stepperStep: 10, decimals: 1, color: .indigo)
                    goalDialRow(title: "metric.bmi",              value: $settings.goalBMI,       spec: MeasureRange.bmi,       recordVal: latestBMI,    unit: "",     stepperStep: 5,  decimals: 1, color: .cyan)
                    goalDialRow(title: "metric.bodyTemp",             value: $settings.goalTemp,      spec: MeasureRange.temp,      recordVal: latestTemp,   unit: "unit.celsius",   stepperStep: 1,  decimals: 1, color: .pink)
                    goalDialRow(title: "metric.bodyFat",         value: $settings.goalBodyFat,   spec: MeasureRange.bodyFat,   recordVal: latestBodyFat,unit: "%",    stepperStep: 5,  decimals: 1, color: .purple)
                    goalDialRow(title: "metric.skeletalMuscle",         value: $settings.goalSkMuscle,  spec: MeasureRange.skMuscle,  recordVal: latestSkMuscle,unit: "%",   stepperStep: 5,  decimals: 1, color: .teal)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle("goal.settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func goalDialRow(
        title: LocalizedStringKey,
        value: Binding<Int>,
        spec: MeasureSpec,
        recordVal: Int?,
        unit: String,
        stepperStep: Int,
        decimals: Int = 0,
        color: Color = .primary
    ) -> some View {
        let defaultVal = (recordVal ?? 0) > 0 ? recordVal! : spec.initVal
        let enabled = Binding<Bool>(
            get: { value.wrappedValue > 0 },
            set: { on in value.wrappedValue = on ? defaultVal : 0 }
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                if enabled.wrappedValue {
                    NumpadValueText(value: value, min: spec.min, max: spec.max, decimals: decimals, color: color)
                    Text(LocalizedStringKey(unit))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(color.opacity(0.7))
                } else {
                    Text("placeholder.none")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
                Toggle("", isOn: enabled)
                    .labelsHidden()
            }
            if enabled.wrappedValue {
                AZDialView(
                    value: value,
                    min: spec.min,
                    max: spec.max,
                    step: 1,
                    stepperStep: stepperStep,
                    decimals: decimals,
                    style: DialStyle.builtin(id: AppSettings.shared.dialStyle) ?? .shape,
                    tuning: AppSettings.shared.dialTuning
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HealthKit 設定

struct HealthKitSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var hkService = HealthKitService.shared
    @Environment(\.openURL) private var openURL
    @State private var showGuideAlert = false

    private var directionBinding: Binding<HKSyncDirection> {
        Binding(
            get: { HKSyncDirection(rawValue: settings.hkDirection) ?? .writeOnly },
            set: { settings.hkDirection = $0.rawValue }
        )
    }

    private var importStartDate: Date {
        let now = Date()
        let cal = Calendar.current
        if hkService.lastAutoImportAt == nil {
            return cal.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)
        }
        return cal.date(byAdding: .day, value: -15, to: now) ?? now.addingTimeInterval(-15 * 24 * 3600)
    }

    private var directionHelpKey: String {
        switch directionBinding.wrappedValue {
        case .writeOnly:
            return "health.writeOnlyHelp"
        case .readOnly:
            return "health.readOnlyHelp"
        case .both:
            return "health.bothHelp"
        }
    }

    var body: some View {
        Form {
            Section("health.permissions") {
                HStack {
                    Text("text.status")
                    Spacer()
                    Text(hkService.isAuthorized
                         ? "health.authorized"
                         : "health.unauthorized")
                        .foregroundStyle(hkService.isAuthorized ? Color.secondary : Color.orange)
                    Button("action.changePermission") {
                        if hkService.isAuthorized {
                            showGuideAlert = true
                        } else {
                            Task { await hkService.requestAuthorization() }
                        }
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("health.writableFields")
                        Spacer()
                        Text(hkService.authorizedShareFieldsText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("health.writableFields")
                        Text(hkService.authorizedShareFieldsText)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if settings.userLevel == .beginner {
                    // 読み込み対象は HealthKit のプライバシー制限で個別取得できない
                    Text("health.readableFieldsPrivacyHelp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("health.syncDirection") {
                // HealthKit連携方向はインラインの代わりにラジオPickerで選ぶ
                AZRadioPicker(
                    options: HKSyncDirection.allCases,
                    selection: directionBinding,
                    minOptionWidth: 0,
                    maxOptionWidth: 180,
                    horizontalPadding: 4,
                    optionSpacing: 4,
                    groupPadding: 5,
                    wrapsOptions: true,
                    fillsWidth: true
                ) { direction in
                    Text(LocalizedStringKey(direction.titleKey))
                }

                if settings.userLevel == .beginner {
                    // 選択した連携方向ごとの動作を初心者向けに補足する
                    Text(LocalizedStringKey(directionHelpKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("health.syncDetails") {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("health.importStartDate")
                        Spacer()
                        Text(importStartDate, format: .dateTime.year().month().day())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        resetImportDateButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("health.importStartDate")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(importStartDate, format: .dateTime.year().month().day())
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer()
                            resetImportDateButton
                        }
                    }
                }

                if settings.userLevel == .beginner {
                    // 読み込み範囲の自動短縮と、必要時の再読み込み方法を説明する
                    Text("health.importStartDateHelp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Text("health.thisAppCannotModifyOrDelete")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollIndicators(.hidden)
        .navigationTitle("health.integration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hkService.checkAuthorization() }
        .onChange(of: settings.hkDirection) { _, _ in updateNeedsAutoImport() }
        .alert(
            "health.changePermission",
            isPresented: $showGuideAlert
        ) {
            Button("health.open") {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("health.tapTheIconAtTheTop")
        }
    }

    private func updateNeedsAutoImport() {
        let canImport = settings.hkEnabled &&
            (HKSyncDirection(rawValue: settings.hkDirection)?.canRead == true)
        if canImport { hkService.needsAutoImport = true }
    }

    private var resetImportDateButton: some View {
        Button("health.resetOneYear") {
            hkService.clearLastAutoImportAt()
            updateNeedsAutoImport()
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 68))
                            .foregroundStyle(Color.azuki)
                        Text("app.name")
                            .font(.title.bold())
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(AppConstants.copyright)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical)
            }

            Section("text.support") {
                Link(
                    "app.website",
                    destination: URL(string: "https://azukid.com")!
                )
                Link(
                    "action.reviewAppStore",
                    destination: URL(string: "https://apps.apple.com/app/id\(AppConstants.productName)")!
                )
            }
        }
        .scrollIndicators(.hidden)
        .navigationTitle("app.about")
        .navigationBarTitleDisplayMode(.inline)
    }
}
