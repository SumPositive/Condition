// AppSettings.swift
// @Observable 設定ストア
// UserDefaults の読み書きを集約

import Foundation
import SwiftUI
import Observation
import AZDial

// ユーザレベル（初心者：ヘルプテキスト表示 / 達人：非表示）
enum AppUserLevel: Int, CaseIterable, Identifiable {
    case beginner = 0
    case expert   = 1

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .beginner: return "settings.userLevel.beginner"
        case .expert:   return "settings.userLevel.expert"
        }
    }
}

// 文字サイズ倍率
enum AppFontScale: Int, CaseIterable, Identifiable {
    case system   = 0   // 自動（システム設定に従う）
    case standard = 1   // 標準（Large 固定）
    case large    = 2   // 大（xxxLarge 相当）
    case xLarge   = 3   // 特大（accessibility2 相当）

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .system:   return "settings.fontScale.system"
        case .standard: return "settings.fontScale.standard"
        case .large:    return "settings.fontScale.large"
        case .xLarge:   return "settings.fontScale.xLarge"
        }
    }

    /// true のときはシステム設定に委ねる（.dynamicTypeSize を上書きしない）
    var followsSystem: Bool { self == .system }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .system:   return .large           // followsSystem=true なので実際には使われない
        case .standard: return .large
        case .large:    return .xxxLarge
        case .xLarge:   return .accessibility2
        }
    }
}

// アプリ全体の外観モード
enum AppAppearanceMode: Int, CaseIterable, Identifiable {
    case automatic = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .automatic: return "appearance.automatic"
        case .light:     return "appearance.light"
        case .dark:      return "appearance.dark"
        }
    }
}

@Observable
@MainActor
final class AppSettings {

    // MARK: - シングルトン
    static let shared = AppSettings()

    private let ud  = UserDefaults.standard

    // MARK: - グラフ設定（グラフ専用表示）
    var graphDisplayOrder: [Int] = [
        GraphKind.bp.rawValue,
        GraphKind.bpAvg.rawValue,
        GraphKind.pulse.rawValue,
        GraphKind.weight.rawValue,
        GraphKind.bmi.rawValue,
        GraphKind.weightChange.rawValue,
        GraphKind.temp.rawValue,
        GraphKind.bodyFat.rawValue,
        GraphKind.skMuscle.rawValue,
    ] {
        didSet { ud.set(graphDisplayOrder, forKey: SettingsKeys.settGraphDisplayOrder) }
    }
    var graphHiddenPanels: [Int] = [
        GraphKind.temp.rawValue,
        GraphKind.bodyFat.rawValue,
        GraphKind.skMuscle.rawValue,
    ] {
        didSet { ud.set(graphHiddenPanels, forKey: SettingsKeys.settGraphHiddenPanels) }
    }

    // MARK: - グラフ設定（記録入力共通）
    var graphPanelOrder: [Int] = [
        GraphKind.bp.rawValue,       // 0
        GraphKind.pulse.rawValue,    // 2
        GraphKind.weight.rawValue,   // 4
        GraphKind.temp.rawValue,     // 3
        GraphKind.bpAvg.rawValue,    // 1
        GraphKind.bodyFat.rawValue,  // 6
        GraphKind.skMuscle.rawValue, // 7
    ] {
        didSet { ud.set(graphPanelOrder, forKey: SettingsKeys.settGraphs) }
    }
    /// 非表示フィールドの GraphKind.rawValue 集合（グラフ・記録入力の両方に適用）
    var hiddenFields: [Int] = [
        GraphKind.temp.rawValue,     // 3
        GraphKind.bodyFat.rawValue,  // 6
        GraphKind.skMuscle.rawValue, // 7
    ] {
        didSet { ud.set(hiddenFields, forKey: SettingsKeys.settFieldHidden) }
    }
    var graphOneWidth: Int = 45 {
        didSet { ud.set(graphOneWidth, forKey: SettingsKeys.settGraphOneWid) }
    }
    var graphBpMean: Bool = true {
        didSet { ud.set(graphBpMean, forKey: SettingsKeys.settGraphBpMean) }
    }
    var graphBpPress: Bool = true {
        didSet { ud.set(graphBpPress, forKey: SettingsKeys.settGraphBpPress) }
    }
    var graphBMITall: Int = 160 {
        didSet { ud.set(graphBMITall, forKey: SettingsKeys.settGraphBMITall) }
    }
    var graphBMI: Bool = true {
        didSet { ud.set(graphBMI, forKey: SettingsKeys.settGraphBMI) }
    }
    var graphWeightMA: Bool = true {
        didSet { ud.set(graphWeightMA, forKey: SettingsKeys.settGraphWeightMA) }
    }
    var graphWeightChange: Bool = true {
        didSet { ud.set(graphWeightChange, forKey: SettingsKeys.settGraphWeightChange) }
    }
    var dialStyle: String = DialStyle.shape.id {
        didSet { ud.set(dialStyle, forKey: SettingsKeys.settDialStyle) }
    }
    var dialTuning: AZDialInteractionTuning = .default {
        didSet { saveDialTuning() }
    }

    // MARK: - 表示設定（端末別）
    var userLevel: AppUserLevel = .beginner {
        didSet { ud.set(userLevel.rawValue, forKey: UDefKeys.userLevel) }
    }
    var appearanceMode: AppAppearanceMode = .automatic {
        didSet { ud.set(appearanceMode.rawValue, forKey: UDefKeys.appearanceMode) }
    }
    var fontScale: AppFontScale = .system {
        didSet { ud.set(fontScale.rawValue, forKey: UDefKeys.fontScale) }
    }

    // MARK: - 統計設定
    var statType: Int = 0 {
        didSet { ud.set(statType, forKey: SettingsKeys.settStatType) }
    }
    var statDays: Int = 7 {
        didSet { ud.set(statDays, forKey: SettingsKeys.settStatDays) }
    }
    var statShowAvg: Bool = true {
        didSet { ud.set(statShowAvg, forKey: SettingsKeys.settStatAvgShow) }
    }
    var statShowTimeLine: Bool = true {
        didSet { ud.set(statShowTimeLine, forKey: SettingsKeys.settStatTimeLine) }
    }
    var statShow24HLine: Bool = false {
        didSet { ud.set(statShow24HLine, forKey: SettingsKeys.settStat24HLine) }
    }
    var statSectionOrder: [Int] = StatSection.allCases.map(\.rawValue) {
        didSet { ud.set(statSectionOrder, forKey: SettingsKeys.settStatSections) }
    }
    var statHiddenSections: [Int] = [] {
        didSet { ud.set(statHiddenSections, forKey: SettingsKeys.settStatHiddenSections) }
    }

    // MARK: - 機能切替
    var goalEnabled: Bool = true {
        didSet { ud.set(goalEnabled, forKey: SettingsKeys.bGoal) }
    }
    // MARK: - DateOpt 自動判定時刻（旧設定、マイグレーション用に保持）
    var wakeHour: Int = 6 {
        didSet { ud.set(wakeHour, forKey: SettingsKeys.dateOptWakeHour) }
    }
    var restHour: Int = 12 {
        didSet { ud.set(restHour, forKey: SettingsKeys.dateOptRestHour) }
    }
    var downHour: Int = 21 {
        didSet { ud.set(downHour, forKey: SettingsKeys.dateOptDownHour) }
    }
    var sleepHour: Int = 23 {
        didSet { ud.set(sleepHour, forKey: SettingsKeys.dateOptSleepHour) }
    }

    // MARK: - DateOpt 時刻マトリックス（24要素、-1=未割当→.restにフォールバック）
    var dateOptHourMap: [Int] = AppSettings.factoryDefaultHourMap {
        didSet { ud.set(dateOptHourMap, forKey: SettingsKeys.settDateOptHourMap) }
    }

    /// 出荷時初期値（画像定義）
    static let factoryDefaultHourMap: [Int] = [
        3, 3, 3,       // 0-2:   就寝時
        0, 0, 0, 0, 0, // 3-7:   起床時
        1, 1, 1,       // 8-10:  安静時
        4, 4, 4,       // 11-13: 運動前
        5, 5, 5,       // 14-16: 運動後
        1, 1, 1,       // 17-19: 安静時
        2, 2,          // 20-21: 就寝前
        3, 3,          // 22-23: 就寝時
    ]

    /// 旧設定（wakeHour/downHour/sleepHour）からのマイグレーション用
    static func makeDefaultHourMap(wake: Int, down: Int, sleep: Int) -> [Int] {
        var map = Array(repeating: -1, count: 24)
        let around = DateOptConstants.aroundHour
        for offset in -around..<around {
            map[(down  + offset + 24) % 24] = DateOpt.down.rawValue
        }
        for offset in -around..<around {
            map[(sleep + offset + 24) % 24] = DateOpt.sleep.rawValue
        }
        for offset in -around..<around {
            map[(wake  + offset + 24) % 24] = DateOpt.wake.rawValue
        }
        return map
    }

    // MARK: - 目標値
    var goalBpHi: Int = 0 {
        didSet { ud.set(goalBpHi, forKey: SettingsKeys.goalBpHi) }
    }
    var goalBpLo: Int = 0 {
        didSet { ud.set(goalBpLo, forKey: SettingsKeys.goalBpLo) }
    }
    var goalPulse: Int = 0 {
        didSet { ud.set(goalPulse, forKey: SettingsKeys.goalPulse) }
    }
    var goalWeight: Int = 0 {
        didSet { ud.set(goalWeight, forKey: SettingsKeys.goalWeight) }
    }
    var goalTemp: Int = 0 {
        didSet { ud.set(goalTemp, forKey: SettingsKeys.goalTemp) }
    }
    var goalBodyFat: Int = 0 {
        didSet { ud.set(goalBodyFat, forKey: SettingsKeys.goalBodyFat) }
    }
    var goalSkMuscle: Int = 0 {
        didSet { ud.set(goalSkMuscle, forKey: SettingsKeys.goalSkMuscle) }
    }
    var goalBpPp: Int = 0 {
        didSet { ud.set(goalBpPp, forKey: SettingsKeys.goalBpPp) }
    }
    var goalBMI: Int = 0 {
        didSet { ud.set(goalBMI, forKey: SettingsKeys.goalBMI) }
    }

    // MARK: - HealthKit（UserDefaults: デバイス個別・@Observable 追跡対象にするため stored property）
    var hkEnabled: Bool = false {
        didSet { ud.set(hkEnabled, forKey: UDefKeys.hkEnabled) }
    }
    var hkDisabledByDemo: Bool = false {
        didSet { ud.set(hkDisabledByDemo, forKey: UDefKeys.hkDisabledByDemo) }
    }
    var hkDirection: Int = HKSyncDirection.both.rawValue {
        didSet { ud.set(hkDirection, forKey: UDefKeys.hkDirection) }
    }

    // MARK: - 起動・フォアグラウンド時の動作
    var openNewRecordOnForeground: Bool = false {
        didSet { ud.set(openNewRecordOnForeground, forKey: UDefKeys.openNewRecordOnForeground) }
    }

    // MARK: - 記録をまとめる（衝突検出設定）
    /// 直前記録との衝突を検出する時間しきい値（分）。0=しない
    var mergeWindowMinutes: Int = 0 {
        didSet { ud.set(mergeWindowMinutes, forKey: UDefKeys.mergeWindowMinutes) }
    }
    /// 衝突解決の初期選択 (ConflictAction.rawValue)
    var mergeDefaultAction: Int = ConflictAction.useAverage.rawValue {
        didSet { ud.set(mergeDefaultAction, forKey: UDefKeys.mergeDefaultAction) }
    }

    // MARK: - 新規記録シート（非永続・セッションのみ）
    /// TabView 上位から新規記録シートを開くトリガー
    var showNewRecordSheet: Bool = false
    /// 新規記録シートに未保存の変更があるか
    var newRecordSheetModified: Bool = false

    // MARK: - 購入状態（制限解除済み）
    let isUnlocked: Bool = true

    // MARK: - 初期化

    private init() {
        // UserDefaults デフォルト値登録（キー未登録時は 0 が返るため明示的に設定）
        ud.register(defaults: [
            UDefKeys.hkDirection:   HKSyncDirection.both.rawValue,
            UDefKeys.appearanceMode: AppAppearanceMode.automatic.rawValue,
            UDefKeys.userLevel:     AppUserLevel.beginner.rawValue,
            UDefKeys.fontScale:     AppFontScale.system.rawValue,
        ])
        migrateFromKVSIfNeeded()
        loadFromUserDefaults()
        // UserDefaults（デバイス個別）読み込み
        hkDisabledByDemo = ud.bool(forKey: UDefKeys.hkDisabledByDemo)
        hkEnabled   = hkDisabledByDemo ? false : ud.bool(forKey: UDefKeys.hkEnabled)
        hkDirection = ud.integer(forKey: UDefKeys.hkDirection)
        appearanceMode = AppAppearanceMode(rawValue: ud.integer(forKey: UDefKeys.appearanceMode)) ?? .automatic
        userLevel  = AppUserLevel(rawValue:  ud.integer(forKey: UDefKeys.userLevel))  ?? .beginner
        fontScale  = AppFontScale(rawValue:  ud.integer(forKey: UDefKeys.fontScale))  ?? .system
        if ud.object(forKey: UDefKeys.openNewRecordOnForeground) != nil {
            openNewRecordOnForeground = ud.bool(forKey: UDefKeys.openNewRecordOnForeground)
        }
        if ud.object(forKey: UDefKeys.mergeWindowMinutes) != nil {
            mergeWindowMinutes = ud.integer(forKey: UDefKeys.mergeWindowMinutes)
        }
        if ud.object(forKey: UDefKeys.mergeDefaultAction) != nil {
            mergeDefaultAction = ud.integer(forKey: UDefKeys.mergeDefaultAction)
        }
    }

    // MARK: - 旧KVS設定の移行

    private func migrateFromKVSIfNeeded() {
        guard ud.bool(forKey: UDefKeys.settingsMigratedFromKVS) == false else { return }

        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        for key in SettingsKeys.migratableKeys where ud.object(forKey: key) == nil {
            guard let value = kvs.object(forKey: key) else { continue }
            ud.set(value, forKey: key)
        }
        ud.set(true, forKey: UDefKeys.settingsMigratedFromKVS)
    }

    // MARK: - UserDefaults ロード

    func loadFromUserDefaults() {
        if let arr = ud.array(forKey: SettingsKeys.settGraphDisplayOrder) as? [Int], !arr.isEmpty {
            graphDisplayOrder = arr
        }
        if let arr = ud.array(forKey: SettingsKeys.settGraphHiddenPanels) as? [Int] {
            graphHiddenPanels = arr
        }
        // 新しい GraphKind が追加された場合、既存ユーザーの順序末尾に補完
        for raw in GraphKind.allCases.map(\.rawValue) where !graphDisplayOrder.contains(raw) {
            graphDisplayOrder.append(raw)
        }
        if let arr = ud.array(forKey: SettingsKeys.settGraphs) as? [Int], !arr.isEmpty {
            graphPanelOrder = arr
        }
        // 記録入力フィールドが graphPanelOrder に不足している場合は末尾に補完
        for kind in GraphKind.allCases where kind.isRecordField && !graphPanelOrder.contains(kind.rawValue) {
            graphPanelOrder.append(kind.rawValue)
        }
        if let arr = ud.array(forKey: SettingsKeys.settFieldHidden) as? [Int] {
            hiddenFields = arr
        }
        let ow = ud.integer(forKey: SettingsKeys.settGraphOneWid)
        if 0 < ow { graphOneWidth = ow }

        if ud.object(forKey: SettingsKeys.settGraphBpMean)    != nil { graphBpMean    = ud.bool(forKey: SettingsKeys.settGraphBpMean) }
        if ud.object(forKey: SettingsKeys.settGraphBpPress)   != nil { graphBpPress   = ud.bool(forKey: SettingsKeys.settGraphBpPress) }
        if ud.object(forKey: SettingsKeys.settGraphBMI)       != nil { graphBMI       = ud.bool(forKey: SettingsKeys.settGraphBMI) }
        let tall = ud.integer(forKey: SettingsKeys.settGraphBMITall)
        if 0 < tall { graphBMITall = tall }
        if ud.object(forKey: SettingsKeys.settGraphWeightMA)     != nil { graphWeightMA     = ud.bool(forKey: SettingsKeys.settGraphWeightMA) }
        if ud.object(forKey: SettingsKeys.settGraphWeightChange) != nil { graphWeightChange = ud.bool(forKey: SettingsKeys.settGraphWeightChange) }
        // dialStyle: 強制デフォルト移行バージョン
        let dialStyleForceVersion = 1  // Shape をデフォルトにした版
        let forcedVersion = ud.integer(forKey: SettingsKeys.settDialStyleForcedVersion)

        if ud.object(forKey: SettingsKeys.settDialStyle) != nil {
            if let str = ud.string(forKey: SettingsKeys.settDialStyle), DialStyle.builtin(id: str) != nil {
                // 新形式（String）
                dialStyle = str
            } else {
                // 旧形式（Int）→ 新形式へ移行
                let oldInt = ud.integer(forKey: SettingsKeys.settDialStyle)
                let migrated: String
                switch oldInt {
                case 2:  migrated = DialStyle.chrome.id
                case 4:  migrated = DialStyle.hairline.id
                case 5:  migrated = DialStyle.rubber.id
                default: migrated = DialStyle.varnia.id
                }
                dialStyle = migrated
                ud.set(migrated, forKey: SettingsKeys.settDialStyle)
            }
        }
        // アップデートで強制的にデフォルトへ上書き
        if forcedVersion < dialStyleForceVersion {
            dialStyle = DialStyle.shape.id
            ud.set(dialStyle, forKey: SettingsKeys.settDialStyle)
            ud.set(dialStyleForceVersion, forKey: SettingsKeys.settDialStyleForcedVersion)
        }
        loadDialTuning()

        let sd = ud.integer(forKey: SettingsKeys.settStatDays)
        if 0 < sd { statDays = sd }
        if ud.object(forKey: SettingsKeys.settStatType)     != nil { statType         = ud.integer(forKey: SettingsKeys.settStatType) }
        if ud.object(forKey: SettingsKeys.settStatAvgShow)  != nil { statShowAvg      = ud.bool(forKey: SettingsKeys.settStatAvgShow) }
        if ud.object(forKey: SettingsKeys.settStatTimeLine) != nil { statShowTimeLine = ud.bool(forKey: SettingsKeys.settStatTimeLine) }
        if ud.object(forKey: SettingsKeys.settStat24HLine)  != nil { statShow24HLine  = ud.bool(forKey: SettingsKeys.settStat24HLine) }
        if let arr = ud.array(forKey: SettingsKeys.settStatSections) as? [Int], !arr.isEmpty {
            // 保存済み配列に含まれていない新セクションを末尾に追加する（バージョンアップ対応）
            let known = Set(arr)
            let appended = arr + StatSection.allCases.map(\.rawValue).filter { !known.contains($0) }
            statSectionOrder = appended
        }
        if let arr = ud.array(forKey: SettingsKeys.settStatHiddenSections) as? [Int] {
            statHiddenSections = arr
        }

        if ud.object(forKey: SettingsKeys.bGoal) != nil { goalEnabled = ud.bool(forKey: SettingsKeys.bGoal) }

        let wh = ud.integer(forKey: SettingsKeys.dateOptWakeHour)
        if 0 < wh { wakeHour = wh }
        let rh = ud.integer(forKey: SettingsKeys.dateOptRestHour)
        if 0 < rh { restHour = rh }
        let dh = ud.integer(forKey: SettingsKeys.dateOptDownHour)
        if 0 < dh { downHour = dh }
        let sh = ud.integer(forKey: SettingsKeys.dateOptSleepHour)
        if 0 < sh { sleepHour = sh }
        // 時刻マトリックス（保存済みを優先、旧設定があればマイグレーション、なければ出荷時初期値）
        if let arr = ud.array(forKey: SettingsKeys.settDateOptHourMap) as? [Int], arr.count == 24 {
            dateOptHourMap = arr
        } else if 0 < wh || 0 < dh || 0 < sh {
            dateOptHourMap = AppSettings.makeDefaultHourMap(wake: wakeHour, down: downHour, sleep: sleepHour)
        } else {
            dateOptHourMap = AppSettings.factoryDefaultHourMap
        }

        let gbh = ud.integer(forKey: SettingsKeys.goalBpHi)
        if 0 < gbh { goalBpHi = gbh }
        let gbl = ud.integer(forKey: SettingsKeys.goalBpLo)
        if 0 < gbl { goalBpLo = gbl }
        let gp = ud.integer(forKey: SettingsKeys.goalPulse)
        if 0 < gp { goalPulse = gp }
        let gw = ud.integer(forKey: SettingsKeys.goalWeight)
        if 0 < gw { goalWeight = gw }
        let gt = ud.integer(forKey: SettingsKeys.goalTemp)
        if 0 < gt { goalTemp = gt }
        let gbf = ud.integer(forKey: SettingsKeys.goalBodyFat)
        if 0 < gbf { goalBodyFat = gbf }
        let gsk = ud.integer(forKey: SettingsKeys.goalSkMuscle)
        if 0 < gsk { goalSkMuscle = gsk }
        let gpp = ud.integer(forKey: SettingsKeys.goalBpPp)
        if 0 < gpp { goalBpPp = gpp }
        let gbmi = ud.integer(forKey: SettingsKeys.goalBMI)
        if 0 < gbmi { goalBMI = gbmi }

    }

    private func loadDialTuning() {
        // 保存済みの操作感度がなければ標準値を使う
        guard let data = ud.data(forKey: SettingsKeys.settDialTuning),
              let tuning = try? JSONDecoder().decode(AZDialInteractionTuning.self, from: data) else {
            dialTuning = .default
            return
        }
        dialTuning = tuning
    }

    private func saveDialTuning() {
        // UserDefaultsに入れられるようJSONデータへ変換する
        guard let data = try? JSONEncoder().encode(dialTuning) else { return }
        ud.set(data, forKey: SettingsKeys.settDialTuning)
    }

    // MARK: - DateOpt 自動判定
    func autoDateOpt(for date: Date) -> DateOpt {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        return DateOpt(rawValue: dateOptHourMap[hour]) ?? .rest
    }
}
