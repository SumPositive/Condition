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

enum GraphBpLineMode: Int, CaseIterable, Identifiable {
    case average = 0
    case category = 1

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .average: return "graph.bpLineMode.average"
        case .category: return "graph.bpLineMode.category"
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

// 起動（フォアグラウンド復帰）時に自動で開く画面
enum LaunchAction: Int, CaseIterable, Identifiable {
    case none       = 0   // 何もしない
    case newMulti   = 1   // 新しい記録（複数回測定の平均）
    case newSingle  = 2   // 新しい記録（単発）
    case records    = 5   // 記録（一覧）
    case graph      = 3   // 旧グラフ。rawValueを保ったまま分析ページ1へ移行
    case statistics = 4   // 旧統計。rawValueを保ったまま分析ページ2へ移行
    case analysis3  = 6   // 分析ページ3

    var id: Int { rawValue }

    // rawValue は永続化互換のため飛び番だが、UIでは記録の後に分析ページ1〜3を並べる
    static var allCases: [LaunchAction] {
        [.none, .newMulti, .newSingle, .records, .graph, .statistics, .analysis3]
    }

    var titleKey: String {
        switch self {
        case .none:       return "settings.launchAction.none"
        case .newMulti:   return "settings.launchAction.newMulti"
        case .newSingle:  return "settings.launchAction.newSingle"
        case .records:    return "settings.launchAction.records"
        case .graph:      return "settings.launchAction.analysis1"
        case .statistics: return "settings.launchAction.analysis2"
        case .analysis3:  return "settings.launchAction.analysis3"
        }
    }

    /// 起動時に開く分析ページを返す
    var analysisPage: AnalysisPage? {
        switch self {
        case .graph: return .one
        case .statistics: return .two
        case .analysis3: return .three
        case .none, .newSingle, .newMulti, .records: return nil
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
    /// グラフ種別ごとの追加高さ（ユーザーがハンドル操作でリサイズした分）
    var graphHeightOverrides: [Int: Double] = [:] {
        didSet { saveGraphHeightOverrides() }
    }
    /// 統計図セクションごとの追加高さ
    var statHeightOverrides: [Int: Double] = [:] {
        didSet { saveStatHeightOverrides() }
    }
    /// 3つの分析ページに属する図表、順位、表示状態、期間、ページ名
    var analysisLayout = AnalysisLayout.migrated(
        graphOrder: GraphKind.allCases.map(\.rawValue),
        hiddenGraphs: [],
        statOrder: StatSection.allCases.map(\.rawValue),
        hiddenStats: [],
        statDays: GraphPeriod.threeMonths.rawValue
    ) {
        didSet { saveAnalysisLayout() }
    }
    /// 各症状パネルで最後に選んだ症状ID
    var analysisSymptomFilters: [String: String] = [:] {
        didSet { ud.set(analysisSymptomFilters, forKey: SettingsKeys.settAnalysisSymptomFilters) }
    }
    /// 全症状パネルで選択中の症状を共有する
    var analysisSymptomSelectionSync: Bool = true {
        didSet {
            ud.set(
                analysisSymptomSelectionSync,
                forKey: SettingsKeys.settAnalysisSymptomSelectionSync
            )
        }
    }

    private static let synchronizedAnalysisSymptomFilterKey = "_synchronized"

    /// 同期中は共通値、同期していない場合はパネルごとの症状絞り込みを返す
    func analysisSymptomFilter(for panel: AnalysisPanelID, in page: AnalysisPage) -> String {
        if analysisSymptomSelectionSync {
            return synchronizedAnalysisSymptomFilter
        }
        return analysisSymptomFilters[panel.rawValue]
            ?? analysisSymptomFilters[String(page.rawValue)]
            ?? ""
    }

    /// 同期設定に応じて共通またはパネル個別の症状選択を保存する
    func setAnalysisSymptomFilter(_ symptomID: String, for panel: AnalysisPanelID) {
        let key = analysisSymptomSelectionSync
            ? Self.synchronizedAnalysisSymptomFilterKey
            : panel.rawValue
        analysisSymptomFilters[key] = symptomID
    }

    /// 同期を切り替えても画面上の選択が急に変わらないよう現在値を引き継ぐ
    func setAnalysisSymptomSelectionSync(_ isOn: Bool) {
        guard analysisSymptomSelectionSync != isOn else { return }
        var filters = analysisSymptomFilters
        if isOn {
            let selected = analysisSymptomFilter(for: .symptomOverview, in: .three)
            filters[Self.synchronizedAnalysisSymptomFilterKey] = selected
        } else {
            let selected = synchronizedAnalysisSymptomFilter
            for panel in AnalysisPanelID.allCases where panel.isSymptomPanel {
                filters[panel.rawValue] = selected
            }
        }
        analysisSymptomFilters = filters
        analysisSymptomSelectionSync = isOn
    }

    /// 保存済みの個別選択がある場合は同期の初期値として引き継ぐ
    private var synchronizedAnalysisSymptomFilter: String {
        if let selected = analysisSymptomFilters[Self.synchronizedAnalysisSymptomFilterKey] {
            return selected
        }
        for panel in AnalysisPanelID.allCases where panel.isSymptomPanel {
            if let selected = analysisSymptomFilters[panel.rawValue] { return selected }
        }
        for page in AnalysisPage.allCases {
            if let selected = analysisSymptomFilters[String(page.rawValue)] { return selected }
        }
        return ""
    }

    private func saveGraphHeightOverrides() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: graphHeightOverrides.map { (String($0.key), $0.value) })
        if let data = try? JSONSerialization.data(withJSONObject: stringKeyed) {
            ud.set(data, forKey: SettingsKeys.settGraphHeightOverrides)
        }
    }

    private func loadGraphHeightOverrides() {
        guard let data = ud.data(forKey: SettingsKeys.settGraphHeightOverrides),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else { return }
        var result: [Int: Double] = [:]
        for (k, v) in obj {
            if let key = Int(k) { result[key] = v }
        }
        graphHeightOverrides = result
    }

    private func saveStatHeightOverrides() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: statHeightOverrides.map { (String($0.key), $0.value) })
        if let data = try? JSONSerialization.data(withJSONObject: stringKeyed) {
            ud.set(data, forKey: SettingsKeys.settStatHeightOverrides)
        }
    }

    private func loadStatHeightOverrides() {
        guard let data = ud.data(forKey: SettingsKeys.settStatHeightOverrides),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else { return }
        var result: [Int: Double] = [:]
        for (k, v) in obj {
            if let key = Int(k) { result[key] = v }
        }
        statHeightOverrides = result
    }

    private func saveAnalysisLayout() {
        guard let data = try? JSONEncoder().encode(analysisLayout) else { return }
        ud.set(data, forKey: SettingsKeys.settAnalysisLayout)
    }

    private func loadAnalysisLayout() {
        if let data = ud.data(forKey: SettingsKeys.settAnalysisLayout),
           var saved = try? JSONDecoder().decode(AnalysisLayout.self, from: data) {
            saved.normalize()
            analysisLayout = saved
            return
        }
        // 旧グラフ・統計の順序と非表示を、そのまま分析ページ1・2へ移す
        analysisLayout = AnalysisLayout.migrated(
            graphOrder: graphDisplayOrder,
            hiddenGraphs: graphHiddenPanels,
            statOrder: statSectionOrder,
            hiddenStats: statHiddenSections,
            statDays: statDays
        )
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
    var graphBpLineMode: Int = GraphBpLineMode.average.rawValue {
        didSet { ud.set(graphBpLineMode, forKey: SettingsKeys.settGraphBpLineMode) }
    }
    var graphBpHiddenDateOpts: [Int] = [] {
        didSet { ud.set(graphBpHiddenDateOpts, forKey: SettingsKeys.settGraphBpHiddenDateOpts) }
    }
    var dialStyle: String = DialStyle.shape.id {
        didSet { ud.set(dialStyle, forKey: SettingsKeys.settDialStyle) }
    }
    var dialTuning: AZDialInteractionTuning = AZDialInteractionTuningPreset.mild.tuning {
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
    var statBpDistributionHiddenDateOpts: [Int] = [] {
        didSet { ud.set(statBpDistributionHiddenDateOpts, forKey: SettingsKeys.settStatBpDistributionHiddenDateOpts) }
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
    var dateOptAppearanceRevision: Int = 0
    var dateOptAppearances: [DateOptAppearance] = DateOpt.allCases.map(\.defaultAppearance) {
        didSet {
            // 全区分が未使用になると新規記録画面の候補が空になるため、最低1区分は定義済みに保つ。
            // 全未使用なら、直前まで定義済みだった区分（無ければ cat01）を工場出荷時の既定へ戻す。
            // UI編集・JSON取込・起動時ロードの全経路がこの setter を通る。
            let repaired = Self.ensuringAtLeastOneDefined(dateOptAppearances, previouslyDefined: oldValue)
            if repaired != dateOptAppearances {
                dateOptAppearances = repaired   // 再度 didSet が走るが、修復済みなので無限ループしない
                return
            }
            DateOptAppearanceStore.save(dateOptAppearances)
            // 区分の表示設定だけを参照する画面にも再描画を伝える
            dateOptAppearanceRevision += 1
        }
    }

    /// 全区分が未使用（名称なし）なら、直前まで定義済みだった区分（無ければ cat01）を
    /// 工場出荷時の既定へ戻し、必ず1区分を定義済みにする。
    /// setter の不変条件を担う純粋ロジック（単体テスト対象）。
    static func ensuringAtLeastOneDefined(
        _ appearances: [DateOptAppearance],
        previouslyDefined: [DateOptAppearance]
    ) -> [DateOptAppearance] {
        guard !appearances.contains(where: { $0.isDefined }) else { return appearances }
        // 直前に定義済みだった区分を優先して戻す（利用者が最後に消した区分を復帰させる）
        let targetRaw = previouslyDefined.first(where: { $0.isDefined })?.dateOptRawValue
            ?? DateOpt.cat01.rawValue
        let opt = DateOpt(rawValue: targetRaw) ?? .cat01
        var repaired = appearances
        if let idx = repaired.firstIndex(where: { $0.dateOptRawValue == opt.rawValue }) {
            repaired[idx] = opt.defaultAppearance
        } else {
            repaired.append(opt.defaultAppearance)
        }
        return repaired
    }

    /// 区分の表示順序（rawValue の並び）。内部 index（DateOpt.rawValue）とは独立して管理する。
    /// 並べ替え UI から更新し、各画面はこの順序で区分を表示する。
    var dateOptDisplayOrder: [Int] = DateOpt.allCases.map(\.rawValue) {
        didSet {
            ud.set(dateOptDisplayOrder, forKey: SettingsKeys.settDateOptDisplayOrder)
            dateOptAppearanceRevision += 1
        }
    }

    /// 表示順に並べた全区分（保存順 → 欠落分を末尾に補完）
    var orderedDateOpts: [DateOpt] {
        let ordered = dateOptDisplayOrder.compactMap { DateOpt(rawValue: $0) }
        let missing = DateOpt.allCases.filter { !ordered.contains($0) }
        return ordered + missing
    }

    /// 表示順に並べた、定義済み（名称設定済み）区分のみ
    var orderedDefinedDateOpts: [DateOpt] {
        orderedDateOpts.filter(\.isDefined)
    }

    /// 出荷時初期値（画像定義）
    /// 家庭血圧の基本（朝の起床後・夜の就寝前）に合わせ、それ以外の時間は安静時にする。
    /// 体調不良時・運動前は時刻で決まらないので割り当てない
    static let factoryDefaultHourMap: [Int] = [
        2, 2, 2,       // 0-2:   就寝前（夜更かしの就寝前）
        0, 0, 0, 0, 0, // 3-7:   起床時
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 8-19: 安静時
        2, 2, 2, 2,    // 20-23: 就寝前
    ]

    /// 2.8.x までの出荷時初期値（就寝時・運動前・運動後を含む）。
    /// 既存の利用者で割り当てを保存していない人は、これで固定する
    static let legacyFactoryDefaultHourMap: [Int] = [
        3, 3, 3,       // 0-2:   就寝時
        0, 0, 0, 0, 0, // 3-7:   起床時
        1, 1, 1,       // 8-10:  安静時
        4, 4, 4,       // 11-13: 運動前
        5, 5, 5,       // 14-16: 運動後
        1, 1, 1,       // 17-19: 安静時
        2, 2,          // 20-21: 就寝前
        3, 3,          // 22-23: 就寝時
    ]

    /// 起動時の読み込み前に、区分の名称・時刻の割り当てが保存済みだったか。
    /// 読み込みは既定値も保存するので、読み込み後の UserDefaults では判定できない
    @ObservationIgnored private var hadSavedDateOptAppearances = true
    @ObservationIgnored private var hadSavedDateOptHourMap = true

    /// 区分の既定を見直した版（2.9.0）への切り替えを済ませたか
    private static let dateOptDefaultsVersionKey = "UDEF_DateOptDefaultsVersion"
    private static let dateOptDefaultsVersion = 2

    /// 区分の既定（名称・アイコン・色・時刻の割り当て）の見直しを、既存の利用者には適用しない。
    ///
    /// 起動時の読み込みは区分の名称・時刻の割り当てを保存するので、2.5.0 以降を一度でも起動した人は
    /// 旧既定がすでに保存されていて、ここで何もしなくても区分名は変わらない。
    /// それより前の版から直接更新した人は保存が無く、既定をその場で使っていたので、
    /// 既定だけ変えると過去の「就寝時」「運動後」の記録の区分名まで変わってしまう。
    /// 記録がある（＝既存の利用者）なら旧既定を保存して固定する。記録の無い新規インストールは新しい既定のまま。
    /// 一度だけ判定する（新規の人が後で記録を付けても旧既定には戻さない）
    func freezeLegacyDateOptDefaultsIfNeeded(hasRecords: Bool) {
        guard ud.integer(forKey: Self.dateOptDefaultsVersionKey) < Self.dateOptDefaultsVersion else { return }
        defer { ud.set(Self.dateOptDefaultsVersion, forKey: Self.dateOptDefaultsVersionKey) }
        guard hasRecords else { return }
        if !hadSavedDateOptAppearances {
            dateOptAppearances = DateOpt.allCases.map(\.legacyDefaultAppearance)
        }
        // 旧設定（起床・就寝の時刻）から作った割り当てはそのまま使い、新しい出荷時初期値のときだけ戻す
        if !hadSavedDateOptHourMap, dateOptHourMap == Self.factoryDefaultHourMap {
            dateOptHourMap = Self.legacyFactoryDefaultHourMap
        }
    }

    /// 旧設定（wakeHour/downHour/sleepHour）からのマイグレーション用
    static func makeDefaultHourMap(wake: Int, down: Int, sleep: Int) -> [Int] {
        var map = Array(repeating: -1, count: 24)
        let around = DateOptConstants.aroundHour
        for offset in -around..<around {
            map[(down  + offset + 24) % 24] = DateOpt.cat03.rawValue
        }
        for offset in -around..<around {
            map[(sleep + offset + 24) % 24] = DateOpt.cat04.rawValue
        }
        for offset in -around..<around {
            map[(wake  + offset + 24) % 24] = DateOpt.cat01.rawValue
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
    /// 起動（フォアグラウンド復帰）時に自動で開く画面
    var launchAction: LaunchAction = .none {
        didSet { ud.set(launchAction.rawValue, forKey: UDefKeys.launchAction) }
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

    // MARK: - 区分の推定
    /// 蓄積した記録（曜日・時刻）から区分を推定して初期表示する。OFF時は時間帯マップを使用
    var estimateDateOpt: Bool = true {
        didSet { ud.set(estimateDateOpt, forKey: UDefKeys.estimateDateOpt) }
    }

    // MARK: - ダイアル式の測定記録
    /// 初期からあるダイアル式の記録画面を使うか。既定 OFF で、記録は複数平均式と症状の2つに絞る。
    /// OFF のときは一覧のボタンだけでなく、記録タブ再タップと起動時アクションの経路も塞ぐ
    var useDialRecordEntry: Bool = false {
        didSet { ud.set(useDialRecordEntry, forKey: UDefKeys.useDialRecordEntry) }
    }

    // MARK: - 症状メモ
    /// 記録一覧の絞り込み（すべて／測定／症状）
    var recordDomain: RecordDomain = .all {
        didSet { ud.set(recordDomain.rawValue, forKey: SettingsKeys.settRecordDomain) }
    }
    /// 症状タグリスト。変更したら保存し、一覧・記録画面へ再描画を伝える
    var symptomTagRevision: Int = 0
    var symptomTags: SymptomTagList = SymptomTagStore.symptomTags() {
        didSet {
            SymptomTagStore.saveSymptomTags(symptomTags)
            symptomTagRevision += 1
        }
    }
    var medicineTags: SymptomTagList = SymptomTagStore.medicineTags() {
        didSet {
            SymptomTagStore.saveMedicineTags(medicineTags)
            symptomTagRevision += 1
        }
    }

    var triggerTags: SymptomTagList = SymptomTagStore.triggerTags() {
        didSet {
            SymptomTagStore.saveTriggerTags(triggerTags)
            symptomTagRevision += 1
        }
    }

    /// 症状の使用を記録して並び順（MRU）を更新する
    func markSymptomUsed(_ id: String) {
        guard !id.isEmpty else { return }
        var list = symptomTags
        list.markUsed(id: id)
        symptomTags = list
    }

    /// 薬の使用を記録して並び順（MRU）を更新する
    func markMedicinesUsed(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var list = medicineTags
        for id in ids { list.markUsed(id: id) }
        medicineTags = list
    }

    /// 直前の状況の使用を記録して並び順（MRU）を更新する
    func markTriggersUsed(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var list = triggerTags
        for id in ids { list.markUsed(id: id) }
        triggerTags = list
    }

    // MARK: - 新規記録シート（非永続・セッションのみ）
    /// TabView 上位からダイアル式シートを開くトリガー
    var showNewRecordSheet: Bool = false
    /// 新規記録シートに未保存の変更があるか
    var newRecordSheetModified: Bool = false
    /// TabView 上位から測定シートを開くトリガー
    var showMeasurementAvgSheet: Bool = false
    /// TabView 上位から症状記録シートを開くトリガー
    var showSymptomSheet: Bool = false
    /// 症状記録シートに未保存の変更があるか
    var symptomSheetModified: Bool = false
    /// 起動時アクションでのタブ切替要求（ContentView が消費）
    var pendingLaunchTab: Int? = nil

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
            UDefKeys.estimateDateOpt: true,
        ])
        migrateFromKVSIfNeeded()
        // 読み込みで既定値が保存されてしまう前に、区分を保存済みだったかを控える
        // （freezeLegacyDateOptDefaultsIfNeeded の判定に使う）
        hadSavedDateOptAppearances = ud.data(forKey: SettingsKeys.settDateOptAppearances) != nil
        hadSavedDateOptHourMap = ud.object(forKey: SettingsKeys.settDateOptHourMap) != nil
        loadFromUserDefaults()
        // UserDefaults（デバイス個別）読み込み
        hkDisabledByDemo = ud.bool(forKey: UDefKeys.hkDisabledByDemo)
        hkEnabled   = hkDisabledByDemo ? false : ud.bool(forKey: UDefKeys.hkEnabled)
        hkDirection = ud.integer(forKey: UDefKeys.hkDirection)
        appearanceMode = AppAppearanceMode(rawValue: ud.integer(forKey: UDefKeys.appearanceMode)) ?? .automatic
        userLevel  = AppUserLevel(rawValue:  ud.integer(forKey: UDefKeys.userLevel))  ?? .beginner
        fontScale  = AppFontScale(rawValue:  ud.integer(forKey: UDefKeys.fontScale))  ?? .system
        if ud.object(forKey: UDefKeys.launchAction) != nil {
            launchAction = LaunchAction(rawValue: ud.integer(forKey: UDefKeys.launchAction)) ?? .none
        } else if ud.object(forKey: UDefKeys.openNewRecordOnForeground) != nil {
            // 旧Bool設定から移行：ONだった人は「新しい記録（単発）」、OFFは「何もしない」
            launchAction = ud.bool(forKey: UDefKeys.openNewRecordOnForeground) ? .newSingle : .none
            ud.set(launchAction.rawValue, forKey: UDefKeys.launchAction)
        }
        if ud.object(forKey: UDefKeys.mergeWindowMinutes) != nil {
            mergeWindowMinutes = ud.integer(forKey: UDefKeys.mergeWindowMinutes)
        }
        if ud.object(forKey: UDefKeys.mergeDefaultAction) != nil {
            mergeDefaultAction = ud.integer(forKey: UDefKeys.mergeDefaultAction)
        }
        if ud.object(forKey: UDefKeys.estimateDateOpt) != nil {
            estimateDateOpt = ud.bool(forKey: UDefKeys.estimateDateOpt)
        }
        useDialRecordEntry = ud.bool(forKey: UDefKeys.useDialRecordEntry)
        if let domain = RecordDomain(rawValue: ud.integer(forKey: SettingsKeys.settRecordDomain)) {
            recordDomain = domain
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
        if ud.object(forKey: SettingsKeys.settGraphBpLineMode)   != nil { graphBpLineMode   = ud.integer(forKey: SettingsKeys.settGraphBpLineMode) }
        if let arr = ud.array(forKey: SettingsKeys.settGraphBpHiddenDateOpts) as? [Int] {
            // グラフの区分チェックは統計とは独立して保持する
            graphBpHiddenDateOpts = arr
        }
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
        loadGraphHeightOverrides()
        loadStatHeightOverrides()

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
        if let arr = ud.array(forKey: SettingsKeys.settStatBpDistributionHiddenDateOpts) as? [Int] {
            statBpDistributionHiddenDateOpts = arr
        }
        loadAnalysisLayout()
        if let filters = ud.dictionary(forKey: SettingsKeys.settAnalysisSymptomFilters)
            as? [String: String]
        {
            // パネルごとの選択と旧ページ設定を次回起動時にも引き継ぐ
            analysisSymptomFilters = filters
        }
        if ud.object(forKey: SettingsKeys.settAnalysisSymptomSelectionSync) != nil {
            analysisSymptomSelectionSync = ud.bool(
                forKey: SettingsKeys.settAnalysisSymptomSelectionSync
            )
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
        dateOptAppearances = DateOptAppearanceStore.appearances()
        // 区分の表示順序（保存済みを優先。欠落・新規区分は orderedDateOpts 側で末尾補完）
        if let arr = ud.array(forKey: SettingsKeys.settDateOptDisplayOrder) as? [Int], !arr.isEmpty {
            dateOptDisplayOrder = arr
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
        let mildMigrationVersion = 1
        let migratedVersion = ud.integer(forKey: SettingsKeys.settDialTuningMildMigrationVersion)
        guard let data = ud.data(forKey: SettingsKeys.settDialTuning),
              let tuning = try? JSONDecoder().decode(AZDialInteractionTuning.self, from: data) else {
            // 新規インストールでは操作感度の初期値を控えめにする
            dialTuning = AZDialInteractionTuningPreset.mild.tuning
            ud.set(mildMigrationVersion, forKey: SettingsKeys.settDialTuningMildMigrationVersion)
            return
        }
        if migratedVersion < mildMigrationVersion {
            // 既存ユーザーが標準のままなら一度だけ控えめへ移行する
            ud.set(mildMigrationVersion, forKey: SettingsKeys.settDialTuningMildMigrationVersion)
            if tuning == .default {
                dialTuning = AZDialInteractionTuningPreset.mild.tuning
                return
            }
        }
        dialTuning = tuning
    }

    private func saveDialTuning() {
        // UserDefaultsに入れられるようJSONデータへ変換する
        guard let data = try? JSONEncoder().encode(dialTuning) else {
            return
        }
        ud.set(data, forKey: SettingsKeys.settDialTuning)
    }

    // MARK: - DateOpt 自動判定
    func autoDateOpt(for date: Date) -> DateOpt {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        let mapped = DateOpt(rawValue: dateOptHourMap[hour]) ?? .cat02
        // 時間帯マップが未定義区分を指す場合は、定義済み区分（＝新規記録の候補）へ丸める
        guard !mapped.isDefined else { return mapped }
        return orderedDefinedDateOpts.first ?? mapped
    }
}

// MARK: - 設定のバックアップ（全記録の書き出し／読み込み）

/// 「全記録を書き出す」に同梱する設定。
///
/// 端末に結びつく値（ヘルスケア連携・移行済み印・Demo の印・気象取得時刻・購入など）は
/// 別の端末へ移すと不具合になるので含めない。含めるものだけをここに列挙する（許可リスト）。
/// 区分の名称・色とタグリストは、記録の表示に要るので従来どおり別枠で書き出す。
///
/// 版の違うアプリ同士でやり取りされるので、全項目を任意にし、読めない項目は捨てて
/// 他の項目は生かす（1項目が壊れていても設定全体を失わない）。
/// 項目を増やしたら `AppSettings.makeBackup()` / `apply(_:)` と往復テストにも足す
struct AppSettingsBackup: Codable, Equatable {
    /// 設定バックアップ自体の版。記録ファイルの schemaVersion とは独立させる
    /// （上げると古いアプリが記録ごと読めなくなるのを避けるため）
    var version: Int? = 1

    // 表示
    var userLevel: Int?
    var appearanceMode: Int?
    /// 文字サイズ・起動時に開く・ダイアル式は新規では出さない設定だが、当面は引き継ぐ
    var fontScale: Int?
    var dialStyle: String?
    var dialTuning: AZDialInteractionTuning?

    // 記録
    var launchAction: Int?
    var useDialRecordEntry: Bool?
    var mergeWindowMinutes: Int?
    var mergeDefaultAction: Int?
    var estimateDateOpt: Bool?
    var recordFieldOrder: [Int]?
    var hiddenFields: [Int]?
    var dateOptHourMap: [Int]?
    var dateOptDisplayOrder: [Int]?

    // グラフ
    var graphDisplayOrder: [Int]?
    var graphHiddenPanels: [Int]?
    var graphHeightOverrides: [String: Double]?
    var graphOneWidth: Int?
    var graphBpMean: Bool?
    var graphBpPress: Bool?
    var graphBMITall: Int?
    var graphBMI: Bool?
    var graphWeightMA: Bool?
    var graphWeightChange: Bool?
    var graphBpLineMode: Int?
    var graphBpHiddenDateOpts: [Int]?

    // 統計
    var statType: Int?
    var statDays: Int?
    var statShowAvg: Bool?
    var statShowTimeLine: Bool?
    var statShow24HLine: Bool?
    var statSectionOrder: [Int]?
    var statHiddenSections: [Int]?
    var statBpDistributionHiddenDateOpts: [Int]?
    var statHeightOverrides: [String: Double]?

    // 分析（配置・ページ名・期間、症状パネルの絞り込み）
    var analysisLayout: AnalysisLayout?
    var analysisSymptomFilters: [String: String]?
    var analysisSymptomSelectionSync: Bool?

    // 目標値
    var goalEnabled: Bool?
    var goals: [String: Int]?

    init() {}

    init(from decoder: Decoder) throws {
        // settings がオブジェクトでない壊れたファイルでも、記録の取り込みは止めない
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        version = value(.version)
        userLevel = value(.userLevel)
        appearanceMode = value(.appearanceMode)
        fontScale = value(.fontScale)
        dialStyle = value(.dialStyle)
        dialTuning = value(.dialTuning)
        launchAction = value(.launchAction)
        useDialRecordEntry = value(.useDialRecordEntry)
        mergeWindowMinutes = value(.mergeWindowMinutes)
        mergeDefaultAction = value(.mergeDefaultAction)
        estimateDateOpt = value(.estimateDateOpt)
        recordFieldOrder = value(.recordFieldOrder)
        hiddenFields = value(.hiddenFields)
        dateOptHourMap = value(.dateOptHourMap)
        dateOptDisplayOrder = value(.dateOptDisplayOrder)
        graphDisplayOrder = value(.graphDisplayOrder)
        graphHiddenPanels = value(.graphHiddenPanels)
        graphHeightOverrides = value(.graphHeightOverrides)
        graphOneWidth = value(.graphOneWidth)
        graphBpMean = value(.graphBpMean)
        graphBpPress = value(.graphBpPress)
        graphBMITall = value(.graphBMITall)
        graphBMI = value(.graphBMI)
        graphWeightMA = value(.graphWeightMA)
        graphWeightChange = value(.graphWeightChange)
        graphBpLineMode = value(.graphBpLineMode)
        graphBpHiddenDateOpts = value(.graphBpHiddenDateOpts)
        statType = value(.statType)
        statDays = value(.statDays)
        statShowAvg = value(.statShowAvg)
        statShowTimeLine = value(.statShowTimeLine)
        statShow24HLine = value(.statShow24HLine)
        statSectionOrder = value(.statSectionOrder)
        statHiddenSections = value(.statHiddenSections)
        statBpDistributionHiddenDateOpts = value(.statBpDistributionHiddenDateOpts)
        statHeightOverrides = value(.statHeightOverrides)
        analysisLayout = value(.analysisLayout)
        analysisSymptomFilters = value(.analysisSymptomFilters)
        analysisSymptomSelectionSync = value(.analysisSymptomSelectionSync)
        goalEnabled = value(.goalEnabled)
        goals = value(.goals)
    }
}

extension AppSettings {

    /// いまの設定からバックアップを作る
    func makeBackup() -> AppSettingsBackup {
        var b = AppSettingsBackup()
        b.userLevel = userLevel.rawValue
        b.appearanceMode = appearanceMode.rawValue
        b.fontScale = fontScale.rawValue
        b.dialStyle = dialStyle
        b.dialTuning = dialTuning
        b.launchAction = launchAction.rawValue
        b.useDialRecordEntry = useDialRecordEntry
        b.mergeWindowMinutes = mergeWindowMinutes
        b.mergeDefaultAction = mergeDefaultAction
        b.estimateDateOpt = estimateDateOpt
        b.recordFieldOrder = graphPanelOrder
        b.hiddenFields = hiddenFields
        b.dateOptHourMap = dateOptHourMap
        b.dateOptDisplayOrder = dateOptDisplayOrder
        b.graphDisplayOrder = graphDisplayOrder
        b.graphHiddenPanels = graphHiddenPanels
        b.graphHeightOverrides = Dictionary(
            uniqueKeysWithValues: graphHeightOverrides.map { (String($0.key), $0.value) }
        )
        b.graphOneWidth = graphOneWidth
        b.graphBpMean = graphBpMean
        b.graphBpPress = graphBpPress
        b.graphBMITall = graphBMITall
        b.graphBMI = graphBMI
        b.graphWeightMA = graphWeightMA
        b.graphWeightChange = graphWeightChange
        b.graphBpLineMode = graphBpLineMode
        b.graphBpHiddenDateOpts = graphBpHiddenDateOpts
        b.statType = statType
        b.statDays = statDays
        b.statShowAvg = statShowAvg
        b.statShowTimeLine = statShowTimeLine
        b.statShow24HLine = statShow24HLine
        b.statSectionOrder = statSectionOrder
        b.statHiddenSections = statHiddenSections
        b.statBpDistributionHiddenDateOpts = statBpDistributionHiddenDateOpts
        b.statHeightOverrides = Dictionary(
            uniqueKeysWithValues: statHeightOverrides.map { (String($0.key), $0.value) }
        )
        b.analysisLayout = analysisLayout
        b.analysisSymptomFilters = analysisSymptomFilters
        b.analysisSymptomSelectionSync = analysisSymptomSelectionSync
        b.goalEnabled = goalEnabled
        b.goals = [
            "bpHi": goalBpHi, "bpLo": goalBpLo, "pulse": goalPulse,
            "weight": goalWeight, "temp": goalTemp, "bodyFat": goalBodyFat,
            "skMuscle": goalSkMuscle, "bpPp": goalBpPp, "bmi": goalBMI,
        ]
        return b
    }

    /// バックアップの設定で置き換える。含まれない項目・読めない値は今の設定のまま残す。
    /// 画面の作り直しを伴うユーザーレベルは最後に入れる
    func apply(_ b: AppSettingsBackup) {
        if let raw = b.appearanceMode, let v = AppAppearanceMode(rawValue: raw) { appearanceMode = v }
        if let raw = b.fontScale, let v = AppFontScale(rawValue: raw) { fontScale = v }
        if let v = b.dialStyle, DialStyle.builtin(id: v) != nil { dialStyle = v }
        if let v = b.dialTuning { dialTuning = v }

        if let raw = b.launchAction, let v = LaunchAction(rawValue: raw) { launchAction = v }
        if let v = b.useDialRecordEntry { useDialRecordEntry = v }
        if let v = b.mergeWindowMinutes, Self.mergeWindowChoices.contains(v) { mergeWindowMinutes = v }
        if let raw = b.mergeDefaultAction, ConflictAction(rawValue: raw) != nil { mergeDefaultAction = raw }
        if let v = b.estimateDateOpt { estimateDateOpt = v }
        let recordFields = GraphKind.allCases.filter(\.isRecordField).map(\.rawValue)
        if let v = b.recordFieldOrder, !v.isEmpty {
            graphPanelOrder = Self.normalizedOrder(v, allowed: recordFields)
        }
        if let v = b.hiddenFields { hiddenFields = Self.normalizedSubset(v, allowed: recordFields) }
        // 24時間ぶん揃っていない・知らない区分を指す割り当ては、区分の自動判定を壊すので使わない
        if let v = b.dateOptHourMap, v.count == 24,
           v.allSatisfy({ $0 == -1 || DateOpt(rawValue: $0) != nil }) {
            dateOptHourMap = v
        }
        let dateOpts = DateOpt.allCases.map(\.rawValue)
        if let v = b.dateOptDisplayOrder, !v.isEmpty {
            dateOptDisplayOrder = Self.normalizedOrder(v, allowed: dateOpts)
        }

        let graphKinds = GraphKind.allCases.map(\.rawValue)
        if let v = b.graphDisplayOrder, !v.isEmpty {
            graphDisplayOrder = Self.normalizedOrder(v, allowed: graphKinds)
        }
        if let v = b.graphHiddenPanels { graphHiddenPanels = Self.normalizedSubset(v, allowed: graphKinds) }
        if let v = b.graphHeightOverrides {
            graphHeightOverrides = Self.normalizedHeights(v, allowed: graphKinds)
        }
        if let v = b.graphOneWidth, 0 < v { graphOneWidth = v }
        if let v = b.graphBpMean { graphBpMean = v }
        if let v = b.graphBpPress { graphBpPress = v }
        // 身長は設定画面のダイアルと同じ範囲だけ受け付ける
        if let v = b.graphBMITall, (100...250).contains(v) { graphBMITall = v }
        if let v = b.graphBMI { graphBMI = v }
        if let v = b.graphWeightMA { graphWeightMA = v }
        if let v = b.graphWeightChange { graphWeightChange = v }
        if let raw = b.graphBpLineMode, GraphBpLineMode(rawValue: raw) != nil { graphBpLineMode = raw }
        if let v = b.graphBpHiddenDateOpts { graphBpHiddenDateOpts = Self.normalizedSubset(v, allowed: dateOpts) }

        if let v = b.statType, (0...1).contains(v) { statType = v }
        if let v = b.statDays, GraphPeriod(rawValue: v) != nil { statDays = v }
        if let v = b.statShowAvg { statShowAvg = v }
        if let v = b.statShowTimeLine { statShowTimeLine = v }
        if let v = b.statShow24HLine { statShow24HLine = v }
        let statSections = StatSection.allCases.map(\.rawValue)
        if let v = b.statSectionOrder, !v.isEmpty {
            statSectionOrder = Self.normalizedOrder(v, allowed: statSections)
        }
        if let v = b.statHiddenSections { statHiddenSections = Self.normalizedSubset(v, allowed: statSections) }
        if let v = b.statBpDistributionHiddenDateOpts {
            statBpDistributionHiddenDateOpts = Self.normalizedSubset(v, allowed: dateOpts)
        }
        if let v = b.statHeightOverrides {
            statHeightOverrides = Self.normalizedHeights(v, allowed: statSections)
        }

        if var layout = b.analysisLayout {
            // 版の違いで増減した図表を、この版の図表一覧に合わせて整える
            layout.normalize()
            analysisLayout = layout
        }
        if let v = b.analysisSymptomFilters { analysisSymptomFilters = v }
        if let v = b.analysisSymptomSelectionSync { analysisSymptomSelectionSync = v }

        if let v = b.goalEnabled { goalEnabled = v }
        if let raw = b.goals {
            // 目標値は 0（未設定）以上だけ受け付ける
            let g = raw.filter { 0 <= $0.value }
            if let v = g["bpHi"] { goalBpHi = v }
            if let v = g["bpLo"] { goalBpLo = v }
            if let v = g["pulse"] { goalPulse = v }
            if let v = g["weight"] { goalWeight = v }
            if let v = g["temp"] { goalTemp = v }
            if let v = g["bodyFat"] { goalBodyFat = v }
            if let v = g["skMuscle"] { goalSkMuscle = v }
            if let v = g["bpPp"] { goalBpPp = v }
            if let v = g["bmi"] { goalBMI = v }
        }

        if let raw = b.userLevel, let v = AppUserLevel(rawValue: raw) { userLevel = v }
    }

    // MARK: 取り込み値の正規化

    /// 図表の追加高さとして受け付ける範囲。図表下端のハンドルで調整できる範囲（-60〜400pt）と同じ。
    /// 範囲外や非有限値を入れると frame が崩れるので、取り込み時にこの範囲へ収める
    static let panelExtraHeightRange: ClosedRange<Double> = -60...400

    /// 記録をまとめる時間の選択肢（設定画面のプルダウンと同じ）
    static let mergeWindowChoices: Set<Int> = [0, 5, 10, 15, 30]

    /// 表示順を正規化する。この版に無い値と重複を除き（先に出た方を残す）、
    /// 足りない項目は allowed の順で末尾に補う
    static func normalizedOrder(_ values: [Int], allowed: [Int]) -> [Int] {
        let allowedSet = Set(allowed)
        var seen: Set<Int> = []
        var result = values.filter { allowedSet.contains($0) && seen.insert($0).inserted }
        result += allowed.filter { !seen.contains($0) }
        return result
    }

    /// 非表示などの集合を正規化する。この版に無い値と重複を除く（補完はしない）
    static func normalizedSubset(_ values: [Int], allowed: [Int]) -> [Int] {
        let allowedSet = Set(allowed)
        var seen: Set<Int> = []
        return values.filter { allowedSet.contains($0) && seen.insert($0).inserted }
    }

    /// 図表の追加高さを正規化する。対象の種別だけを残し、非有限値は捨て、許容範囲へ収める
    static func normalizedHeights(_ values: [String: Double], allowed: [Int]) -> [Int: Double] {
        let allowedSet = Set(allowed)
        var result: [Int: Double] = [:]
        for (key, value) in values {
            guard let intKey = Int(key), allowedSet.contains(intKey), value.isFinite else { continue }
            result[intKey] = min(max(value, panelExtraHeightRange.lowerBound), panelExtraHeightRange.upperBound)
        }
        return result
    }
}
