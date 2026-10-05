//
//  分析ページの配置モデル
//  測定・統計・症状の図表を3ページへ割り当て、順位と表示状態を保持する
//

import Foundation
import UIKit

enum AnalysisPage: Int, CaseIterable, Codable, Identifiable {
  case one = 1
  case two = 2
  case three = 3

  var id: Int { rawValue }
  /// 分析ページ番号をカレンダー型アイコンで示す。
  /// 「1.calendar」は iOS 26 からの記号なので、それより前は番号入りの四角で代用する
  var tabSymbol: String {
    AppSymbol.available("\(rawValue).calendar", fallback: "\(rawValue).square")
  }
  /// ページ名が空欄の場合に使う番号名
  var numberedTitle: String {
    String(format: String(localized: "analysis.page.titleFormat"), rawValue)
  }

  /// 初回にページ名へ設定するプリセット
  var presetTitle: String {
    switch self {
    case .one: return String(localized: "analysis.page.preset.trends")
    case .two: return String(localized: "tab.statistics")
    case .three: return String(localized: "analysis.symptoms")
    }
  }

  /// 画面とタブで共通して使う利用者設定済みのページ名
  func displayTitle(in layout: AnalysisLayout) -> String {
    layout.title(in: self)
  }

  func accessibilityTitle(in layout: AnalysisLayout) -> String {
    displayTitle(in: layout)
  }
}

/// iOS の版によって無い SF Symbols を、ある記号へ差し替える。
/// 対応OSは iOS 18 からだが、一部の記号は iOS 26 で追加されたもので、
/// 古い iOS では空白になってしまう（アイコンだけのタブやボタンが見えなくなる）
enum AppSymbol {
  /// 分析の配置
  static let layout = available("text.pad.header", fallback: "rectangle.3.group")
  /// 分析の期間
  static let period = available("ellipsis.calendar", fallback: "calendar")

  static func available(_ name: String, fallback: String) -> String {
    UIImage(systemName: name) != nil ? name : fallback
  }
}

/// 異なるenumの数値衝突を避けるため、図表IDは名前空間付き文字列で永続化する
enum AnalysisPanelID: String, CaseIterable, Codable, Identifiable {
  case graphBloodPressure = "graph.bloodPressure"
  case graphPulsePressure = "graph.pulsePressure"
  case graphHeartRate = "graph.heartRate"
  case graphBodyTemperature = "graph.bodyTemperature"
  case graphWeight = "graph.weight"
  case graphBodyFat = "graph.bodyFat"
  case graphSkeletalMuscle = "graph.skeletalMuscle"
  case graphBMI = "graph.bmi"
  case graphWeightChange = "graph.weightChange"

  case statBloodPressureDistribution = "statistics.bloodPressureDistribution"
  case statBloodPressureRatio = "statistics.bloodPressureRatio"
  case statBloodPressureByCategory = "statistics.bloodPressureByCategory"
  case statBloodPressure24Hours = "statistics.bloodPressure24Hours"
  case statBloodPressureSummary = "statistics.bloodPressureSummary"
  case statBloodPressureLeftRight = "statistics.bloodPressureLeftRight"
  case statWeightSummary = "statistics.weightSummary"
  case statBodyTemperatureSummary = "statistics.bodyTemperatureSummary"
  case statBodyTemperature24Hours = "statistics.bodyTemperature24Hours"
  case statBodyTemperatureDistribution = "statistics.bodyTemperatureDistribution"
  case statWeightBloodPressure = "statistics.weightBloodPressure"

  case symptomOverview = "symptom.overview"
  case symptomCalendar = "symptom.calendar"
  case symptomFrequency = "symptom.frequency"
  case symptomSummary = "symptom.summary"
  case symptomTriggers = "symptom.triggers"

  var id: String { rawValue }

  var titleKey: String {
    if let kind = graphKind { return kind.title }
    if let section = statSection { return section.title }
    switch self {
    case .symptomOverview: return "analysis.symptomSummary"
    case .symptomCalendar: return "analysis.calendar"
    case .symptomFrequency: return "analysis.trend"
    // 保存済み配置IDを維持したまま、文字中心の集計を環境図表へ置き換える
    case .symptomSummary: return "analysis.symptomEnvironment"
    case .symptomTriggers: return "analysis.trigger"
    default: return "analysis.unknownPanel"
    }
  }

  var defaultPage: AnalysisPage {
    if graphKind != nil { return .one }
    if statSection != nil { return .two }
    return .three
  }

  /// 症状図表かを種類から判定する
  var isSymptomPanel: Bool { graphKind == nil && statSection == nil }

  var graphKind: GraphKind? {
    switch self {
    case .graphBloodPressure: return .bp
    case .graphPulsePressure: return .bpAvg
    case .graphHeartRate: return .pulse
    case .graphBodyTemperature: return .temp
    case .graphWeight: return .weight
    case .graphBodyFat: return .bodyFat
    case .graphSkeletalMuscle: return .skMuscle
    case .graphBMI: return .bmi
    case .graphWeightChange: return .weightChange
    default: return nil
    }
  }

  init?(graphKind: GraphKind) {
    switch graphKind {
    case .bp: self = .graphBloodPressure
    case .bpAvg: self = .graphPulsePressure
    case .pulse: self = .graphHeartRate
    case .temp: self = .graphBodyTemperature
    case .weight: self = .graphWeight
    case .bodyFat: self = .graphBodyFat
    case .skMuscle: self = .graphSkeletalMuscle
    case .bmi: self = .graphBMI
    case .weightChange: self = .graphWeightChange
    }
  }

  var statSection: StatSection? {
    switch self {
    case .statBloodPressureDistribution: return .bpJsh
    case .statBloodPressureRatio: return .bpRatio
    case .statBloodPressureByCategory: return .bpDateOptCorr
    case .statBloodPressure24Hours: return .bp24h
    case .statBloodPressureSummary: return .bpSummary
    case .statBloodPressureLeftRight: return .bpLeftRight
    case .statWeightSummary: return .weightSummary
    case .statBodyTemperatureSummary: return .tempSummary
    case .statBodyTemperature24Hours: return .temp24h
    case .statBodyTemperatureDistribution: return .tempHist
    case .statWeightBloodPressure: return .weightBpScatter
    default: return nil
    }
  }

  init?(statSection: StatSection) {
    switch statSection {
    case .bpJsh: self = .statBloodPressureDistribution
    case .bpRatio: self = .statBloodPressureRatio
    case .bpDateOptCorr: self = .statBloodPressureByCategory
    case .bp24h: self = .statBloodPressure24Hours
    case .bpSummary: self = .statBloodPressureSummary
    case .bpLeftRight: self = .statBloodPressureLeftRight
    case .weightSummary: self = .statWeightSummary
    case .tempSummary: self = .statBodyTemperatureSummary
    case .temp24h: self = .statBodyTemperature24Hours
    case .tempHist: self = .statBodyTemperatureDistribution
    case .weightBpScatter: self = .statWeightBloodPressure
    }
  }
}

struct AnalysisLayout: Codable, Equatable {
  var version = 1
  var page1: [AnalysisPanelID]
  var page2: [AnalysisPanelID]
  var page3: [AnalysisPanelID]
  var hidden: Set<AnalysisPanelID>
  var period1: Int
  var period2: Int
  var period3: Int
  /// 利用者が変更したページ名
  /// 未保存の既存データをそのまま読み込めるよう任意値で保持する
  var pageNames: [String: String]? = nil
  /// 3ページで期間をそろえるか。未保存の既存データは nil で、同期する（既定 ON）として扱う
  var periodSync: Bool? = nil

  var isPeriodSynced: Bool { periodSync ?? true }

  /// 空欄の場合はページ番号を使った名前を返す
  func title(in page: AnalysisPage) -> String {
    let name = pageNameInput(in: page).trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? page.numberedTitle : name
  }

  /// 未設定のページにはプリセットを初期値として返す
  func pageNameInput(in page: AnalysisPage) -> String {
    pageNames?[String(page.rawValue)] ?? page.presetTitle
  }

  /// ページ名の最大文字数。タブの見出しに収まる長さ
  static let pageNameMaxLength = 6

  /// ページ名を6文字まで保存し、空欄も利用者の選択として残す
  mutating func setPageName(_ name: String, in page: AnalysisPage) {
    var names = pageNames ?? [:]
    let limitedName = String(name.prefix(Self.pageNameMaxLength))
    names[String(page.rawValue)] = limitedName
    pageNames = names
  }

  func panels(in page: AnalysisPage) -> [AnalysisPanelID] {
    switch page {
    case .one: return page1
    case .two: return page2
    case .three: return page3
    }
  }

  func visiblePanels(in page: AnalysisPage) -> [AnalysisPanelID] {
    panels(in: page).filter { !hidden.contains($0) }
  }

  /// 従来の表示OFFを含む非表示図表を、元の配置順で返す
  var hiddenPanels: [AnalysisPanelID] {
    AnalysisPage.allCases.flatMap { panels(in: $0) }.filter { hidden.contains($0) }
  }

  func period(in page: AnalysisPage) -> GraphPeriod {
    // 同期中は分析1の値を全ページの期間とする（setPeriod が3値をそろえて書く）
    let target: AnalysisPage = isPeriodSynced ? .one : page
    let raw: Int
    switch target {
    case .one: raw = period1
    case .two: raw = period2
    case .three: raw = period3
    }
    return GraphPeriod(rawValue: raw) ?? .threeMonths
  }

  mutating func setPeriod(_ period: GraphPeriod, in page: AnalysisPage) {
    if isPeriodSynced {
      period1 = period.rawValue
      period2 = period.rawValue
      period3 = period.rawValue
      return
    }
    switch page {
    case .one: period1 = period.rawValue
    case .two: period2 = period.rawValue
    case .three: period3 = period.rawValue
    }
  }

  /// 期間の同期を切り替える。ON にしたときは、表示中のページの期間を全ページへそろえ、
  /// 切り替えた直後に見ている期間が変わらないようにする
  mutating func setPeriodSync(_ isOn: Bool, keeping page: AnalysisPage) {
    let current = period(in: page)
    periodSync = isOn
    if isOn { setPeriod(current, in: page) }
  }

  mutating func setPanels(_ panels: [AnalysisPanelID], in page: AnalysisPage) {
    switch page {
    case .one: page1 = panels
    case .two: page2 = panels
    case .three: page3 = panels
    }
  }

  mutating func move(_ panel: AnalysisPanelID, to destination: AnalysisPage) {
    for page in AnalysisPage.allCases {
      var values = panels(in: page)
      values.removeAll { $0 == panel }
      setPanels(values, in: page)
    }
    var destinationPanels = panels(in: destination)
    destinationPanels.append(panel)
    setPanels(destinationPanels, in: destination)
    hidden.remove(panel)
  }

  /// 図表をページから外さず非表示の配置へ移す
  mutating func moveToHidden(_ panel: AnalysisPanelID) {
    hidden.insert(panel)
  }

  mutating func normalize() {
    var seen = Set<AnalysisPanelID>()
    for page in AnalysisPage.allCases {
      let unique = panels(in: page).filter { seen.insert($0).inserted }
      setPanels(unique, in: page)
    }
    // アップデートで増えた図表は既定ページの末尾へ補う
    for panel in AnalysisPanelID.allCases where !seen.contains(panel) {
      var values = panels(in: panel.defaultPage)
      // 症状サマリーは既存利用者にも症状ページの先頭へ追加する
      if panel == .symptomOverview {
        values.insert(panel, at: 0)
      } else {
        values.append(panel)
      }
      setPanels(values, in: panel.defaultPage)
      seen.insert(panel)
    }
    hidden = hidden.intersection(seen)
    // バックアップから取り込んだ名称は setPageName を通らないので、ここでも有効なページだけ残し、
    // 長さを制限する（長い名称はタブ表示を崩す）
    if let names = pageNames {
      let validKeys = Set(AnalysisPage.allCases.map { String($0.rawValue) })
      pageNames = names
        .filter { validKeys.contains($0.key) }
        .mapValues { String($0.prefix(Self.pageNameMaxLength)) }
    }
  }

  static func migrated(
    graphOrder: [Int],
    hiddenGraphs: [Int],
    statOrder: [Int],
    hiddenStats: [Int],
    statDays: Int
  ) -> AnalysisLayout {
    let graphPanels = graphOrder.compactMap(GraphKind.init(rawValue:)).compactMap {
      AnalysisPanelID(graphKind: $0)
    }
    let statPanels = statOrder.compactMap(StatSection.init(rawValue:)).compactMap {
      AnalysisPanelID(statSection: $0)
    }
    var hidden = Set(
      hiddenGraphs.compactMap(GraphKind.init(rawValue:)).compactMap {
        AnalysisPanelID(graphKind: $0)
      })
    hidden.formUnion(
      hiddenStats.compactMap(StatSection.init(rawValue:)).compactMap {
        AnalysisPanelID(statSection: $0)
      })
    var result = AnalysisLayout(
      page1: graphPanels,
      page2: statPanels,
      page3: [
        .symptomOverview,
        .symptomCalendar,
        .symptomFrequency,
        .symptomSummary,
        .symptomTriggers,
      ],
      hidden: hidden,
      period1: GraphPeriod.month.rawValue,
      period2: GraphPeriod(rawValue: statDays)?.rawValue ?? GraphPeriod.threeMonths.rawValue,
      period3: GraphPeriod.threeMonths.rawValue
    )
    result.normalize()
    return result
  }
}

/// 記録開始件数と、期間に重なる症状日数を同じ境界規則で集計する
struct SymptomAnalysisRange {
  let start: Date
  let end: Date
  var calendar = AppDateCalendar.gregorian

  func containsStart(_ record: SymptomRecord) -> Bool {
    start <= record.startAt && record.startAt < end
  }

  func overlaps(_ record: SymptomRecord) -> Bool {
    guard record.startAt < end else { return false }
    if record.bOngoing { return true }
    if let finish = record.endAt, record.startAt < finish { return start < finish }
    return start <= record.startAt
  }

  func symptomDays(_ records: [SymptomRecord]) -> Int {
    var days = Set<Date>()
    for record in records where 1 < record.nSeverity && overlaps(record) {
      var day = calendar.startOfDay(for: max(start, record.startAt))
      let finish = record.bOngoing ? end : min(end, record.endAt ?? record.startAt)
      // 終息時刻ちょうどの翌日は数えず、終息日時不明は開始日だけ数える
      repeat {
        days.insert(day)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      } while day < finish
    }
    return days.count
  }
}
