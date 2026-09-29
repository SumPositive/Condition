//
//  分析ページ
//  3つの独立した期間と自由配置された測定・統計・症状の図表を表示する
//

import Charts
import SwiftData
import SwiftUI
import UIKit

struct AnalysisPageView: View {
  let page: AnalysisPage
  @Query(
    filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
    sort: \BodyRecord.dateTime,
    order: .reverse
  )
  private var bodyRecords: [BodyRecord]
  @Query(sort: \SymptomRecord.startAt) private var symptomRecords: [SymptomRecord]
  @State private var settings = AppSettings.shared
  @State private var chartWidth: CGFloat = 390
  @State private var showSettings = false
  @State private var isExporting = false

  private var period: GraphPeriod { settings.analysisLayout.period(in: page) }
  private var visiblePanels: [AnalysisPanelID] { settings.analysisLayout.visiblePanels(in: page) }

  /// AZPickerで表示する「すべて」と症状名の選択肢
  private var symptomFilterOptions: [AnalysisSymptomFilterOption] {
    [AnalysisSymptomFilterOption(id: "", title: String(localized: "analysis.all"))]
      + symptomIDs.map { AnalysisSymptomFilterOption(id: $0, title: symptomName($0)) }
  }

  /// 周期性は単一症状の発症間隔を分析するため「すべて」を候補から外す
  private func symptomFilterOptions(for panel: AnalysisPanelID) -> [AnalysisSymptomFilterOption] {
    guard panel == .symptomFrequency else { return symptomFilterOptions }
    let options = symptomIDs.map { AnalysisSymptomFilterOption(id: $0, title: symptomName($0)) }
    return options.isEmpty ? [AnalysisSymptomFilterOption(id: "", title: "—")] : options
  }

  private var periodBinding: Binding<GraphPeriod> {
    Binding(
      get: { settings.analysisLayout.period(in: page) },
      set: { newValue in
        var layout = settings.analysisLayout
        layout.setPeriod(newValue, in: page)
        settings.analysisLayout = layout
        AppAnalytics.shared.logFeature(
          "analysis_page_period_select",
          parameters: ["page": page.rawValue, "period_days": newValue.rawValue]
        )
      }
    )
  }

  private var targetBodyRecords: [BodyRecord] {
    let cutoff =
      Calendar.current.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    return bodyRecords.filter { cutoff <= $0.dateTime }
  }

  /// 測定グラフは従来どおり、選択期間の前後へ横スクロールできるよう1年分を渡す
  private var graphBodyRecords: [BodyRecord] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
    return bodyRecords.filter { cutoff <= $0.dateTime }
  }

  private var symptomIDs: [String] {
    let now = Date()
    // 「なし」を除く発症記録を症状ごとに数え、よく記録する症状を上位へ並べる
    let onsetCounts = symptomRecords.reduce(into: [String: Int]()) { counts, record in
      guard !record.sSymptomID.isEmpty,
            record.startAt <= now,
            1 < record.nSeverity
      else { return }
      counts[record.sSymptomID, default: 0] += 1
    }
    return Set(symptomRecords.map(\.sSymptomID).filter { !$0.isEmpty }).sorted { lhs, rhs in
      let lhsCount = onsetCounts[lhs, default: 0]
      let rhsCount = onsetCounts[rhs, default: 0]
      if lhsCount != rhsCount { return rhsCount < lhsCount }
      return symptomName(lhs).localizedStandardCompare(symptomName(rhs)) == .orderedAscending
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 0) {
          BeginnerHelpBanner(
            hintKey: helpHintKey,
            messageText: helpMessage,
            storageKey: helpStorageKey
          )
          LazyVStack(spacing: 0) {
            periodPicker
            if visiblePanels.isEmpty {
              ContentUnavailableView(
                "analysis.page.empty",
                systemImage: "rectangle.3.group"
              )
              .padding(.top, 60)
            } else {
              ForEach(visiblePanels) { panel in
                analysisPanel(panel)
              }
            }
          }
          .padding(.horizontal)
          .padding(.vertical, 12)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { chartWidth = $0 }
      }
      .scrollIndicators(.hidden)
      .environment(\.chartAvailableWidth, chartWidth)
      .overlay { if isExporting { exportingOverlay } }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            exportPDF()
          } label: {
            ToolbarButtonLabel(
              systemImage: "square.and.arrow.up",
              captionKey: "analysis.toolbar.pdf"
            )
          }
          .disabled(visiblePanels.isEmpty || isExporting)
        }
        ToolbarItem(placement: .principal) {
          // 画面タイトルはアイコンを使わず分析名を明記する
          Text(page.displayTitle(in: settings.analysisLayout))
            .font(.headline)
            .accessibilityLabel(page.accessibilityTitle(in: settings.analysisLayout))
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            showSettings = true
          } label: {
            ToolbarButtonLabel(
              systemImage: "text.pad.header",
              captionKey: "analysis.toolbar.layout"
            )
          }
        }
      }
      .sheet(isPresented: $showSettings) {
        let content = NavigationStack {
          AnalysisLayoutSettingsView(initialPage: page, isModal: true)
        }
        if settings.fontScale.followsSystem {
          content
        } else {
          content.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
        }
      }
      // 区分のアイコン・名称・色を変えたときはページ全体を作り直す
      .id(settings.dateOptAppearanceRevision)
    }
  }

  private var pageTitle: String {
    page.displayTitle(in: settings.analysisLayout)
  }

  private var periodPicker: some View {
    AZRadioPicker(
      options: GraphPeriod.allCases,
      selection: periodBinding,
      minOptionWidth: 0,
      maxOptionWidth: 120,
      horizontalPadding: 12,
      optionSpacing: 4,
      groupPadding: 2,
      wrapsOptions: false,
      // 期間は左右端まで均等な幅で配置する
      fillsWidth: true
    ) { value in
      Text(LocalizedStringKey(value.shortLabel))
    }
    .padding(.bottom, 8)
  }

  @ViewBuilder
  private func analysisPanel(_ panel: AnalysisPanelID) -> some View {
    if let kind = panel.graphKind {
      if graphBodyRecords.isEmpty {
        AnalysisEmptyPanel(titleKey: panel.titleKey)
      } else {
        AnalysisGraphPanel(kind: kind, records: graphBodyRecords, period: period)
      }
    } else if let section = panel.statSection {
      if targetBodyRecords.isEmpty {
        AnalysisEmptyPanel(titleKey: panel.titleKey)
      } else {
        AnalysisStatPanel(section: section, records: targetBodyRecords)
      }
    } else {
      switch panel {
      case .symptomCalendar:
        AnalysisSymptomCalendarPanel(
          records: filteredSymptomRecords(for: panel),
          symptomOptions: symptomFilterOptions(for: panel),
          selectedSymptom: symptomFilterBinding(for: panel),
          name: symptomName
        )
      case .symptomFrequency:
        AnalysisSymptomFrequencyPanel(
          records: filteredSymptomRecords(for: panel),
          range: symptomRange,
          symptomOptions: symptomFilterOptions(for: panel),
          selectedSymptom: symptomFilterBinding(for: panel)
        )
      case .symptomSummary:
        AnalysisSymptomEnvironmentPanel(
          symptomRecords: filteredSymptomRecords(for: panel),
          range: symptomRange,
          symptomOptions: symptomFilterOptions(for: panel),
          selectedSymptom: symptomFilterBinding(for: panel)
        )
      case .symptomTriggers:
        AnalysisSymptomTriggerPanel(
          symptomRecords: filteredSymptomRecords(for: panel),
          range: symptomRange,
          symptomOptions: symptomFilterOptions(for: panel),
          selectedSymptom: symptomFilterBinding(for: panel)
        )
      default:
        EmptyView()
      }
    }
  }

  /// 削除済みIDは各パネルで利用可能な初期選択へ戻す
  private func selectedSymptomID(for panel: AnalysisPanelID) -> String {
    let saved = settings.analysisSymptomFilter(for: panel, in: page)
    if symptomIDs.contains(saved) { return saved }
    // 周期性では発症件数が最も多い先頭の症状を初期選択する
    return panel == .symptomFrequency ? symptomIDs.first ?? "" : ""
  }

  private func selectedSymptomOption(for panel: AnalysisPanelID) -> AnalysisSymptomFilterOption {
    let selectedID = selectedSymptomID(for: panel)
    let options = symptomFilterOptions(for: panel)
    return options.first { $0.id == selectedID } ?? options[0]
  }

  private func symptomFilterBinding(
    for panel: AnalysisPanelID
  ) -> Binding<AnalysisSymptomFilterOption> {
    Binding(
      get: { selectedSymptomOption(for: panel) },
      set: { settings.setAnalysisSymptomFilter($0.id, for: panel) }
    )
  }

  private func filteredSymptomRecords(for panel: AnalysisPanelID) -> [SymptomRecord] {
    let selectedID = selectedSymptomID(for: panel)
    // パネルで選択した症状と現在時刻以前の記録だけを返す
    return symptomRecords.filter {
      (selectedID.isEmpty || $0.sSymptomID == selectedID) && $0.startAt <= Date()
    }
  }

  private var symptomRange: SymptomAnalysisRange {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    return SymptomAnalysisRange(
      start: calendar.date(byAdding: .day, value: 1 - period.rawValue, to: today)!,
      end: Date()
    )
  }

  private func symptomName(_ id: String) -> String {
    (settings.symptomTags.tag(for: id) ?? SymptomTag(id: id)).symptomDisplayName
  }

  private var helpHintKey: LocalizedStringKey {
    "analysis.page.helpHint"
  }

  private var helpStorageKey: String {
    "helpDismissed.analysisPage\(page.rawValue)"
  }

  private var helpMessage: Text {
    let blue: (String) -> Text = { name in
      Text(Image(systemName: name)).foregroundColor(.blue)
    }
    return Text("analysis.page.help")
      + Text(verbatim: "\n\n")
      + blue("text.pad.header") + Text(verbatim: " ")
      + Text("analysis.page.helpSettings")
      + Text(verbatim: "\n\n")
      + blue("square.and.arrow.up") + Text(verbatim: " ")
      + Text("analysis.page.helpExport")
  }

  private var exportingOverlay: some View {
    ZStack {
      Color.black.opacity(0.3).ignoresSafeArea()
      VStack(spacing: 14) {
        ProgressView().scaleEffect(1.4)
        Text(String(format: String(localized: "export.generating"), "PDF"))
          .font(.subheadline.weight(.medium))
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 22)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  private func exportPDF() {
    Task { @MainActor in
      isExporting = true
      defer { isExporting = false }
      try? await Task.sleep(for: .milliseconds(50))
      let width = PDFPanelExporter.contentW
      let panels = visiblePanels.map { panel in
        AnyView(analysisPanel(panel).environment(\.chartAvailableWidth, width))
      }
      let formatter = DateFormatter()
      formatter.setLocalizedDateFormatFromTemplate("yMd")
      let now = Date()
      let from = Calendar.current.date(byAdding: .day, value: -period.rawValue, to: now) ?? now
      let subtitle =
        NSLocalizedString(period.label, comment: "") + "  "
        + formatter.string(from: from) + String(localized: "format.range.separator")
        + formatter.string(from: now)
      let data = PDFPanelExporter.export(panels: panels, title: pageTitle, subtitle: subtitle)
      let dateTag = {
        let value = DateFormatter()
        value.dateFormat = "yyyyMMdd"
        return value.string(from: now)
      }()
      guard
        let url = PDFPanelExporter.writeTempFile(
          name: "\(pageTitle)_\(dateTag).pdf",
          data: data
        )
      else { return }
      presentShareSheet(url)
    }
  }

  private func presentShareSheet(_ url: URL) {
    guard
      let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    top.present(
      UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
  }
}

private struct AnalysisEmptyPanel: View {
  let titleKey: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(LocalizedStringKey(titleKey)).font(.headline)
      Label("empty.noDataInPeriod", systemImage: "chart.xyaxis.line")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 16)
  }
}

private struct AnalysisGraphPanel: View {
  let kind: GraphKind
  let records: [BodyRecord]
  let period: GraphPeriod
  @State private var settings = AppSettings.shared
  @State private var draftHeight: CGFloat?

  private var height: CGFloat {
    draftHeight ?? CGFloat(settings.graphHeightOverrides[kind.rawValue] ?? 0)
  }

  var body: some View {
    VStack(spacing: 0) {
      content.environment(\.chartExtraHeight, height)
      AnalysisResizeHandle(
        current: height,
        onDrag: { draftHeight = $0 },
        onCommit: {
          draftHeight = nil
          settings.graphHeightOverrides[kind.rawValue] = Double($0)
        }
      )
    }
  }

  @ViewBuilder
  private var content: some View {
    switch kind {
    case .bp:
      BpChartView(records: records, period: period)
    case .bpAvg:
      BpPpChartView(records: records, period: period, goalValue: settings.goalBpPp)
    case .pulse:
      LineChartView(
        records: records, keyPath: \.nPulse_bpm, title: kind.title, unit: "unit.bpm",
        color: .orange, goalValue: settings.goalPulse, period: period,
        tightDomain: true, usesDateOptFilterAndLineMode: true, kind: kind
      )
    case .temp:
      LineChartView(
        records: records, keyPath: \.nTemp_10c, title: kind.title, unit: "unit.celsius",
        color: .pink, goalValue: settings.goalTemp, decimals: 1, period: period,
        tightDomain: true, kind: kind
      )
    case .weight:
      LineChartView(
        records: records, keyPath: \.nWeight_10Kg, title: kind.title, unit: "unit.kg",
        color: .indigo, goalValue: settings.goalWeight, decimals: 1, period: period,
        tightDomain: true, showMovingAverage: settings.graphWeightMA, kind: kind
      )
    case .bmi:
      if 0 < settings.graphBMITall {
        BMIChartView(
          records: records, heightCm: settings.graphBMITall,
          period: period, goalValue: settings.goalBMI
        )
      }
    case .weightChange:
      WeightChangeChartView(records: records, period: period)
    case .bodyFat:
      LineChartView(
        records: records, keyPath: \.nBodyFat_10p, title: kind.title, unit: "%",
        color: .purple, goalValue: settings.goalBodyFat, decimals: 1, period: period,
        tightDomain: true, kind: kind
      )
    case .skMuscle:
      LineChartView(
        records: records, keyPath: \.nSkMuscle_10p, title: kind.title, unit: "%",
        color: .teal, goalValue: settings.goalSkMuscle, decimals: 1, period: period,
        tightDomain: true, kind: kind
      )
    }
  }
}

private struct AnalysisStatPanel: View {
  let section: StatSection
  let records: [BodyRecord]
  @State private var settings = AppSettings.shared
  @State private var draftHeight: CGFloat?

  private static let resizable: Set<StatSection> = [
    .bpJsh, .bpDateOptCorr, .bp24h, .temp24h, .tempHist, .weightBpScatter,
  ]

  private var height: CGFloat {
    draftHeight ?? CGFloat(settings.statHeightOverrides[section.rawValue] ?? 0)
  }

  var body: some View {
    if Self.resizable.contains(section) {
      VStack(spacing: 0) {
        content.environment(\.chartExtraHeight, height)
        AnalysisResizeHandle(
          current: height,
          onDrag: { draftHeight = $0 },
          onCommit: {
            draftHeight = nil
            settings.statHeightOverrides[section.rawValue] = Double($0)
          }
        )
      }
    } else {
      content.padding(.bottom, 16)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch section {
    case .bpJsh: BpJshView(records: records)
    case .bpRatio: BpJshRatioView(records: records)
    case .bpDateOptCorr: BpDateOptCorrView(records: records)
    case .bp24h: Bp24HChartView(records: records)
    case .bpSummary: BpSummaryView(records: records)
    case .bpLeftRight: BpLeftRightView(records: records)
    case .weightSummary: WeightSummaryView(records: records)
    case .tempSummary: TempSummaryView(records: records)
    case .temp24h: Temp24HChartView(records: records)
    case .tempHist: TempHistogramView(records: records)
    case .weightBpScatter: WeightBpScatterView(records: records)
    }
  }
}

private struct AnalysisResizeHandle: View {
  let current: CGFloat
  let onDrag: (CGFloat) -> Void
  let onCommit: (CGFloat) -> Void
  @State private var start: CGFloat?
  private let minHeight: CGFloat = -60
  private let maxHeight: CGFloat = 400

  var body: some View {
    HStack {
      Spacer()
      Capsule()
        .fill(Color(.tertiaryLabel))
        .frame(width: 56, height: 5)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
              if start == nil { start = current }
              onDrag(min(max((start ?? 0) + value.translation.height, minHeight), maxHeight))
            }
            .onEnded { _ in
              onCommit(current)
              start = nil
            }
        )
      Spacer()
    }
    .accessibilityLabel(Text("graph.resizeHandle"))
    .accessibilityAdjustableAction { direction in
      let step: CGFloat = 24
      switch direction {
      case .increment: onCommit(min(current + step, maxHeight))
      case .decrement: onCommit(max(current - step, minHeight))
      @unknown default: break
      }
    }
  }
}

/// 症状絞り込み用AZPickerの選択肢
private struct AnalysisSymptomFilterOption: Identifiable, Hashable {
  let id: String
  let title: String
}

/// 症状図表ごとに独立して対象を選ぶプルダウン
private struct AnalysisSymptomTargetPicker: View {
  let options: [AnalysisSymptomFilterOption]
  @Binding var selection: AnalysisSymptomFilterOption
  @State private var isExpanded = false

  var body: some View {
    HStack(spacing: 12) {
      Text("analysis.symptoms")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      AZDropdownPicker(
        options: options,
        selection: $selection,
        isExpanded: $isExpanded,
        minWidth: 140,
        // 標準のアイコンなしスタイルで横幅いっぱいに表示する
        fillsWidth: true
      ) { option in
        Text(option.title)
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private extension Color {
  /// 白いカード背景へアクセント色を淡く重ねる
  static var analysisSymptomPanelBackground: Color {
    Color(UIColor { traits in
      let base = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
      // Pickerの開閉や対象変更後も色が変わらない固定のシステムブルーを使う
      let tint = UIColor.systemBlue.resolvedColor(with: traits)
      var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
      var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
      base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
      tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
      let amount: CGFloat = 0.08
      return UIColor(
        red: br + (tr - br) * amount,
        green: bg + (tg - bg) * amount,
        blue: bb + (tb - bb) * amount,
        alpha: ba
      )
    })
  }
}

private extension SymptomSeverity {
  /// 分析画面で程度を見分ける固定色
  var analysisColor: Color {
    switch self {
    case .notPresent, .mild: return .blue
    case .moderate: return .yellow
    case .severe: return .red
    case .unspecified: return .secondary
    }
  }
}

private enum AnalysisCalendarLevel {
  case years
  case months
  case days
}

/// 曜日、余白、日付を一意なIDで並べるカレンダーセル
private enum AnalysisCalendarGridItem: Identifiable {
  case weekday(index: Int, title: String)
  case placeholder(index: Int)
  case day(number: Int, date: Date)

  var id: String {
    switch self {
    case .weekday(let index, _): return "weekday-\(index)"
    case .placeholder(let index): return "placeholder-\(index)"
    case .day(let number, _): return "day-\(number)"
    }
  }
}

private struct AnalysisSymptomCalendarPanel: View {
  let records: [SymptomRecord]
  let symptomOptions: [AnalysisSymptomFilterOption]
  @Binding var selectedSymptom: AnalysisSymptomFilterOption
  let name: (String) -> String
  @State private var level = AnalysisCalendarLevel.years
  @State private var selectedYear = Calendar.current.component(.year, from: Date())
  @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
  @State private var selectedDay: Date?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var periodCellMinimumWidth: CGFloat = 84
  @ScaledMetric(relativeTo: .body) private var calendarGridMinimumWidth: CGFloat = 300
  @ScaledMetric(relativeTo: .caption) private var legendPreferredFontSize: CGFloat = 12
  private let calendar = Calendar.current

  private var currentYear: Int { calendar.component(.year, from: Date()) }
  private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }

  /// 外部取り込みなどで程度がない記録が含まれる場合だけ未指定を案内する
  private var hasUnspecifiedSeverity: Bool {
    records.contains { $0.nSeverity == SymptomSeverity.unspecified.rawValue }
  }

  /// 記録が途切れた年も表示し、前回発症からの間隔を見えるようにする
  private var displayedYears: [Int] {
    let first = records.map { calendar.component(.year, from: $0.startAt) }.min() ?? currentYear
    return Array((min(first, currentYear)...currentYear).reversed())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // カレンダーは年・月・日で辿るため、上部の期間切り替えが効かないことを示す
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("analysis.calendar")
          .font(.headline)
        Spacer(minLength: 4)
        Text("analysis.calendar.periodFilterDisabled")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      AnalysisSymptomTargetPicker(
        options: symptomOptions,
        selection: $selectedSymptom
      )
      switch level {
      case .years:
        yearOverview
      case .months:
        monthOverview
      case .days:
        dayOverview
      }
      calendarLegend
    }
    .padding()
    .background(Color.analysisSymptomPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 16)
    .sheet(
      isPresented: Binding(
        get: { selectedDay != nil },
        set: { if !$0 { selectedDay = nil } }
      )
    ) {
      if let selectedDay {
        AnalysisSymptomDayDetailView(
          date: selectedDay,
          records: dayRecords(selectedDay),
          symptomName: name,
          onClose: { self.selectedDay = nil }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
  }

  private var yearOverview: some View {
    VStack(spacing: 10) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: periodCellMinimumWidth), spacing: 8)],
        spacing: 8
      ) {
        ForEach(displayedYears, id: \.self) { year in
          let values = yearRecords(year)
          periodButton(label: "\(year)", records: values) {
            selectedYear = year
            level = .months
          }
        }
      }
    }
  }

  private var monthOverview: some View {
    VStack(spacing: 10) {
      HStack {
        Button {
          level = .years
        } label: {
          Image(systemName: "chevron.backward")
        }
        .accessibilityLabel(Text("analysis.calendar.backToYears"))
        Spacer()
        Text(String(format: String(localized: "analysis.calendar.yearFormat"), selectedYear))
          .font(.headline)
        Spacer()
        Color.clear.frame(width: 20, height: 1)
      }
      LazyVGrid(
        // 1月から12月までを4列3行で固定表示する
        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
        spacing: 8
      ) {
        ForEach(1...12, id: \.self) { number in
          let target = monthDate(year: selectedYear, month: number)
          let values = monthRecords(target)
          periodButton(
            label: target.formatted(.dateTime.month(.abbreviated)),
            records: values
          ) {
            month = target
            level = .days
          }
          .disabled(Date() < target)
        }
      }
    }
  }

  private var dayOverview: some View {
    VStack(spacing: 10) {
      HStack {
        Button {
          selectedYear = calendar.component(.year, from: monthStart)
          level = .months
        } label: {
          Image(systemName: "chevron.backward")
        }
        .accessibilityLabel(Text("analysis.calendar.backToMonths"))
        Spacer()
        Button {
          moveMonth(-1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .accessibilityLabel(Text("analysis.previousMonth"))
        Text(monthStart.formatted(.dateTime.year().month(.wide)))
          .frame(minWidth: 120)
        Button {
          moveMonth(1)
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(calendar.isDate(monthStart, equalTo: Date(), toGranularity: .month))
        .accessibilityLabel(Text("analysis.nextMonth"))
        Spacer()
        Color.clear.frame(width: 20, height: 1)
      }
      dayCalendarGrid
    }
  }

  /// 通常文字では親幅を使い、大きな文字の時だけ明示幅で横スクロールする
  @ViewBuilder
  private var dayCalendarGrid: some View {
    if DynamicTypeSize.accessibility1 <= dynamicTypeSize {
      ScrollView(.horizontal) {
        calendarGrid
          .frame(width: max(calendarGridMinimumWidth, 300))
      }
      .scrollIndicators(.hidden)
    } else {
      calendarGrid
    }
  }

  private var calendarGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
      ForEach(calendarGridItems) { item in
        switch item {
        case .weekday(_, let title):
          Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
        case .placeholder:
          Color.clear.frame(height: 40)
        case .day(let number, let day):
          let values = dayRecords(day)
          let severity = values.map(\.nSeverity).max() ?? 0
          Button {
            selectedDay = day
          } label: {
            ZStack {
              severityCircle(hasRecords: !values.isEmpty, severity: severity, diameter: 42)
              Text("\(number)")
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.plain)
          .disabled(Date() < day)
        }
      }
    }
  }

  /// 程度アイコンを1行で示し、幅不足時は凡例だけ縮小する
  private var calendarLegend: some View {
    let preferredSize = min(legendPreferredFontSize, 17)
    return VStack(alignment: .leading, spacing: 8) {
      Text("analysis.calendar.maximumSeverity")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ViewThatFits(in: .horizontal) {
        calendarLegendRow(fontSize: preferredSize)
        calendarLegendRow(fontSize: max(preferredSize - 1, 12))
        calendarLegendRow(fontSize: max(preferredSize - 2, 11))
        calendarLegendRow(fontSize: max(preferredSize - 3, 10))
        calendarLegendRow(fontSize: max(preferredSize - 4, 10))
        calendarLegendRow(fontSize: max(preferredSize - 5, 9))
        calendarLegendRow(fontSize: max(preferredSize - 6, 9))
        calendarLegendRow(fontSize: max(preferredSize - 7, 9))
        calendarLegendRow(fontSize: 9)
      }
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 4)
  }

  /// 凡例全体へ同じ文字サイズを適用する
  private func calendarLegendRow(fontSize: CGFloat) -> some View {
    HStack(spacing: 8) {
      ForEach(SymptomSeverity.selectableCases) { severity in
        calendarLegendItem(
          label: LocalizedStringKey(severity.labelKey),
          severity: severity.rawValue
        )
      }
      if hasUnspecifiedSeverity {
        calendarLegendItem(
          label: LocalizedStringKey(SymptomSeverity.unspecified.labelKey),
          severity: SymptomSeverity.unspecified.rawValue
        )
      }
    }
    .font(.system(size: fontSize))
  }

  private func calendarLegendItem(
    label: LocalizedStringKey,
    severity: Int
  ) -> some View {
    HStack(spacing: 7) {
      severityCircle(hasRecords: true, severity: severity, diameter: 20)
        .frame(width: 30, height: 24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
      }
      Text(label)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .accessibilityElement(children: .combine)
  }

  private func periodButton(
    label: String,
    records values: [SymptomRecord],
    action: @escaping () -> Void
  ) -> some View {
    let severity = values.map(\.nSeverity).max() ?? 0
    // 発症件数は他の症状分析と同じく軽い以上（1 < nSeverity）だけを数える。
    // 「なし」と外部取り込みの「未指定」は件数に入れず、円（最大程度）にだけ残す
    let onsetCount = values.filter { 1 < $0.nSeverity }.count
    return Button(action: action) {
      VStack(spacing: 0) {
        Text(label)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.55)
        // 年・月の下へ程度を置き、円の中央で件数を示す
        ZStack {
          severityCircle(hasRecords: !values.isEmpty, severity: severity, diameter: 38)
          if 0 < onsetCount {
            Text("\(onsetCount)")
              .font(.caption2.monospacedDigit().weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
          }
        }
        .frame(width: 38, height: 38)
      }
      .frame(maxWidth: .infinity, minHeight: 64)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
      .overlay {
        RoundedRectangle(cornerRadius: 9)
          .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private var calendarGridItems: [AnalysisCalendarGridItem] {
    var items = (0..<7).map { offset in
      let index = (calendar.firstWeekday - 1 + offset) % 7
      return AnalysisCalendarGridItem.weekday(
        index: offset,
        title: calendar.shortStandaloneWeekdaySymbols[index]
      )
    }
    let leadingDays =
      (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    items += (0..<leadingDays).map { .placeholder(index: $0) }
    let days = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<1
    items += days.compactMap { number in
      guard let date = calendar.date(byAdding: .day, value: number - 1, to: monthStart) else {
        return nil
      }
      return .day(number: number, date: date)
    }
    return items
  }

  private func monthDate(year: Int, month: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: 1))!
  }

  private func records(in start: Date, component: Calendar.Component) -> [SymptomRecord] {
    // 発症日時で数え、日をまたいで終息した記録を翌期間で重複させない
    guard start < Date() else { return [] }
    guard let end = calendar.date(byAdding: component, value: 1, to: start) else { return [] }
    let range = SymptomAnalysisRange(start: start, end: min(end, Date()))
    return records.filter { range.containsStart($0) }
  }

  private func yearRecords(_ year: Int) -> [SymptomRecord] {
    records(in: monthDate(year: year, month: 1), component: .year)
  }

  private func monthRecords(_ month: Date) -> [SymptomRecord] {
    records(in: month, component: .month)
  }

  private func dayRecords(_ day: Date) -> [SymptomRecord] {
    guard day <= Date() else { return [] }
    let end = min(Date(), calendar.date(byAdding: .day, value: 1, to: day)!)
    let range = SymptomAnalysisRange(start: day, end: end)
    return records.filter { range.containsStart($0) }
  }

  private func moveMonth(_ value: Int) {
    guard let target = calendar.date(byAdding: .month, value: value, to: monthStart) else { return }
    month = calendar.dateInterval(of: .month, for: target)?.start ?? target
  }

  /// 程度を色ではなく円の大きさで示す
  @ViewBuilder
  private func severityCircle(hasRecords: Bool, severity: Int, diameter: CGFloat) -> some View {
    if hasRecords {
      if severity == SymptomSeverity.unspecified.rawValue {
        Circle()
          .stroke(
            severityCircleColor(severity).opacity(0.75),
            style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
          )
          .frame(width: diameter * 0.88, height: diameter * 0.88)
      } else if severity == SymptomSeverity.notPresent.rawValue {
        Circle()
          .stroke(severityCircleColor(severity), lineWidth: 1.8)
          .frame(width: diameter * 0.88, height: diameter * 0.88)
      } else {
        Circle()
          .fill(severityCircleColor(severity).opacity(0.26))
          .overlay {
            Circle()
              .stroke(severityCircleColor(severity).opacity(0.8), lineWidth: 1)
          }
          .frame(
            width: diameter * severityCircleScale(severity),
            height: diameter * severityCircleScale(severity)
          )
      }
    } else {
      Color.clear.frame(width: diameter, height: diameter)
    }
  }

  /// なしと軽いは青、中くらいは黄、強いは赤で示す
  private func severityCircleColor(_ severity: Int) -> Color {
    SymptomSeverity(rawValue: severity)?.analysisColor ?? .secondary
  }

  private func severityCircleScale(_ severity: Int) -> CGFloat {
    switch severity {
    case SymptomSeverity.mild.rawValue: return 0.68
    case SymptomSeverity.moderate.rawValue: return 0.84
    case SymptomSeverity.severe.rawValue: return 0.88
    default: return 0.88
    }
  }
}

/// 症状カレンダーで選んだ1日の概要と記録内容を表示する
private struct AnalysisSymptomDayDetailView: View {
  let date: Date
  let records: [SymptomRecord]
  let symptomName: (String) -> String
  let onClose: () -> Void
  @State private var settings = AppSettings.shared
  private let calendar = Calendar.current

  private var sortedRecords: [SymptomRecord] {
    records.sorted { $0.startAt < $1.startAt }
  }

  private var highestSeverity: SymptomSeverity? {
    records.map(\.severity).max { $0.rawValue < $1.rawValue }
  }

  private var totalDuration: TimeInterval? {
    let values = records.compactMap(durationInSelectedDay)
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          summaryPanel
          if sortedRecords.isEmpty {
            ContentUnavailableView(
              "analysis.unrecorded",
              systemImage: "calendar.badge.exclamationmark"
            )
            .frame(maxWidth: .infinity, minHeight: 240)
          } else {
            Text("analysis.calendar.day.records")
              .font(.title3.weight(.bold))
              .padding(.horizontal, 4)
            ForEach(Array(sortedRecords.enumerated()), id: \.element.id) { index, record in
              recordCard(record, index: index)
            }
          }
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          // 大きな文字でも日付が画面を占有しないようインライン表示に固定する
          Text(date.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        ToolbarItem(placement: .cancellationAction) {
          Button(action: onClose) {
            // 共通シートと同じ左上の下向きボタンで閉じる
            Image(systemName: "chevron.down")
              .fontWeight(.semibold)
          }
          .accessibilityLabel(Text("action.close"))
        }
      }
    }
  }

  private var summaryPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("analysis.calendar.day.summary", systemImage: "chart.bar.doc.horizontal")
        .font(.headline)
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
        spacing: 8
      ) {
        summaryMetric(
          title: "analysis.calendar.day.recordCount",
          value: records.count.formatted(),
          systemImage: "number"
        )
        summaryMetric(
          title: "analysis.calendar.day.highestSeverity",
          value: highestSeverity.map { NSLocalizedString($0.labelKey, comment: "") } ?? "—",
          systemImage: "circle.inset.filled"
        )
        summaryMetric(
          title: "analysis.calendar.day.totalDuration",
          value: totalDuration.map { SymptomDurationFormatter.string(from: $0) } ?? "—",
          systemImage: "timer"
        )
      }
    }
    .padding()
    .background(Color.analysisSymptomPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func summaryMetric(
    title: LocalizedStringKey,
    value: String,
    systemImage: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: systemImage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Text(value)
        .font(.headline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .padding(10)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 11))
  }

  private func recordCard(_ record: SymptomRecord, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text("#\(index + 1)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          Text(symptomName(record.sSymptomID))
            .font(.title3.weight(.bold))
        }
        Spacer(minLength: 8)
        severityBadge(record.severity)
      }

      Divider()
      timeDetails(record)

      // 記録画面と同じく、直前の状況を対処より先に並べる
      let triggers = triggerNames(record)
      if !triggers.isEmpty {
        detailSection(title: "symptom.section.trigger", systemImage: "clock.arrow.circlepath") {
          let color: Color = record.triggerIDs == [TriggerCatalog.nothingComesToMindID]
            ? .blue : .purple
          tagGrid(triggers, color: color)
        }
      }

      let remedies = remedyNames(record)
      if !remedies.isEmpty {
        detailSection(title: "symptom.section.remedy", systemImage: "cross.case") {
          tagGrid(remedies, color: .accentColor)
        }
      }

      let environment = environmentLines(record)
      if !environment.isEmpty {
        detailSection(title: "environment.title", systemImage: "thermometer.medium") {
          // 屋外の値を1行目、室内・端末の値を2行目へまとめ、幅不足時は縮小する
          VStack(alignment: .leading, spacing: 4) {
            ForEach(environment.indices, id: \.self) { index in
              environment[index]
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
          }
        }
      }

      if !record.sNote.isEmpty {
        detailSection(title: "symptom.section.note", systemImage: "note.text") {
          Text(record.sNote)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(record.severity.analysisColor.opacity(0.22), lineWidth: 1)
    }
  }

  private func severityBadge(_ severity: SymptomSeverity) -> some View {
    Text(LocalizedStringKey(severity.labelKey))
      .font(.caption.weight(.bold))
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(severity.analysisColor.opacity(0.2), in: Capsule())
      .overlay {
        Capsule().stroke(severity.analysisColor.opacity(0.7), lineWidth: 1)
      }
  }

  private func timeDetails(_ record: SymptomRecord) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label {
        Text("symptom.startAt") + Text(verbatim: "  ") + Text(timestamp(record.startAt))
      } icon: {
        Image(systemName: "play.circle")
      }
      // 経過時間は終息（継続中）の右へ並べ、行数を抑える
      if let end = record.endAt {
        Label {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("symptom.endAt") + Text(verbatim: "  ") + Text(timestamp(end))
            durationLabel(record)
          }
        } icon: {
          Image(systemName: "stop.circle")
        }
      } else if record.bOngoing {
        Label {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("analysis.ongoing")
              .foregroundStyle(Color.accentColor)
            durationLabel(record)
          }
        } icon: {
          Image(systemName: "waveform.path")
            .foregroundStyle(Color.accentColor)
        }
      } else {
        Label("symptom.progress.finishedUnknown", systemImage: "smallcircle.filled.circle")
      }
    }
    .font(.subheadline)
  }

  private func detailSection<Content: View>(
    title: LocalizedStringKey,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func timestamp(_ value: Date) -> String {
    if calendar.isDate(value, inSameDayAs: date) {
      return value.formatted(date: .omitted, time: .shortened)
    }
    return value.formatted(date: .abbreviated, time: .shortened)
  }

  private func durationText(_ duration: TimeInterval, ongoing: Bool) -> String {
    let text = SymptomDurationFormatter.string(from: duration)
    guard ongoing else { return text }
    return String(format: NSLocalizedString("symptom.duration.ongoing", comment: ""), text)
  }

  private func durationInSelectedDay(_ record: SymptomRecord) -> TimeInterval? {
    guard let interval = calendar.dateInterval(of: .day, for: date) else { return nil }
    let start = max(record.startAt, interval.start)
    let rawEnd = record.endAt ?? (record.bOngoing ? Date() : nil)
    guard let rawEnd else { return nil }
    let end = min(rawEnd, interval.end)
    guard start < end else { return nil }
    return end.timeIntervalSince(start)
  }

  /// 可変グリッドで折り返し後の高さをカードへ確実に伝える
  private func tagGrid(_ names: [String], color: Color) -> some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 120), spacing: 6)],
      alignment: .leading,
      spacing: 6
    ) {
      ForEach(names, id: \.self) { name in
        Text(name)
          .font(.caption.weight(.medium))
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(color.opacity(0.12), in: Capsule())
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func triggerNames(_ record: SymptomRecord) -> [String] {
    let names = record.triggerIDs.map { id in
      (settings.triggerTags.tag(for: id) ?? SymptomTag(id: id)).triggerDisplayName
    }
    return names.isEmpty ? [String(localized: "trigger.select.unselected")] : names
  }

  private func remedyNames(_ record: SymptomRecord) -> [String] {
    record.medicineIDs.map { id in
      (settings.medicineTags.tag(for: id) ?? SymptomTag(id: id)).medicineDisplayName
    }
  }

  private func durationLabel(_ record: SymptomRecord) -> some View {
    Group {
      if let duration = record.duration {
        Text(verbatim: "(\(durationText(duration, ongoing: record.needsEnding)))")
          .foregroundStyle(.secondary)
      }
    }
  }

  /// 屋外の値はアイコンなし、室内・端末の値だけ由来が分かるアイコンを添える
  private func environmentLines(_ record: SymptomRecord) -> [Text] {
    var lines: [Text] = []
    var parts: [Text] = []
    var outdoor: [String] = []
    if record.bTempSet { outdoor.append(measurement(record.nTemp_10c, divisor: 10, unit: "℃")) }
    if record.bHumiditySet { outdoor.append("\(record.nHumidity_p)%") }
    if record.nPressure_10hpa != 0 {
      outdoor.append(measurement(record.nPressure_10hpa, divisor: 10, unit: "hPa"))
    }
    if !record.sWeatherPlace.isEmpty { outdoor.insert(record.sWeatherPlace, at: 0) }
    if !outdoor.isEmpty { lines.append(Text(verbatim: outdoor.joined(separator: "  "))) }

    var indoor: [String] = []
    if record.bIndoorTempSet {
      indoor.append(measurement(record.nIndoorTemp_10c, divisor: 10, unit: "℃"))
    }
    if record.bIndoorHumiditySet { indoor.append("\(record.nIndoorHumidity_p)%") }
    if !indoor.isEmpty {
      parts.append(Text(Image(systemName: "house")) + Text(verbatim: " " + indoor.joined(separator: "  ")))
    }

    if record.nDevicePressure_10hpa != 0 {
      let pressure = measurement(record.nDevicePressure_10hpa, divisor: 10, unit: "hPa")
      parts.append(Text(Image(systemName: "iphone")) + Text(verbatim: " " + pressure))
    }
    if let first = parts.first {
      lines.append(parts.dropFirst().reduce(first) { $0 + Text(verbatim: "   ") + $1 })
    }
    return lines
  }

  private func measurement(_ value: Int, divisor: Double, unit: String) -> String {
    let number = (Double(value) / divisor).formatted(
      .number.precision(.fractionLength(1))
    )
    return "\(number) \(unit)"
  }
}

private enum AnalysisPeriodicityStrength: Equatable {
  case regular
  case approximate
  case irregular
}

private struct AnalysisPeriodicityInsight {
  let typicalInterval: TimeInterval
  let lowerInterval: TimeInterval
  let upperInterval: TimeInterval
  let recordCount: Int
  let strength: AnalysisPeriodicityStrength
}

private struct AnalysisOnsetIntervalPoint: Identifiable {
  let id: Int
  let date: Date
  let interval: TimeInterval
}

private struct AnalysisSymptomFrequencyPanel: View {
  let records: [SymptomRecord]
  let range: SymptomAnalysisRange
  let symptomOptions: [AnalysisSymptomFilterOption]
  @Binding var selectedSymptom: AnalysisSymptomFilterOption

  private var selectedSymptomName: String? {
    selectedSymptom.id.isEmpty ? nil : selectedSymptom.title
  }
  private var canEstimatePeriodicity: Bool { selectedSymptomName != nil }

  private var affected: [SymptomRecord] {
    records.filter { range.containsStart($0) && 1 < $0.nSeverity }
  }

  private var intervalPoints: [AnalysisOnsetIntervalPoint] {
    let starts = affected.map(\.startAt).sorted()
    return starts.indices.dropFirst().compactMap { index in
      let interval = starts[index].timeIntervalSince(starts[index - 1])
      guard 0 < interval else { return nil }
      return AnalysisOnsetIntervalPoint(id: index, date: starts[index], interval: interval)
    }
  }

  /// 発症開始間隔の中央値とばらつきから、おおよその周期性を求める
  private var periodicity: AnalysisPeriodicityInsight? {
    guard 4 <= affected.count else { return nil }
    let intervals = intervalPoints.map(\.interval).sorted()
    guard 3 <= intervals.count else { return nil }

    let typical = percentile(intervals, fraction: 0.5)
    guard 0 < typical else { return nil }
    let deviations = intervals.map { abs($0 - typical) }.sorted()
    let relativeDeviation = percentile(deviations, fraction: 0.5) / typical
    let strength: AnalysisPeriodicityStrength
    if relativeDeviation <= 0.25 {
      strength = .regular
    } else if relativeDeviation <= 0.5 {
      strength = .approximate
    } else {
      strength = .irregular
    }
    return AnalysisPeriodicityInsight(
      typicalInterval: typical,
      lowerInterval: percentile(intervals, fraction: 0.25),
      upperInterval: percentile(intervals, fraction: 0.75),
      recordCount: affected.count,
      strength: strength
    )
  }

  private var chartUnit: TimeInterval {
    let typical = periodicity?.typicalInterval
      ?? percentile(intervalPoints.map(\.interval).sorted(), fraction: 0.5)
    return typical < 48 * 60 * 60 ? 60 * 60 : 24 * 60 * 60
  }

  private var chartUnitTitle: LocalizedStringKey {
    chartUnit == 60 * 60
      ? "analysis.periodicity.axisHours"
      : "analysis.periodicity.axisDays"
  }

  /// 横軸は最大4件へ間引き、日付ラベルが省略されるのを防ぐ
  private var periodicityXAxisDates: [Date] {
    let dates = intervalPoints.map(\.date)
    guard 4 < dates.count else { return dates }
    let lastIndex = dates.count - 1
    return (0..<4).map { position in
      let index = Int((Double(lastIndex) * Double(position) / 3).rounded())
      return dates[index]
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("analysis.trend").font(.headline)
      AnalysisSymptomTargetPicker(
        options: symptomOptions,
        selection: $selectedSymptom
      )
      Text("analysis.trend.help")
        .font(.footnote)
        .foregroundStyle(.secondary)
      periodicityPanel
      if canEstimatePeriodicity, !intervalPoints.isEmpty {
        periodicityChart
      }
      if affected.isEmpty { Text("analysis.noEpisodes").foregroundStyle(.secondary) }
    }
    .padding()
    .background(Color.analysisSymptomPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 16)
  }

  private var periodicityChart: some View {
    Chart {
      if let periodicity,
         let first = intervalPoints.first,
         let last = intervalPoints.last {
        // 中央50%の範囲を帯で示し、点の集まり具合を読みやすくする
        RectangleMark(
          xStart: .value("Start", first.date),
          xEnd: .value("End", last.date),
          yStart: .value("Lower", periodicity.lowerInterval / chartUnit),
          yEnd: .value("Upper", periodicity.upperInterval / chartUnit)
        )
        .foregroundStyle(Color.accentColor.opacity(0.1))
        RuleMark(y: .value("Median", periodicity.typicalInterval / chartUnit))
          .foregroundStyle(Color.accentColor)
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
          .annotation(position: .top, alignment: .leading) {
            Text(intervalText(periodicity.typicalInterval))
              .font(.caption2.weight(.semibold))
              .foregroundStyle(Color.accentColor)
          }
      }
      ForEach(intervalPoints) { point in
        LineMark(
          x: .value("Date", point.date),
          y: .value("Interval", point.interval / chartUnit)
        )
        .foregroundStyle(Color.accentColor.opacity(0.75))
        PointMark(
          x: .value("Date", point.date),
          y: .value("Interval", point.interval / chartUnit)
        )
        .foregroundStyle(Color.accentColor)
        .symbolSize(40)
      }
    }
    .chartXScale(range: .plotDimension(startPadding: 24, endPadding: 24))
    .chartXAxis {
      AxisMarks(values: periodicityXAxisDates) { value in
        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
        AxisTick()
        AxisValueLabel {
          if let date = value.as(Date.self) {
            // 年を省いた短い月日で全体を表示する
            Text(date, format: .dateTime.month(.defaultDigits).day(.defaultDigits))
              .font(.caption2)
          }
        }
      }
    }
    .chartYAxisLabel(chartUnitTitle)
    .chartYAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
    .frame(height: 240)
    .accessibilityLabel(Text("analysis.trend"))
  }

  private var periodicityPanel: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("analysis.periodicity.title", systemImage: "repeat")
        .font(.subheadline.weight(.semibold))
      Text(periodicityMessage)
        .font(.headline)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      if canEstimatePeriodicity, let periodicity {
        Label(
          String(
            format: NSLocalizedString("analysis.periodicity.basisFormat", comment: ""),
            periodicity.recordCount
          ),
          systemImage: "number"
        )
        if periodicity.strength != .irregular {
          Label(
            String(
              format: NSLocalizedString("analysis.periodicity.rangeFormat", comment: ""),
              intervalText(periodicity.lowerInterval),
              intervalText(periodicity.upperInterval)
            ),
            systemImage: "arrow.left.and.right"
          )
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var periodicityMessage: String {
    guard canEstimatePeriodicity else {
      return NSLocalizedString("analysis.periodicity.selectSymptom", comment: "")
    }
    guard let periodicity else {
      return NSLocalizedString("analysis.periodicity.insufficient", comment: "")
    }
    switch periodicity.strength {
    case .regular:
      guard let selectedSymptomName else { return "" }
      return String(
        format: NSLocalizedString("analysis.periodicity.regularFormat", comment: ""),
        selectedSymptomName,
        intervalText(periodicity.typicalInterval)
      )
    case .approximate:
      guard let selectedSymptomName else { return "" }
      return String(
        format: NSLocalizedString("analysis.periodicity.approximateFormat", comment: ""),
        selectedSymptomName,
        intervalText(periodicity.typicalInterval)
      )
    case .irregular:
      guard let selectedSymptomName else { return "" }
      return String(
        format: NSLocalizedString("analysis.periodicity.irregular", comment: ""),
        selectedSymptomName
      )
    }
  }

  private func intervalText(_ interval: TimeInterval) -> String {
    SymptomDurationFormatter.string(from: interval)
  }

  private func percentile(_ sortedValues: [TimeInterval], fraction: Double) -> TimeInterval {
    guard 0 < sortedValues.count else { return 0 }
    let position = fraction * Double(sortedValues.count - 1)
    let lowerIndex = Int(position.rounded(.down))
    let upperIndex = Int(position.rounded(.up))
    guard lowerIndex != upperIndex else { return sortedValues[lowerIndex] }
    let progress = position - Double(lowerIndex)
    return sortedValues[lowerIndex]
      + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * progress
  }
}

/// 症状との関係を比較する環境項目
private enum AnalysisEnvironmentMetric: String, CaseIterable, Identifiable {
  case outdoorTemp
  case outdoorHumidity
  case pressure
  case pressureDelta
  case indoorTemp
  case indoorHumidity
  case devicePressure

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .outdoorTemp: return "analysis.environment.metric.outdoorTemp"
    case .outdoorHumidity: return "analysis.environment.metric.outdoorHumidity"
    case .pressure: return "analysis.environment.metric.stationPressure"
    case .pressureDelta: return "analysis.environment.metric.pressureDelta"
    case .indoorTemp: return "analysis.environment.metric.indoorTemp"
    case .indoorHumidity: return "analysis.environment.metric.indoorHumidity"
    case .devicePressure: return "analysis.environment.metric.devicePressure"
    }
  }

  var unit: String {
    switch self {
    case .outdoorTemp, .indoorTemp: return "℃"
    case .outdoorHumidity, .indoorHumidity: return "%"
    case .pressure, .pressureDelta, .devicePressure: return "hPa"
    }
  }

  /// 項目ごとの見やすい集計幅
  var binWidth: Double {
    switch self {
    case .outdoorTemp: return 5
    case .outdoorHumidity: return 10
    case .pressure: return 5
    case .pressureDelta: return 2
    case .indoorTemp: return 2
    case .indoorHumidity: return 10
    case .devicePressure: return 5
    }
  }

  func value(in environment: EnvironmentSnapshot) -> Double? {
    switch self {
    case .outdoorTemp:
      return environment.isTempSet ? Double(environment.temp_10c) / 10 : nil
    case .outdoorHumidity:
      return environment.isHumiditySet ? Double(environment.humidity_p) : nil
    case .pressure:
      return 0 < environment.pressure_10hpa ? Double(environment.pressure_10hpa) / 10 : nil
    case .pressureDelta:
      return environment.isPressureDelta24hSet
        ? Double(environment.pressureDelta24h_10hpa) / 10 : nil
    case .indoorTemp:
      return environment.isIndoorTempSet ? Double(environment.indoorTemp_10c) / 10 : nil
    case .indoorHumidity:
      return environment.isIndoorHumiditySet ? Double(environment.indoorHumidity_p) : nil
    case .devicePressure:
      return 0 < environment.devicePressure_10hpa
        ? Double(environment.devicePressure_10hpa) / 10 : nil
    }
  }
}

private struct AnalysisEnvironmentSample {
  let value: Double
  let severity: SymptomSeverity
}

private struct AnalysisEnvironmentSeverityBucket: Identifiable {
  let lower: Double
  let count: Int
  let severity: SymptomSeverity
  /// 同じ範囲で下に積まれた程度の件数合計
  let stackedBelow: Int
  var id: String { "\(lower)-\(severity.rawValue)" }
}

private struct AnalysisEnvironmentMetricSamples {
  let metric: AnalysisEnvironmentMetric
  let samples: [AnalysisEnvironmentSample]
}

private struct AnalysisSymptomEnvironmentPanel: View {
  let symptomRecords: [SymptomRecord]
  let range: SymptomAnalysisRange
  let symptomOptions: [AnalysisSymptomFilterOption]
  @Binding var selectedSymptom: AnalysisSymptomFilterOption
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  private let onsetSeverities: [SymptomSeverity] = [.mild, .moderate, .severe]

  /// 期間内に発症した記録（程度「なし」を除く）
  private var onsetRecords: [SymptomRecord] {
    symptomRecords.filter { range.containsStart($0) && 1 < $0.nSeverity }
  }

  /// 項目を選ぶ手間を省き、記録がある環境項目をすべて並べる
  private var metricSamples: [AnalysisEnvironmentMetricSamples] {
    let records = onsetRecords
    return AnalysisEnvironmentMetric.allCases.compactMap { metric -> AnalysisEnvironmentMetricSamples? in
      let samples = records.compactMap { record -> AnalysisEnvironmentSample? in
        guard let value = metric.value(in: record.environmentSnapshot) else { return nil }
        return AnalysisEnvironmentSample(value: value, severity: record.severity)
      }
      return samples.isEmpty ? nil : AnalysisEnvironmentMetricSamples(metric: metric, samples: samples)
    }
  }

  /// 大きな文字では1列にして軸の数値を読みやすくする
  private var columnCount: Int {
    DynamicTypeSize.accessibility1 <= dynamicTypeSize ? 1 : 2
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("analysis.symptomEnvironment").font(.headline)
      AnalysisSymptomTargetPicker(
        options: symptomOptions,
        selection: $selectedSymptom
      )

      let items = metricSamples
      if items.isEmpty {
        ContentUnavailableView(
          "analysis.environment.noData",
          systemImage: "chart.bar.xaxis"
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount),
          alignment: .leading,
          spacing: 16
        ) {
          ForEach(items, id: \.metric) { item in
            AnalysisEnvironmentMiniChart(
              metric: item.metric,
              samples: item.samples,
              severities: onsetSeverities
            )
          }
        }
        chartLegend
      }

      Text("analysis.environment.note")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(Color.analysisSymptomPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 16)
  }

  private var chartLegend: some View {
    AZFlowLayout(spacing: 10, rowSpacing: 6, alignment: .leading) {
      ForEach(onsetSeverities) { severity in
        HStack(spacing: 5) {
          RoundedRectangle(cornerRadius: 2)
            .fill(severity.analysisEnvironmentColor.opacity(0.82))
            .frame(width: 10, height: 10)
          Text(LocalizedStringKey(severity.labelKey)).font(.caption)
        }
      }
    }
  }
}

/// 1つの環境項目について、範囲ごとの発症件数を程度別に積み上げた縦棒で示す
private struct AnalysisEnvironmentMiniChart: View {
  let metric: AnalysisEnvironmentMetric
  let samples: [AnalysisEnvironmentSample]
  let severities: [SymptomSeverity]

  private var buckets: [AnalysisEnvironmentSeverityBucket] {
    let lowers = Set(samples.map { bucketLower($0.value) }).sorted()
    var buckets: [AnalysisEnvironmentSeverityBucket] = []
    for lower in lowers {
      // 軽い→強いの順に下から積み上げる
      var stacked = 0
      for severity in severities {
        let count = samples.filter {
          bucketLower($0.value) == lower && $0.severity == severity
        }.count
        guard 0 < count else { continue }
        buckets.append(AnalysisEnvironmentSeverityBucket(
          lower: lower,
          count: count,
          severity: severity,
          stackedBelow: stacked
        ))
        stacked += count
      }
    }
    return buckets
  }

  private var firstLower: Double { buckets.map(\.lower).min() ?? 0 }
  private var xDomainUpper: Double { (buckets.map(\.lower).max() ?? 0) + metric.binWidth }

  /// 空の範囲も含めた境界値を、狭い幅でも重ならない本数に間引いて目盛りにする
  private var axisValues: [Double] {
    let count = Int(((xDomainUpper - firstLower) / metric.binWidth).rounded())
    let values = (0...max(count, 1)).map { firstLower + Double($0) * metric.binWidth }
    let step = max(1, Int((Double(values.count) / 4).rounded(.up)))
    return values.enumerated().filter { $0.offset.isMultiple(of: step) }.map(\.element)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(LocalizedStringKey(metric.titleKey))
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Spacer(minLength: 2)
        Text(verbatim: metric.unit)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize()
      }
      Chart {
        ForEach(buckets) { bucket in
          // 横軸を環境値の数値軸にし、範囲の幅どおりの縦棒で件数を示す
          RectangleMark(
            xStart: .value(metric.titleKey, bucket.lower + metric.binWidth * 0.06),
            xEnd: .value(metric.titleKey, bucket.lower + metric.binWidth * 0.94),
            yStart: .value("analysis.environment.onsetCount", bucket.stackedBelow),
            yEnd: .value("analysis.environment.onsetCount", bucket.stackedBelow + bucket.count)
          )
          .foregroundStyle(bucket.severity.analysisEnvironmentColor.opacity(0.82))
        }
      }
      .chartXScale(domain: firstLower...xDomainUpper)
      .chartXAxis {
        AxisMarks(values: axisValues) { value in
          AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
          AxisTick()
          AxisValueLabel {
            if let number = value.as(Double.self) {
              Text(number.formatted(.number.precision(.fractionLength(0...1))))
                .font(.caption2)
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
          AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
          AxisValueLabel {
            if let count = value.as(Int.self) {
              Text(count.formatted())
                .font(.caption2)
            }
          }
        }
      }
      .frame(height: 130)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(LocalizedStringKey(metric.titleKey)))
  }

  private func bucketLower(_ value: Double) -> Double {
    floor(value / metric.binWidth) * metric.binWidth
  }
}

private struct AnalysisTriggerRow: Identifiable {
  /// 状況のタグID。未選択の行は固定IDを使う
  let id: String
  let name: String
  /// 程度ごとの件数（軽い→強い）。未選択の行は程度で分けず1区分にする
  let segments: [(color: Color, count: Int)]
  /// 未選択の行は同数時に最後へ並べる
  let isUnselected: Bool
  var total: Int { segments.reduce(0) { $0 + $1.count } }
}

/// 発症の直前に記録した状況を、状況ごとの件数（程度別の積み上げ）で示す
private struct AnalysisSymptomTriggerPanel: View {
  let symptomRecords: [SymptomRecord]
  let range: SymptomAnalysisRange
  let symptomOptions: [AnalysisSymptomFilterOption]
  @Binding var selectedSymptom: AnalysisSymptomFilterOption
  @State private var settings = AppSettings.shared
  private let onsetSeverities: [SymptomSeverity] = [.mild, .moderate, .severe]

  /// 期間内に発症した記録（程度「なし」を除く）
  private var onsetRecords: [SymptomRecord] {
    symptomRecords.filter { range.containsStart($0) && 1 < $0.nSeverity }
  }

  /// 状況ごとの件数。名前は ID から引き、多い順に並べる
  private var rows: [AnalysisTriggerRow] {
    var counts: [String: [SymptomSeverity: Int]] = [:]
    for record in onsetRecords {
      for id in Set(record.triggerIDs) {
        counts[id, default: [:]][record.severity, default: 0] += 1
      }
    }
    var result: [AnalysisTriggerRow] = counts.map { id, bySeverity in
      AnalysisTriggerRow(
        id: id,
        name: name(id),
        segments: onsetSeverities.compactMap { severity -> (color: Color, count: Int)? in
          guard let count = bySeverity[severity], 0 < count else { return nil }
          return (severity.analysisEnvironmentColor.opacity(0.82), count)
        },
        isUnselected: false
      )
    }
    // タグが無い記録だけを未選択として別の行にする
    let unselectedCount = onsetRecords.filter { $0.triggerIDs.isEmpty }.count
    if 0 < unselectedCount {
      result.append(AnalysisTriggerRow(
        id: "unselected",
        name: String(localized: "trigger.select.unselected"),
        segments: [(.secondary.opacity(0.22), unselectedCount)],
        isUnselected: true
      ))
    }
    // 件数の降順。同数ならタグを先にし、未選択は最後へ回す
    return result.sorted { lhs, rhs in
      if lhs.total != rhs.total { return rhs.total < lhs.total }
      if lhs.isUnselected != rhs.isUnselected { return rhs.isUnselected }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("analysis.trigger").font(.headline)
      AnalysisSymptomTargetPicker(
        options: symptomOptions,
        selection: $selectedSymptom
      )

      let values = rows
      if values.isEmpty {
        ContentUnavailableView(
          "analysis.trigger.noData",
          systemImage: "clock.arrow.circlepath"
        )
        .frame(maxWidth: .infinity, minHeight: 200)
      } else {
        triggerBars(values)
        chartLegend
      }

      Text("analysis.trigger.note")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(Color.analysisSymptomPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 16)
  }

  /// 項目数に関係なく同じ太さで並べるため、Chart の軸に任せず1行ずつ組む。
  /// 棒の長さは最多の状況を幅いっぱいとした比で、件数は行の右端に数字で出す
  private func triggerBars(_ values: [AnalysisTriggerRow]) -> some View {
    let maxTotal = max(values.map(\.total).max() ?? 1, 1)
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(values) { row in
        // 項目の区切りが分かるよう、2項目目から上に区切り線を引く
        if row.id != values.first?.id {
          Divider()
        }
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline) {
            Text(row.name)
              .font(.subheadline)
              .lineLimit(1)
            Spacer(minLength: 8)
            Text(row.total.formatted())
              .font(.subheadline.monospacedDigit().weight(.semibold))
              .foregroundStyle(.secondary)
          }
          GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(row.total) / CGFloat(maxTotal)
            HStack(spacing: 0) {
              ForEach(Array(row.segments.enumerated()), id: \.offset) { _, segment in
                Rectangle()
                  .fill(segment.color)
                  .frame(width: width * CGFloat(segment.count) / CGFloat(max(row.total, 1)))
              }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
          }
          .frame(height: 16)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
      }
    }
  }

  private var chartLegend: some View {
    AZFlowLayout(spacing: 10, rowSpacing: 6, alignment: .leading) {
      ForEach(onsetSeverities) { severity in
        HStack(spacing: 5) {
          RoundedRectangle(cornerRadius: 2)
            .fill(severity.analysisEnvironmentColor.opacity(0.82))
            .frame(width: 10, height: 10)
          Text(LocalizedStringKey(severity.labelKey)).font(.caption)
        }
      }
    }
  }

  private func name(_ id: String) -> String {
    (settings.triggerTags.tag(for: id) ?? SymptomTag(id: id)).triggerDisplayName
  }
}

private extension SymptomSeverity {
  /// 発症と環境の積み上げ棒で使う程度の色
  var analysisEnvironmentColor: Color {
    switch self {
    case .notPresent: return .gray
    case .mild: return .green
    case .moderate: return .orange
    case .severe: return .red
    case .unspecified: return .secondary
    }
  }
}

private enum AnalysisLayoutDestination: Int, CaseIterable, Identifiable {
  case page1 = 1
  case page2 = 2
  case page3 = 3
  case hidden = 4

  var id: Int { rawValue }

  init(page: AnalysisPage) {
    self = AnalysisLayoutDestination(rawValue: page.rawValue) ?? .page1
  }

  var page: AnalysisPage? {
    switch self {
    case .page1: return .one
    case .page2: return .two
    case .page3: return .three
    case .hidden: return nil
    }
  }

  /// 図表ごとの移動先として選べる配置先
  static let placementCases: [AnalysisLayoutDestination] = [.page1, .page2, .page3, .hidden]
}

struct AnalysisLayoutSettingsView: View {
  var initialPage: AnalysisPage = .one
  var isModal = false
  @State private var settings = AppSettings.shared
  @State private var selectedDestination: AnalysisLayoutDestination
  @State private var expandedPanel: AnalysisPanelID?
  @State private var showDetails = false
  @FocusState private var isPageNameFocused: Bool
  @Environment(\.dismiss) private var dismiss

  init(initialPage: AnalysisPage = .one, isModal: Bool = false) {
    self.initialPage = initialPage
    self.isModal = isModal
    _selectedDestination = State(initialValue: AnalysisLayoutDestination(page: initialPage))
  }

  var body: some View {
    List {
      Section {
        AZRadioPicker(
          options: AnalysisLayoutDestination.allCases,
          selection: $selectedDestination,
          minOptionWidth: 0,
          maxOptionWidth: 120,
          horizontalPadding: 12,
          verticalPadding: 8,
          optionSpacing: 4,
          groupPadding: 2,
          wrapsOptions: false,
          fillsWidth: true
        ) { destination in
          if let page = destination.page {
            // 初心者には番号アイコンの意味を分析名でも示す
            VStack(spacing: 2) {
              Image(systemName: page.tabSymbol)
              if settings.userLevel == .beginner {
                Text(page.displayTitle(in: settings.analysisLayout))
                  .font(.caption)
              }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(page.accessibilityTitle(in: settings.analysisLayout))
          } else {
            // 初心者には非表示アイコンの意味を文字でも明記する
            VStack(spacing: 2) {
              Image(systemName: "eye.slash")
              if settings.userLevel == .beginner {
                Text("analysis.layout.hidden")
                  .font(.caption)
              }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("analysis.layout.hidden"))
          }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
      }

      Section {
        ForEach(selectedPanels) { panel in
          panelRow(panel)
            .moveDisabled(selectedDestination == .hidden)
        }
        .onMove(perform: movePanels)
      } header: {
        HStack(spacing: 4) {
          if let page = selectedDestination.page {
            // 選択中ページの名称を図表一覧の見出しで直接編集する
            TextField(page.numberedTitle, text: pageNameBinding(for: page))
              .textFieldStyle(.plain)
              .lineLimit(1)
              .submitLabel(.done)
              .focused($isPageNameFocused)
              .accessibilityLabel(Text("analysis.page.names"))
          } else {
            Text("analysis.layout.hidden")
          }
          // 配置ヘルプは利用レベルにかかわらずアイコンから確認できる
          BeginnerHelpBanner(
            "analysis.layout.help",
            storageKey: "helpDismissed.analysisLayout",
            compact: true,
            tight: true
          )
        }
        .accessibilityElement(children: .contain)
      }
      .environment(\.editMode, .constant(.active))

    }
    .onChange(of: selectedDestination) { _, _ in
      // ページを切り替えたら名称編集を終える
      isPageNameFocused = false
    }
    .navigationTitle("analysis.layout.title")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $showDetails) {
      GraphSettingsView(showsLayout: false)
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        // Labelの省略を避け、画面タイトルにアイコンと文字を必ず表示する
        HStack(spacing: 4) {
          Image(systemName: "text.pad.header")
          Text("analysis.layout.title")
        }
        .font(.headline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("analysis.layout.title"))
      }
      if isModal {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "chevron.down").fontWeight(.semibold)
          }
          .accessibilityLabel(Text("action.close"))
        }
      }
      ToolbarItem(placement: .primaryAction) {
        // 配置先セレクタから独立した詳細設定ボタンを右上に置く
        Button {
          showDetails = true
        } label: {
          ToolbarButtonLabel(
            systemImage: "ellipsis.calendar",
            captionKey: "analysis.details.shortTitle"
          )
        }
        .accessibilityLabel(Text("analysis.details.title"))
      }
    }
  }

  private var selectedPanels: [AnalysisPanelID] {
    if let page = selectedDestination.page {
      return settings.analysisLayout.visiblePanels(in: page)
    }
    return settings.analysisLayout.hiddenPanels
  }

  /// ページ名の変更を配置設定と一緒に保存する
  private func pageNameBinding(for page: AnalysisPage) -> Binding<String> {
    Binding(
      get: { settings.analysisLayout.pageNameInput(in: page) },
      set: { newName in
        var layout = settings.analysisLayout
        layout.setPageName(newName, in: page)
        settings.analysisLayout = layout
      }
    )
  }

  private func panelRow(_ panel: AnalysisPanelID) -> some View {
    HStack(spacing: 12) {
      Text(LocalizedStringKey(panel.titleKey))
      Spacer()
      AZDropdownPicker(
        options: AnalysisLayoutDestination.placementCases,
        selection: Binding(
          get: { selectedDestination },
          set: { destination in
            if destination != selectedDestination { move(panel, to: destination) }
          }
        ),
        isExpanded: Binding(
          get: { expandedPanel == panel },
          set: { isExpanded in expandedPanel = isExpanded ? panel : nil }
        ),
        minWidth: 56
      ) { destination in
        if let page = destination.page {
          // 閉じた状態と候補で分析タブと同じアイコンを使う
          Image(systemName: page.tabSymbol)
            .accessibilityLabel(page.accessibilityTitle(in: settings.analysisLayout))
        } else {
          // 各行では幅を取らないよう非表示をアイコンだけで示す
          Image(systemName: "eye.slash")
            .accessibilityLabel(Text("analysis.layout.hidden"))
        }
      }
    }
  }

  private func move(_ panel: AnalysisPanelID, to destination: AnalysisLayoutDestination) {
    var layout = settings.analysisLayout
    if let page = destination.page {
      layout.move(panel, to: page)
    } else {
      layout.moveToHidden(panel)
    }
    settings.analysisLayout = layout
  }

  private func movePanels(from source: IndexSet, to destination: Int) {
    guard let page = selectedDestination.page else { return }
    var layout = settings.analysisLayout
    var visible = layout.visiblePanels(in: page)
    visible.move(fromOffsets: source, toOffset: destination)
    var iterator = visible.makeIterator()
    let panels = layout.panels(in: page).map { panel in
      layout.hidden.contains(panel) ? panel : iterator.next() ?? panel
    }
    layout.setPanels(panels, in: page)
    settings.analysisLayout = layout
  }

}
