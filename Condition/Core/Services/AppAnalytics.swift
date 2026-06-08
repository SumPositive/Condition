//
//  匿名利用分析
//  Firebase AnalyticsとCrashlyticsへ機能利用、設定傾向、非致命エラーを送る
//

import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

@MainActor
final class AppAnalytics {
    static let shared = AppAnalytics()

    private var didConfigure = false
    private var lastSettingsSignature = ""

    private init() {}

    func configure() {
        guard !didConfigure else { return }
        didConfigure = true

        Analytics.setAnalyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        logEvent("app_start")
        updateUserProperties(settings: AppSettings.shared)
        logSettingsSnapshot(settings: AppSettings.shared, reason: "app_start")
    }

    func logScreen(_ name: String) {
        logEvent(
            AnalyticsEventScreenView,
            parameters: [
                AnalyticsParameterScreenName: name,
                AnalyticsParameterScreenClass: name,
            ]
        )
    }

    func logFeature(_ name: String, parameters: [String: Any] = [:]) {
        var merged = parameters
        merged["feature"] = name
        logEvent("feature_use", parameters: merged)
    }

    func logOperation(_ name: String, parameters: [String: Any] = [:]) {
        var merged = parameters
        merged["operation"] = name
        logEvent("operation", parameters: merged)
    }

    func logSettingsSnapshot(settings: AppSettings, reason: String) {
        let snapshot = settingsSnapshot(settings)
        let signature = snapshot
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")

        // 同じ設定スナップショットは連続送信しない
        guard signature != lastSettingsSignature else { return }
        lastSettingsSignature = signature

        var parameters = snapshot
        parameters["reason"] = reason
        logEvent("settings_snapshot", parameters: parameters)
        updateUserProperties(settings: settings)
    }

    func record(error: Error, name: String, parameters: [String: Any] = [:]) {
        var merged = parameters
        merged["error_name"] = name

        // Crashlyticsには自由入力や測定値を入れず、原因調査に必要な分類だけを送る
        Crashlytics.crashlytics().record(error: error, userInfo: sanitizedParameters(merged))
        logEvent("nonfatal_error", parameters: merged)
    }

    func record(message: String, name: String, parameters: [String: Any] = [:]) {
        let error = NSError(
            domain: "Condition.AppAnalytics",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        record(error: error, name: name, parameters: parameters)
    }

    private func logEvent(_ name: String, parameters: [String: Any] = [:]) {
        guard didConfigure || name == "app_start" else { return }
        Analytics.logEvent(name, parameters: sanitizedParameters(parameters))
    }

    private func updateUserProperties(settings: AppSettings) {
        Analytics.setUserProperty("\(settings.userLevel.rawValue)", forName: "user_level")
        Analytics.setUserProperty("\(settings.appearanceMode.rawValue)", forName: "appearance_mode")
        Analytics.setUserProperty("\(settings.fontScale.rawValue)", forName: "font_scale")
        Analytics.setUserProperty(settings.dialStyle, forName: "dial_style")
    }

    private func settingsSnapshot(_ settings: AppSettings) -> [String: Any] {
        [
            "user_level": settings.userLevel.rawValue,
            "appearance_mode": settings.appearanceMode.rawValue,
            "font_scale": settings.fontScale.rawValue,
            "open_new_on_foreground": settings.openNewRecordOnForeground ? 1 : 0,
            "merge_window_minutes": settings.mergeWindowMinutes,
            "merge_default_action": settings.mergeDefaultAction,
            "estimate_category": settings.estimateDateOpt ? 1 : 0,
            "dial_style": settings.dialStyle,
            "hidden_record_fields": settings.hiddenFields.count,
            "hidden_graph_panels": settings.graphHiddenPanels.count,
            "graph_bp_mean": settings.graphBpMean ? 1 : 0,
            "graph_weight_ma": settings.graphWeightMA ? 1 : 0,
            "graph_bp_line_mode": settings.graphBpLineMode,
            "stat_days": settings.statDays,
            "hidden_stat_sections": settings.statHiddenSections.count,
            "unused_categories": settings.dateOptAppearances.filter { !$0.isDefined }.count,
        ]
    }

    private func sanitizedParameters(_ parameters: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in parameters {
            let safeKey = key.safeAnalyticsKey
            switch value {
            case let value as String:
                result[safeKey] = String(value.prefix(80))
            case let value as Int:
                result[safeKey] = value
            case let value as Double:
                result[safeKey] = value
            case let value as Bool:
                result[safeKey] = value ? 1 : 0
            default:
                result[safeKey] = String(describing: value).prefix(80).description
            }
        }

        return result
    }
}

private extension String {
    var safeAnalyticsKey: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        let mapped = String(map { allowed.contains($0) ? $0 : "_" })
        return String(mapped.prefix(40))
    }

    var trimmedForAnalytics: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
