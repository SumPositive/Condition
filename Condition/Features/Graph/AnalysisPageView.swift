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
  @State private var isSymptomFilterExpanded = false
  @State private var showSettings = false
  @State private var isExporting = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var period: GraphPeriod { settings.analysisLayout.period(in: page) }
  private var visiblePanels: [AnalysisPanelID] { settings.analysisLayout.visiblePanels(in: page) }
  private var hasSymptomPanel: Bool { visiblePanels.contains(where: \.isSymptomPanel) }

  /// 削除済みの症状IDが保存されている場合は「すべて」として扱う
  private var selectedSymptomID: String {
    let saved = settings.analysisSymptomFilter(in: page)
    return symptomIDs.contains(saved) ? saved : ""
  }

  /// AZPickerで表示する「すべて」と症状名の選択肢
  private var symptomFilterOptions: [AnalysisSymptomFilterOption] {
    [AnalysisSymptomFilterOption(id: "", title: String(localized: "analysis.all"))]
      + symptomIDs.map { AnalysisSymptomFilterOption(id: $0, title: symptomName($0)) }
  }

  private var selectedSymptomFilterOption: AnalysisSymptomFilterOption {
    symptomFilterOptions.first { $0.id == selectedSymptomID } ?? symptomFilterOptions[0]
  }

  private var symptomFilterBinding: Binding<AnalysisSymptomFilterOption> {
    Binding(
      get: { selectedSymptomFilterOption },
      set: { settings.setAnalysisSymptomFilter($0.id, in: page) }
    )
  }

  private var symptomFilterPickerStyle: AZPickerStyle {
    var style = AZPickerStyle.form
    // 選択式であることが閉じた状態でも分かるよう山型を表示する
    style.dropdownIndicator = .chevron
    return style
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
    Set(symptomRecords.map(\.sSymptomID).filter { !$0.isEmpty }).sorted {
      symptomName($0).localizedStandardCompare(symptomName($1)) == .orderedAscending
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
            if hasSymptomPanel { symptomFilter }
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
          Text(page.displayTitle)
            .font(.headline)
            .accessibilityLabel(page.accessibilityTitle)
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
    page.displayTitle
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
      wrapsOptions: DynamicTypeSize.xxxLarge <= dynamicTypeSize,
      fillsWidth: dynamicTypeSize < DynamicTypeSize.xxxLarge
    ) { value in
      Text(LocalizedStringKey(value.shortLabel))
    }
    .padding(.bottom, 8)
  }

  private var symptomFilter: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("analysis.symptomTarget")
        .font(.headline)
      AZDropdownPicker(
        options: symptomFilterOptions,
        selection: symptomFilterBinding,
        isExpanded: $isSymptomFilterExpanded,
        minWidth: 180,
        fillsWidth: true,
        style: symptomFilterPickerStyle
      ) { option in
        Text(option.title)
      }
      Text("analysis.symptomTargetAppliesToPage")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Divider()
      if symptomRecords.contains(where: { $0.sWeatherSourceURL == "vitalin-demo://symptoms" }) {
        Label("analysis.demo", systemImage: "info.circle")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Text("analysis.recordNote")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color.analysisSymptomPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 16)
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
          records: filteredSymptomRecords,
          name: symptomName
        )
      case .symptomFrequency:
        AnalysisSymptomFrequencyPanel(
          records: filteredSymptomRecords,
          range: symptomRange
        )
      case .symptomSummary:
        AnalysisSymptomEnvironmentPanel(
          symptomRecords: filteredSymptomRecords,
          allSymptomRecords: symptomRecords,
          bodyRecords: targetBodyRecords,
          range: symptomRange,
        )
      default:
        EmptyView()
      }
    }
  }

  private var filteredSymptomRecords: [SymptomRecord] {
    symptomRecords.filter {
      (selectedSymptomID.isEmpty || $0.sSymptomID == selectedSymptomID) && $0.startAt <= Date()
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

private struct AnalysisSymptomBucket: Identifiable {
  let date: Date
  let count: Int
  var id: Date { date }
}

/// 症状絞り込み用AZPickerの選択肢
private struct AnalysisSymptomFilterOption: Identifiable, Hashable {
  let id: String
  let title: String
}

private extension Color {
  /// 症状選択シートと同じ青みを使う分析パネル背景
  static var analysisSymptomPanelBackground: Color {
    .azTintedSheetBackground(.tintColor)
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
    VStack(spacing: 12) {
      Text("analysis.calendar").font(.headline)
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
        NavigationStack {
          List {
            ForEach(dayRecords(selectedDay)) { record in
              VStack(alignment: .leading, spacing: 6) {
                Text(name(record.sSymptomID)).font(.headline)
                Text(LocalizedStringKey(record.severity.labelKey))
                Text(record.startAt.formatted(date: .abbreviated, time: .shortened))
                  .font(.footnote)
                if let end = record.endAt {
                  Text(end.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                } else if record.bOngoing {
                  Text("analysis.ongoing").font(.footnote)
                }
                if !record.sNote.isEmpty { Text(record.sNote).font(.footnote) }
              }
            }
            if dayRecords(selectedDay).isEmpty { Text("analysis.unrecorded") }
          }
          .navigationTitle(selectedDay.formatted(date: .abbreviated, time: .omitted))
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("action.close") { self.selectedDay = nil }
            }
          }
        }
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
        columns: [GridItem(.adaptive(minimum: periodCellMinimumWidth), spacing: 8)],
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
      Text("analysis.legend")
        .font(.caption)
        .foregroundStyle(.secondary)
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
    return Button(action: action) {
      HStack(spacing: 6) {
        ZStack {
          severityCircle(hasRecords: !values.isEmpty, severity: severity, diameter: 44)
          Text(label)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .frame(width: 48, height: 48)
        if !values.isEmpty {
          Text("\(values.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 48)
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
    // 未来の期間には継続中の記録を表示しない
    guard start < Date() else { return [] }
    guard let end = calendar.date(byAdding: component, value: 1, to: start) else { return [] }
    let range = SymptomAnalysisRange(start: start, end: min(end, Date()))
    return records.filter { range.overlaps($0) }
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
    return records.filter { range.overlaps($0) }
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
          .stroke(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
          .frame(width: diameter * 0.88, height: diameter * 0.88)
      } else if severity == SymptomSeverity.notPresent.rawValue {
        Circle()
          .stroke(Color.primary, lineWidth: 1.8)
          .frame(width: diameter * 0.88, height: diameter * 0.88)
      } else {
        Circle()
          .fill(Color.primary.opacity(0.16))
          .frame(
            width: diameter * severityCircleScale(severity),
            height: diameter * severityCircleScale(severity)
          )
      }
    } else {
      Color.clear.frame(width: diameter, height: diameter)
    }
  }

  private func severityCircleScale(_ severity: Int) -> CGFloat {
    switch severity {
    case SymptomSeverity.mild.rawValue: return 0.68
    case SymptomSeverity.moderate.rawValue: return 0.84
    case SymptomSeverity.severe.rawValue: return 1
    default: return 0.88
    }
  }
}

private struct AnalysisSymptomFrequencyPanel: View {
  let records: [SymptomRecord]
  let range: SymptomAnalysisRange
  @State private var monthly = false
  private let calendar = Calendar.current

  private var affected: [SymptomRecord] {
    records.filter { range.containsStart($0) && 1 < $0.nSeverity }
  }

  private var buckets: [AnalysisSymptomBucket] {
    let component: Calendar.Component = monthly ? .month : .weekOfYear
    var date = calendar.dateInterval(of: component, for: range.start)!.start
    var result: [AnalysisSymptomBucket] = []
    while date < range.end {
      let next = calendar.date(byAdding: component, value: 1, to: date)!
      result.append(
        AnalysisSymptomBucket(
          date: date,
          count: affected.filter { date <= $0.startAt && $0.startAt < next }.count
        ))
      date = next
    }
    return result
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("analysis.trend").font(.headline)
      Picker("analysis.interval", selection: $monthly) {
        Text("analysis.weekly").tag(false)
        Text("analysis.monthly").tag(true)
      }
      .pickerStyle(.segmented)
      Chart(buckets) { bucket in
        BarMark(
          x: .value("Date", bucket.date, unit: monthly ? .month : .weekOfYear),
          y: .value("Count", bucket.count)
        )
      }
      .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
      .frame(height: 220)
      if affected.isEmpty { Text("analysis.noEpisodes").foregroundStyle(.secondary) }
    }
    .padding()
    .background(Color.analysisSymptomPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 16)
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

  func axisText(_ value: Double) -> String {
    switch self {
    case .outdoorHumidity, .indoorHumidity:
      return String(format: "%.0f", value)
    default:
      return String(format: "%.1f", value)
    }
  }
}

private struct AnalysisEnvironmentSample {
  let value: Double
  let severity: SymptomSeverity
}

private struct AnalysisEnvironmentSeverityBucket: Identifiable {
  let lower: Double
  let center: Double
  let proportion: Double
  let severity: SymptomSeverity
  var id: String { "\(lower)-\(severity.rawValue)" }
}

private struct AnalysisEnvironmentReferenceBucket: Identifiable {
  let lower: Double
  let center: Double
  let proportion: Double
  var id: Double { lower }
}

private struct AnalysisSymptomEnvironmentPanel: View {
  let symptomRecords: [SymptomRecord]
  let allSymptomRecords: [SymptomRecord]
  let bodyRecords: [BodyRecord]
  let range: SymptomAnalysisRange
  @State private var metric = AnalysisEnvironmentMetric.pressure
  @State private var isMetricExpanded = false

  private var metricPickerStyle: AZPickerStyle {
    var style = AZPickerStyle.form
    // 環境項目を変更できることが閉じた状態でも分かるよう山型を表示する
    style.dropdownIndicator = .chevron
    return style
  }

  private var symptomSamples: [AnalysisEnvironmentSample] {
    symptomRecords.compactMap { record in
      guard range.containsStart(record), record.severity.isCountable,
            let value = metric.value(in: record.environmentSnapshot)
      else { return nil }
      return AnalysisEnvironmentSample(value: value, severity: record.severity)
    }
  }

  private var referenceValues: [Double] {
    let measurementValues = bodyRecords.compactMap {
      metric.value(in: $0.environmentSnapshot)
    }
    let symptomValues = allSymptomRecords.compactMap { record -> Double? in
      guard range.containsStart(record) else { return nil }
      return metric.value(in: record.environmentSnapshot)
    }
    return measurementValues + symptomValues
  }

  private var symptomBuckets: [AnalysisEnvironmentSeverityBucket] {
    guard !symptomSamples.isEmpty else { return [] }
    let lowers = Set(symptomSamples.map { bucketLower($0.value) }).sorted()
    let total = Double(symptomSamples.count)
    return lowers.flatMap { lower in
      SymptomSeverity.selectableCases.compactMap { severity in
        let count = symptomSamples.filter {
          bucketLower($0.value) == lower && $0.severity == severity
        }.count
        guard 0 < count else { return nil }
        return AnalysisEnvironmentSeverityBucket(
          lower: lower,
          center: lower + metric.binWidth / 2,
          proportion: Double(count) / total,
          severity: severity
        )
      }
    }
  }

  private var referenceBuckets: [AnalysisEnvironmentReferenceBucket] {
    guard !referenceValues.isEmpty else { return [] }
    let lowers = Set(referenceValues.map(bucketLower)).sorted()
    let total = Double(referenceValues.count)
    return lowers.map { lower in
      AnalysisEnvironmentReferenceBucket(
        lower: lower,
        center: lower + metric.binWidth / 2,
        proportion: Double(referenceValues.filter { bucketLower($0) == lower }.count) / total
      )
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("analysis.symptomEnvironment").font(.headline)
      HStack {
        Text("analysis.environment.metric")
          .font(.subheadline)
        Spacer()
        // 横軸の単位をプルダウンの近くへ固定して読み違いを防ぐ
        Text(metric.unit)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      AZDropdownPicker(
        options: AnalysisEnvironmentMetric.allCases,
        selection: $metric,
        isExpanded: $isMetricExpanded,
        minWidth: 180,
        fillsWidth: true,
        style: metricPickerStyle
      ) { item in
        Text(LocalizedStringKey(item.titleKey))
      }

      if symptomSamples.isEmpty {
        ContentUnavailableView(
          "analysis.environment.noData",
          systemImage: "chart.bar.xaxis"
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        environmentChart
        chartLegend
        Text(
          String(
            format: String(localized: "analysis.environment.coverageFormat"),
            symptomSamples.count,
            referenceValues.count
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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

  private var environmentChart: some View {
    Chart {
      ForEach(symptomBuckets) { bucket in
        BarMark(
          x: .value(metric.titleKey, bucket.center),
          y: .value("analysis.environment.share", bucket.proportion),
          stacking: .standard
        )
        .foregroundStyle(severityColor(bucket.severity).opacity(0.82))
      }
      ForEach(referenceBuckets) { bucket in
        LineMark(
          x: .value(metric.titleKey, bucket.center),
          y: .value("analysis.environment.share", bucket.proportion)
        )
        .foregroundStyle(.secondary)
        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
        .symbol(Circle())
        .symbolSize(22)
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 5)) { value in
        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(metric.axisText(number))
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(number, format: .percent.precision(.fractionLength(0)))
          }
        }
      }
    }
    .frame(height: 240)
    .accessibilityLabel(Text("analysis.symptomEnvironment"))
  }

  private var chartLegend: some View {
    AZFlowLayout(spacing: 10, rowSpacing: 6, alignment: .leading) {
      ForEach(SymptomSeverity.selectableCases) { severity in
        legendItem(
          title: NSLocalizedString(severity.labelKey, comment: ""),
          color: severityColor(severity)
        )
      }
      HStack(spacing: 5) {
        Rectangle()
          .fill(Color.secondary)
          .frame(width: 20, height: 2)
        Text("analysis.environment.allRecords")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func legendItem(title: String, color: Color) -> some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color.opacity(0.82))
        .frame(width: 10, height: 10)
      Text(title).font(.caption)
    }
  }

  private func bucketLower(_ value: Double) -> Double {
    floor(value / metric.binWidth) * metric.binWidth
  }

  private func severityColor(_ severity: SymptomSeverity) -> Color {
    switch severity {
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
                Text(page.displayTitle)
                  .font(.caption)
              }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(page.accessibilityTitle)
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
          Text(selectedDestinationTitle)
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

  private var selectedDestinationTitle: String {
    if let page = selectedDestination.page {
      return page.displayTitle
    }
    return String(localized: "analysis.layout.hidden")
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
            .accessibilityLabel(page.accessibilityTitle)
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
