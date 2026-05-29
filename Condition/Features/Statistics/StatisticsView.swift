// StatisticsView.swift
// 統計画面（旧 StatisticsVC 相当）

import SwiftUI
import SwiftData
import Charts

// MARK: - チャート幅 Environment

struct ChartAvailableWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 390
}
extension EnvironmentValues {
    var chartAvailableWidth: CGFloat {
        get { self[ChartAvailableWidthKey.self] }
        set { self[ChartAvailableWidthKey.self] = newValue }
    }
}

/// 利用可能幅とフォントサイズに応じてチャート高さを拡大する
/// dynamicTypeSize を渡すと文字サイズに比例してわずかに高くなる（最大1.33倍）
func adaptiveChartHeight(base: CGFloat, width: CGFloat, dynamicTypeSize: DynamicTypeSize = .large) -> CGFloat {
    let fontFactor: CGFloat
    switch dynamicTypeSize {
    case .xSmall, .small, .medium, .large: fontFactor = 1.00
    case .xLarge:         fontFactor = 1.04
    case .xxLarge:        fontFactor = 1.08
    case .xxxLarge:       fontFactor = 1.13
    case .accessibility1: fontFactor = 1.17
    case .accessibility2: fontFactor = 1.21
    case .accessibility3: fontFactor = 1.25
    case .accessibility4: fontFactor = 1.29
    case .accessibility5: fontFactor = 1.33
    @unknown default:     fontFactor = 1.00
    }
    let h = base * fontFactor
    guard width > 390 else { return h }
    return h * (width / 390)
}

struct StatisticsView: View {

    private var settings: AppSettings { AppSettings.shared }
    @State private var cutoffDate = StatisticsView.makeCutoffDate(
        days: GraphPeriod.threeMonths.rawValue
    )

    var body: some View {
        StatisticsContentView(
            cutoffDate: cutoffDate,
            expandCutoffIfNeeded: expandCutoffIfNeeded(days:)
        )
        // 保存済みの統計期間が長い場合だけ、初回表示後に取得範囲を広げる
        .onAppear {
            expandCutoffIfNeeded(days: currentPeriod.rawValue)
        }
    }

    private var currentPeriod: GraphPeriod {
        GraphPeriod(rawValue: settings.statDays) ?? .threeMonths
    }

    private static func makeCutoffDate(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private func expandCutoffIfNeeded(days: Int) {
        let target = Self.makeCutoffDate(days: days)
        if target < cutoffDate {
            cutoffDate = target
        }
    }
}

private struct StatisticsContentView: View {
    private static let initialChartCount = 2
    private static let chartBatchCount = 2
    private static let chartBatchDelayMS = 120

    @Query private var records: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }
    private let expandCutoffIfNeeded: (Int) -> Void
    @State private var showSettings = false
    @State private var chartWidth: CGFloat = 390
    @State private var isExporting = false
    @State private var stagedChartCount = StatisticsContentView.initialChartCount

    init(cutoffDate: Date, expandCutoffIfNeeded: @escaping (Int) -> Void) {
        let predicate = #Predicate<BodyRecord> {
            cutoffDate <= $0.dateTime && $0.dateTime < bodyRecordGoalDate
        }
        _records = Query(filter: predicate, sort: \BodyRecord.dateTime, order: .reverse)
        self.expandCutoffIfNeeded = expandCutoffIfNeeded
    }

    private var periodBinding: Binding<GraphPeriod> {
        Binding(
            get: { GraphPeriod(rawValue: settings.statDays) ?? .threeMonths },
            set: { newPeriod in
                settings.statDays = newPeriod.rawValue
                expandCutoffIfNeeded(newPeriod.rawValue)
            }
        )
    }

    private var currentPeriod: GraphPeriod {
        GraphPeriod(rawValue: settings.statDays) ?? .threeMonths
    }

    private var targetRecords: [BodyRecord] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -currentPeriod.rawValue,
            to: Date()
        ) ?? Date()
        return records.filter { cutoff <= $0.dateTime }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "empty.noData",
                        systemImage: "chart.dots.scatter"
                    )
                } else {
                    scrollContent
                }
            }
            .overlay { if isExporting { exportingOverlay } }
            .navigationTitle("tab.statistics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { @MainActor in
                            isExporting = true
                            defer { isExporting = false }
                            try? await Task.sleep(for: .milliseconds(50))
                            doExport()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(targetRecords.isEmpty || isExporting)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                let content = NavigationStack {
                    StatSettingsView(isModal: true)
                }
                if AppSettings.shared.fontScale.followsSystem {
                    content
                } else {
                    content.dynamicTypeSize(AppSettings.shared.fontScale.dynamicTypeSize)
                }
            }
            // 区分のアイコン・名称・色を変更したら統計チャートを再生成する
            .id(settings.dateOptAppearanceRevision)
        }
    }

    private var visibleStatSections: [StatSection] {
        let hidden = Set(settings.statHiddenSections)
        return settings.statSectionOrder.compactMap { raw in
            guard !hidden.contains(raw) else { return nil }
            return StatSection(rawValue: raw)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                BeginnerHelpBanner("help.statistics", storageKey: "helpDismissed.statistics")
                LazyVStack(spacing: 16) {
                    // 対象期間はグラフ画面と同じラジオPickerで揃える
                    AZRadioPicker(
                        options: GraphPeriod.allCases,
                        selection: periodBinding,
                        minOptionWidth: 0,
                        maxOptionWidth: 120,
                        horizontalPadding: 4,
                        optionSpacing: 4,
                        groupPadding: 5,
                        wrapsOptions: false,
                        fillsWidth: true
                    ) { p in
                        Text(LocalizedStringKey(p.label))
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.horizontal)

                    ForEach(stagedStatSections) { section in
                        statSectionView(section)
                    }
                }
                .padding()
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { chartWidth = $0 }
        }
        .environment(\.chartAvailableWidth, chartWidth)
        .task(id: statStageID) {
            await revealCharts(total: visibleStatSections.count)
        }
    }

    private var stagedStatSections: [StatSection] {
        Array(visibleStatSections.prefix(min(stagedChartCount, visibleStatSections.count)))
    }

    private var statStageID: String {
        visibleStatSections.map { String($0.rawValue) }.joined(separator: "|")
    }

    @MainActor
    private func revealCharts(total: Int) async {
        // 初回は上部に見える分だけ作り、その後に残りを小分けで作る
        stagedChartCount = min(Self.initialChartCount, total)
        while stagedChartCount < total {
            try? await Task.sleep(for: .milliseconds(Self.chartBatchDelayMS))
            stagedChartCount = min(stagedChartCount + Self.chartBatchCount, total)
        }
    }

    @ViewBuilder
    private func statSectionView(_ section: StatSection) -> some View {
        switch section {
        case .bpJsh:           BpJshView(records: targetRecords)
        case .bpRatio:         BpJshRatioView(records: targetRecords)
        case .bpDateOptCorr:   BpDateOptCorrView(records: targetRecords)
        case .bp24h:           Bp24HChartView(records: targetRecords)
        case .bpSummary:       BpSummaryView(records: targetRecords)
        case .weightSummary:   WeightSummaryView(records: targetRecords)
        case .tempSummary:     TempSummaryView(records: targetRecords)
        case .temp24h:         Temp24HChartView(records: targetRecords)
        case .tempHist:        TempHistogramView(records: targetRecords)
        case .weightBpScatter: WeightBpScatterView(records: targetRecords)
        }
    }

    // MARK: - PDF エクスポート

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                Text(String(format: String(localized: "export.generating"), "PDF"))
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }


    private func doExport() {
        let pdfW = PDFPanelExporter.contentW
        let panels: [AnyView] = visibleStatSections.map { section in
            AnyView(
                statSectionView(section)
                    .environment(\.chartAvailableWidth, pdfW)
            )
        }

        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("yMd")
        let now = Date()
        let fromDate = Calendar.current.date(byAdding: .day, value: -currentPeriod.rawValue, to: now) ?? now
        let localizedPeriod = NSLocalizedString(currentPeriod.label, comment: "")
        let subtitle = localizedPeriod + "  " + df.string(from: fromDate) + String(localized: "format.range.separator") + df.string(from: now)
        let title = String(localized: "tab.statistics")

        let data = PDFPanelExporter.export(panels: panels, title: title, subtitle: subtitle)
        let tabName = String(localized: "tab.statistics")
        let dateTag = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: Date()) }()
        guard let url = PDFPanelExporter.writeTempFile(name: "\(tabName)_\(dateTag).pdf", data: data) else { return }

        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        topVC.present(activityVC, animated: true)
    }

}

// MARK: - JSH 血圧分布バー＋散布図

struct BpJshView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showJSHInfo = false
    @ScaledMetric(relativeTo: .caption) private var zoneLabelSize: CGFloat = 10

    private var isJapanese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") ?? true
    }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    var body: some View {
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("metric.bloodPressureDistribution")
                        .font(.title3)
                    Spacer()
                    Button {
                        showJSHInfo = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.footnote)
                            Text(isJapanese ? String(localized: "text.jshStandard") : "ESC/ESH 2018")
                                .font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showJSHInfo, arrowEdge: .bottom) {
                        if isJapanese {
                            JSHStandardsPopover()
                        } else {
                            ESHStandardsPopover()
                        }
                    }
                }
                .padding(.horizontal)

                // 散布図（上 vs 下、JSHゾーン背景＋カラードット）
                Chart {
                    // 上（収縮期）ゾーン帯：横方向
                    ForEach(bpHiZones, id: \.min) { z in
                        RectangleMark(
                            xStart: .value("", 40), xEnd: .value("", 130),
                            yStart: .value("", max(z.min, 70)),
                            yEnd:   .value("", min(z.max, 210))
                        )
                        .foregroundStyle(z.color)
                    }
                    // 下（拡張期）ゾーン帯：縦方向（上ゾーンより薄く重ねる）
                    ForEach(bpLoZones, id: \.min) { z in
                        RectangleMark(
                            xStart: .value("", max(z.min, 40)),
                            xEnd:   .value("", min(z.max, 130)),
                            yStart: .value("", 70), yEnd: .value("", 210)
                        )
                        .foregroundStyle(z.color.opacity(0.5))
                    }
                    // JSH境界ステップ線
                    jshBoundaryLines()
                    // ゾーンラベル（Y軸寄り）
                    jshZoneLabels()
                    // データ点
                    ForEach(validRecords) { r in
                        PointMark(
                            x: .value("metric.diastolic.short", r.nBpLo_mmHg),
                            y: .value("metric.systolic.short", r.nBpHi_mmHg)
                        )
                        .foregroundStyle(DateOpt(rawValue: r.nDateOpt)?.color ?? .secondary)
                        .symbolSize(32)
                    }
                }
                .chartXScale(domain: 40...134)
                .chartYScale(domain: 70...210)
                .chartXAxis {
                    let narrow = UIScreen.main.bounds.width <= 375
                    let xValues: [Int] = narrow ? [60, 80, 100] : [60, 80, 100, 120]
                    AxisMarks(values: xValues) { value in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                let showLabel = v == 120 || (narrow && v == 100)
                                if showLabel {
                                    HStack(spacing: 2) {
                                        Text("\(v)").font(.caption)
                                        Text("metric.diastolic.short").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("\(v)").font(.caption)
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [80, 100, 120, 140, 160, 180, 200]) { value in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                if v == 200 {
                                    VStack(spacing: 0) {
                                        Text("metric.systolic.short").font(.caption).foregroundStyle(.secondary)
                                        Text("\(v)").font(.caption)
                                    }
                                } else {
                                    Text("\(v)").font(.caption)
                                }
                            }
                        }
                    }
                }
                .frame(height: adaptiveChartHeight(base: 330, width: chartWidth, dynamicTypeSize: dynamicTypeSize))
                .padding(.horizontal, 4)
                .overlay {
                    if validRecords.isEmpty {
                        Text("empty.noDataInPeriod")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // 区分（DateOpt）凡例
                let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, alignment: .center, spacing: 4) {
                    ForEach(DateOpt.allCases.filter(\.isDefined), id: \.self) { opt in
                        HStack(spacing: 4) {
                            Image(systemName: opt.icon)
                                .font(.caption2)
                                .foregroundStyle(opt.color)
                            Text(opt.displayName)
                                .font(.caption)
                                .foregroundStyle(opt.color)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    private func dateOptColor(_ opt: DateOpt) -> Color { opt.color }

    @ChartContentBuilder
    private func jshBoundaryLines() -> some ChartContent {
        let bc = Color.secondary.opacity(0.45)
        let bs = StrokeStyle(lineWidth: 1)
        // 正常血圧 / 正常高値
        RuleMark(xStart: .value("", 40), xEnd: .value("", 80), y: .value("", 120))
            .foregroundStyle(bc).lineStyle(bs)
        // 正常高値 / 高値血圧（+ 正常血圧右縁）
        RuleMark(xStart: .value("", 40), xEnd: .value("", 80), y: .value("", 130))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 80), yStart: .value("", 70), yEnd: .value("", 130))
            .foregroundStyle(bc).lineStyle(bs)
        // 高値血圧 / 高血圧I度
        RuleMark(xStart: .value("", 40), xEnd: .value("", 90), y: .value("", 140))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 90), yStart: .value("", 70), yEnd: .value("", 140))
            .foregroundStyle(bc).lineStyle(bs)
        // 高血圧I度 / 高血圧II度
        RuleMark(xStart: .value("", 40), xEnd: .value("", 100), y: .value("", 160))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 100), yStart: .value("", 70), yEnd: .value("", 160))
            .foregroundStyle(bc).lineStyle(bs)
        // 高血圧II度 / 高血圧III度
        RuleMark(xStart: .value("", 40), xEnd: .value("", 110), y: .value("", 180))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 110), yStart: .value("", 70), yEnd: .value("", 180))
            .foregroundStyle(bc).lineStyle(bs)
    }

    // 各ゾーン中央にラベルを表示（Y軸寄り）
    @ChartContentBuilder
    private func jshZoneLabels() -> some ChartContent {
        let names = ["metric.normal", "text.elevated", "metric.highNormal", "metric.grade1Htn", "metric.grade2Htn", "metric.grade3Htn"]
        let labels: [(name: String, color: Color, y: Int)] = [
            (names[0], Color(red: 0.20, green: 0.50, blue: 0.90),  95),
            (names[1], Color(red: 0.25, green: 0.72, blue: 0.35), 125),
            (names[2], Color(white: 0.20), 135),
            (names[3], Color(red: 1.00, green: 0.55, blue: 0.00), 150),
            (names[4], Color(red: 0.95, green: 0.25, blue: 0.00), 170),
            (names[5], Color(red: 0.80, green: 0.00, blue: 0.00), 195),
        ]
        ForEach(labels, id: \.name) { label in
            PointMark(x: .value("", 41), y: .value("", label.y))
                .symbolSize(0)
                .annotation(position: .trailing, alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(label.name))
                        .font(.system(size: zoneLabelSize))
                        .foregroundStyle(label.color.opacity(0.85))
                }
        }
    }
}

// MARK: - JSH基準ポップアップ

private struct JSHStandardsPopover: View {
    private struct Row {
        let name: String
        let color: Color
        let criteria: String
    }
    private let rows: [Row] = [
        Row(name: "metric.grade3Htn", color: Color(red: 0.80, green: 0.00, blue: 0.00), criteria: "jsh.criteria.grade3"),
        Row(name: "metric.grade2Htn",  color: Color(red: 0.95, green: 0.25, blue: 0.00), criteria: "jsh.criteria.grade2"),
        Row(name: "metric.grade1Htn",   color: Color(red: 1.00, green: 0.55, blue: 0.00), criteria: "jsh.criteria.grade1"),
        Row(name: "metric.highNormal",    color: Color(white: 0.55),                         criteria: "jsh.criteria.highNormal"),
        Row(name: "text.elevated",    color: Color(red: 0.25, green: 0.72, blue: 0.35), criteria: "jsh.criteria.elevated"),
        Row(name: "metric.normal",    color: Color(red: 0.20, green: 0.50, blue: 0.90), criteria: "jsh.criteria.normal"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("metric.jshBpClassification2019")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.name) { index, row in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(row.color.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5)
                            )
                            .frame(width: 18, height: 18)
                        Text(LocalizedStringKey(row.name))
                            .font(.callout)
                        Spacer()
                        Text(LocalizedStringKey(row.criteria))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
                Spacer(minLength: 14)
            }
        }
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - ESC/ESH 2018 基準ポップアップ（en 用）

private struct ESHStandardsPopover: View {
    private struct Row {
        let name: String
        let color: Color
        let criteria: String
    }
    private let rows: [Row] = [
        Row(name: "Grade 3 HT",  color: Color(red: 0.80, green: 0.00, blue: 0.00), criteria: "Systolic ≥180 or Diastolic ≥110"),
        Row(name: "Grade 2 HT",  color: Color(red: 0.95, green: 0.25, blue: 0.00), criteria: "Systolic 160–179 or Diastolic 100–109"),
        Row(name: "Grade 1 HT",  color: Color(red: 1.00, green: 0.55, blue: 0.00), criteria: "Systolic 140–159 or Diastolic 90–99"),
        Row(name: "High Normal", color: Color(white: 0.55),                          criteria: "Systolic 130–139 or Diastolic 80–89"),
        Row(name: "Normal",      color: Color(red: 0.25, green: 0.72, blue: 0.35),  criteria: "Systolic 120–129 and Diastolic <80"),
        Row(name: "Optimal",     color: Color(red: 0.20, green: 0.50, blue: 0.90),  criteria: "Systolic <120 and Diastolic <80"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("text.escEshHypertensionGuidelines2018")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.name) { index, row in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(row.color.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5)
                            )
                            .frame(width: 18, height: 18)
                        Text(row.name)
                            .font(.callout)
                        Spacer()
                        Text(row.criteria)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
                Spacer(minLength: 14)
            }
        }
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 血圧 JSH基準割合バー

struct BpJshRatioView: View {
    let records: [BodyRecord]
    /// 列minimum幅をフォントサイズと連動させる（大文字時に3→2→1列へ自動縮小）
    @ScaledMetric(relativeTo: .caption) private var legendMinW: CGFloat = 110

    private var isJapanese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") ?? true
    }

    private static let categoryColors: [Color] = [
        Color(red: 0.20, green: 0.50, blue: 0.90),
        Color(red: 0.25, green: 0.72, blue: 0.35),
        Color(white: 0.55),
        Color(red: 1.00, green: 0.55, blue: 0.00),
        Color(red: 0.95, green: 0.25, blue: 0.00),
        Color(red: 0.80, green: 0.00, blue: 0.00),
    ]

    private var categoryNames: [(name: String, color: Color)] {
        let names = ["metric.normal", "text.elevated", "metric.highNormal", "metric.grade1Htn", "metric.grade2Htn", "metric.grade3Htn"]
        return zip(names, Self.categoryColors).map { ($0, $1) }
    }

    private func jshIndex(hi: Int, lo: Int) -> Int {
        if hi >= 180 || lo >= 110 { return 5 }
        if hi >= 160 || lo >= 100 { return 4 }
        if hi >= 140 || lo >= 90  { return 3 }
        if hi >= 130 || lo >= 80  { return 2 }
        if hi >= 120              { return 1 }
        return 0
    }

    private var counts: [Int] {
        let valid = records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
        var c = [Int](repeating: 0, count: 6)
        for r in valid { c[jshIndex(hi: r.nBpHi_mmHg, lo: r.nBpLo_mmHg)] += 1 }
        return c
    }

    var body: some View {
        let c = counts
        let total = c.reduce(0, +)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("metric.bpJshRatio")
                    .font(.title3)
                    .padding(.horizontal)

                GeometryReader { geo in
                    if total > 0 {
                        HStack(spacing: 0) {
                            ForEach(Array(categoryNames.enumerated()), id: \.offset) { i, cat in
                                if c[i] > 0 {
                                    Rectangle()
                                        .fill(cat.color)
                                        .frame(width: geo.size.width * CGFloat(c[i]) / CGFloat(total))
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                    }
                }
                .frame(height: 28)
                .padding(.horizontal)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: legendMinW))],
                    spacing: 4
                ) {
                    ForEach(Array(categoryNames.enumerated()), id: \.offset) { i, cat in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cat.color)
                                .frame(width: 10, height: 10)
                            Text(LocalizedStringKey(cat.name)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(c[i] > 0
                                 ? String(format: "%.0f%%", Double(c[i]) / Double(total) * 100)
                                 : "-")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(c[i] > 0 ? .primary : .tertiary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }
}

// MARK: - 血圧・区分 相関（ストリッププロット）

struct BpDateOptCorrView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct BpPoint: Identifiable {
        let id: Int
        let category: String
        let dateOptRaw: Int
        let value: Int
        let isHi: Bool
    }

    private struct CatMean: Identifiable {
        let id: String
        let category: String
        let dateOptRaw: Int
        let hiAvg: Double
        let loAvg: Double
    }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    private var points: [BpPoint] {
        var result: [BpPoint] = []
        var idx = 0
        for r in validRecords {
            guard let dateOpt = DateOpt(rawValue: r.nDateOpt), dateOpt.isDefined else { continue }
            result.append(BpPoint(id: idx,     category: dateOpt.displayName, dateOptRaw: dateOpt.rawValue, value: r.nBpHi_mmHg, isHi: true))
            result.append(BpPoint(id: idx + 1, category: dateOpt.displayName, dateOptRaw: dateOpt.rawValue, value: r.nBpLo_mmHg, isHi: false))
            idx += 2
        }
        return result
    }

    private var means: [CatMean] {
        DateOpt.allCases.compactMap { opt in
            guard opt.isDefined else { return nil }
            let filtered = validRecords.filter { $0.nDateOpt == opt.rawValue }
            guard !filtered.isEmpty else { return nil }
            let hi = Double(filtered.map { $0.nBpHi_mmHg }.reduce(0, +)) / Double(filtered.count)
            let lo = Double(filtered.map { $0.nBpLo_mmHg }.reduce(0, +)) / Double(filtered.count)
            return CatMean(id: "\(opt.rawValue)", category: opt.displayName, dateOptRaw: opt.rawValue, hiAvg: hi, loAvg: lo)
        }
    }

    private var categoryOrder: [String] {
        DateOpt.allCases.filter(\.isDefined).map(\.displayName)
    }

    private var yDomain: ClosedRange<Int> {
        guard !points.isEmpty else { return 50...180 }
        let vals = points.map { $0.value }
        let lower = max(30, (vals.min()! / 10) * 10 - 10)
        let upper = min(260, ((vals.max()! + 9) / 10) * 10 + 10)
        return lower...upper
    }

    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let bpCorrLegend = HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Circle().fill(Color.red.opacity(0.8)).frame(width: 8, height: 8)
                    Text("metric.systolic.short").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.blue.opacity(0.8)).frame(width: 8, height: 8)
                    Text("metric.diastolic.short").font(.caption).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("metric.bpByCategory").font(.title3)
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3).foregroundStyle(.secondary)
                            .padding(.vertical, 6).padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                        BpDateOptCorrInfoPopover()
                    }
                    Spacer()
                    bpCorrLegend
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("metric.bpByCategory").font(.title3)
                        Button {
                            showInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3).foregroundStyle(.secondary)
                                .padding(.vertical, 6).padding(.horizontal, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                            BpDateOptCorrInfoPopover()
                        }
                    }
                    bpCorrLegend
                }
            }
            .padding(.horizontal)

            if points.isEmpty {
                Text("empty.noDataInPeriod")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                chartContent
                Text("chart.legend.categoryAverage")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chartContent: some View {
        let ms = means
        let order = categoryOrder
        return Chart {
            ForEach(points) { pt in
                PointMark(
                    x: .value("record.category", pt.category),
                    y: .value("unit.mmHg", pt.value)
                )
                .symbol(.circle)
                .symbolSize(16)
                .foregroundStyle(pt.isHi ? Color.red.opacity(0.35) : Color.blue.opacity(0.35))
            }
            ForEach(ms) { m in
                PointMark(
                    x: .value("record.category", m.category),
                    y: .value("unit.mmHg", m.hiAvg)
                )
                .symbol(.diamond)
                .symbolSize(80)
                .foregroundStyle(Color.red.opacity(0.9))

                PointMark(
                    x: .value("record.category", m.category),
                    y: .value("unit.mmHg", m.loAvg)
                )
                .symbol(.diamond)
                .symbolSize(80)
                .foregroundStyle(Color.blue.opacity(0.9))
            }
        }
        .chartXScale(domain: order)
        .chartYScale(domain: yDomain)
        .chartYAxisLabel("unit.mmHg")
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let s = value.as(String.self),
                       let opt = DateOpt.allCases.first(where: { $0.displayName == s }) {
                        VStack(spacing: 2) {
                            Image(systemName: opt.icon)
                                .font(.caption)
                                .foregroundStyle(opt.color)
                            Text(s)
                                .font(.caption)
                                .foregroundStyle(opt.color)
                                .multilineTextAlignment(.center)
                        }
                        // 区分軸は読みやすくしつつ、特大文字サイズまでで上限を止める
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }
            }
        }
        .frame(height: adaptiveChartHeight(base: 240, width: chartWidth, dynamicTypeSize: dynamicTypeSize))
        .padding(.horizontal)
    }
}

// MARK: - 血圧・区分 相関 説明ポップアップ

private struct BpDateOptCorrInfoPopover: View {
    private var isJapanese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") ?? true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(isJapanese ? String(localized: "chart.howToReadTheScatterPlot") : "How to Read This Chart")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        isJapanese
                            ? String(localized: "chart.corrInfo.byCategory")
                            : "Blood pressure values are plotted vertically for each category (e.g. morning, rest)",
                        systemImage: "circle.fill"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Label(
                        isJapanese ? String(localized: "chart.corrInfo.measurementDots")
                                   : "Small circles represent individual measurements",
                        systemImage: "circle"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Label(
                        isJapanese ? String(localized: "chart.corrInfo.averageDiamond")
                                   : "Diamond ◆ marks the category average",
                        systemImage: "diamond.fill"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Label(
                        isJapanese
                            ? String(localized: "chart.corrInfo.compareAverages")
                            : "Comparing ◆ heights across categories reveals time-of-day BP patterns",
                        systemImage: "arrow.left.arrow.right"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 10, height: 10)
                        Text(isJapanese ? String(localized: "metric.redSystolicUpper") : "Red = Systolic (Upper)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(Color.blue.opacity(0.8)).frame(width: 10, height: 10)
                        Text(isJapanese ? String(localized: "metric.blueDiastolicLower") : "Blue = Diastolic (Lower)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - 血圧 24時間散布図（旧 statDispersal24Hour 相当）

struct Bp24HChartView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    private var settings: AppSettings { AppSettings.shared }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var validRecords: [(hour: Int, hi: Int, lo: Int)] {
        let cal = Calendar(identifier: .gregorian)
        return records
            .filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .map { r in
                let h = cal.component(.hour, from: r.dateTime)
                return (hour: h, hi: r.nBpHi_mmHg, lo: r.nBpLo_mmHg)
            }
    }

    /// データに合わせた Y 軸範囲（10mmHg グリッドに揃え、上下にパディング）
    private var yDomain: ClosedRange<Int> {
        guard !validRecords.isEmpty else { return 50...180 }
        let allValues = validRecords.flatMap { [$0.lo, $0.hi] }
        let dataMin = allValues.min()!
        let dataMax = allValues.max()!
        let lower = max(30, (dataMin / 10) * 10 - 10)
        let upper = min(260, ((dataMax + 9) / 10) * 10 + 10)
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("metric.bp24hDistribution")
                .font(.title3)
                .padding(.horizontal)

            Chart {
                ForEach(Array(validRecords.enumerated()), id: \.offset) { _, item in
                    PointMark(
                        x: .value("text.time", item.hour),
                        y: .value("metric.systolic", item.hi)
                    )
                    .foregroundStyle(.red.opacity(0.6))
                    .symbolSize(35)

                    PointMark(
                        x: .value("text.time", item.hour),
                        y: .value("metric.diastolic", item.lo)
                    )
                    .foregroundStyle(.blue.opacity(0.6))
                    .symbolSize(35)
                }

                // 時刻ライン（設定時刻に垂直線）
                if settings.statShow24HLine {
                    RuleMark(x: .value("category.wake.line", settings.wakeHour))
                        .foregroundStyle(.green.opacity(0.4))
                    RuleMark(x: .value("category.bedtime.line", settings.sleepHour))
                        .foregroundStyle(.purple.opacity(0.4))
                }
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: yDomain)
            .chartXAxisLabel("text.time")
            .chartYAxisLabel("unit.mmHg")
            .frame(height: adaptiveChartHeight(base: 220, width: chartWidth, dynamicTypeSize: dynamicTypeSize))
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 血圧 上下平均サマリー

struct BpSummaryView: View {
    let records: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let avg = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    var body: some View {
        let hiValues = validRecords.map { Double($0.nBpHi_mmHg) }
        let loValues = validRecords.map { Double($0.nBpLo_mmHg) }
        let hiAvg = hiValues.isEmpty ? 0.0 : hiValues.reduce(0, +) / Double(hiValues.count)
        let loAvg = loValues.isEmpty ? 0.0 : loValues.reduce(0, +) / Double(loValues.count)
        let hiStd = standardDeviation(hiValues)
        let loStd = standardDeviation(loValues)

        VStack(spacing: 8) {
            Text("metric.bloodPressureSummary")
                .font(.title3)

            if validRecords.isEmpty {
                Text("empty.noDataInPeriod")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 40)
                        Text("stat.avg").font(.footnote).foregroundStyle(.secondary)
                        if settings.statShowAvg {
                            Text("stat.standardDeviation.short").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("metric.systolic.short").foregroundStyle(.red)
                        Text(String(format: "%.1f", hiAvg)).font(.title2.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.1f", hiStd)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("metric.diastolic.short").foregroundStyle(.blue)
                        Text(String(format: "%.1f", loAvg)).font(.title2.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.1f", loStd)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体重 サマリー

struct WeightSummaryView: View {
    let records: [BodyRecord]
    @ScaledMetric(relativeTo: .footnote) private var unitColW: CGFloat = 24

    private var weightRecords: [BodyRecord] {
        records.filter { $0.nWeight_10Kg > 0 }.sorted { $0.dateTime < $1.dateTime }
    }

    private var values: [Double] { weightRecords.map { Double($0.nWeight_10Kg) / 10.0 } }
    private var avg: Double { values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count) }
    private var minVal: Double { values.min() ?? 0.0 }
    private var maxVal: Double { values.max() ?? 0.0 }
    private var change: Double { values.count >= 2 ? values.last! - values.first! : 0.0 }

    @ViewBuilder private var changeCell: some View {
        HStack(spacing: 2) {
            Image(systemName: change > 0.05 ? "arrow.up" : change < -0.05 ? "arrow.down" : "minus")
                .foregroundStyle(change > 0.05 ? .red : change < -0.05 ? .blue : .secondary)
                .font(.footnote)
            Text(String(format: "%.1f", abs(change)))
                .font(.title2.monospacedDigit())
                .foregroundStyle(change > 0.05 ? .red : change < -0.05 ? .blue : .secondary)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("metric.weightSummary")
                .font(.title3)

            if values.isEmpty {
                Text("empty.noDataInPeriod")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    // 4列レイアウト（プライマリ）
                    Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("stat.avg").font(.footnote).foregroundStyle(.secondary)
                            Text("stat.min").font(.footnote).foregroundStyle(.secondary)
                            Text("stat.max").font(.footnote).foregroundStyle(.secondary)
                            Text("text.change").font(.footnote).foregroundStyle(.secondary)
                            Text("").frame(width: unitColW)
                        }
                        GridRow {
                            Text(String(format: "%.1f", avg)).font(.title2.monospacedDigit())
                            Text(String(format: "%.1f", minVal)).font(.title2.monospacedDigit())
                            Text(String(format: "%.1f", maxVal)).font(.title2.monospacedDigit())
                            changeCell
                            Text("unit.kg").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    // 2行レイアウト（フォールバック）
                    VStack(spacing: 8) {
                        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("stat.avg").font(.footnote).foregroundStyle(.secondary)
                                Text("stat.min").font(.footnote).foregroundStyle(.secondary)
                            }
                            GridRow {
                                Text(String(format: "%.1f", avg)).font(.title2.monospacedDigit())
                                Text(String(format: "%.1f", minVal)).font(.title2.monospacedDigit())
                            }
                        }
                        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("stat.max").font(.footnote).foregroundStyle(.secondary)
                                Text("text.change").font(.footnote).foregroundStyle(.secondary)
                                Text("").frame(width: unitColW)
                            }
                            GridRow {
                                Text(String(format: "%.1f", maxVal)).font(.title2.monospacedDigit())
                                changeCell
                                Text("unit.kg").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体温 サマリー

struct TempSummaryView: View {
    let records: [BodyRecord]
    @ScaledMetric(relativeTo: .footnote) private var unitColW: CGFloat = 24

    private var settings: AppSettings { AppSettings.shared }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let avg = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    private var tempValues: [Double] {
        records.filter { $0.nTemp_10c > 0 }.map { Double($0.nTemp_10c) / 10.0 }
    }
    private var avg: Double { tempValues.isEmpty ? 0.0 : tempValues.reduce(0, +) / Double(tempValues.count) }
    private var sd: Double { standardDeviation(tempValues) }
    private var minVal: Double { tempValues.min() ?? 0.0 }
    private var maxVal: Double { tempValues.max() ?? 0.0 }

    var body: some View {
        VStack(spacing: 8) {
            Text("metric.bodyTempSummary")
                .font(.title3)

            if tempValues.isEmpty {
                Text("empty.noDataInPeriod")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    // プライマリ（1行）
                    Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("stat.avg").font(.footnote).foregroundStyle(.secondary)
                            if settings.statShowAvg {
                                Text("stat.standardDeviation.short").font(.footnote).foregroundStyle(.secondary)
                            }
                            Text("stat.min").font(.footnote).foregroundStyle(.secondary)
                            Text("stat.max").font(.footnote).foregroundStyle(.secondary)
                            Text("").frame(width: unitColW)
                        }
                        GridRow {
                            Text(String(format: "%.1f", avg)).font(.title2.monospacedDigit())
                            if settings.statShowAvg {
                                Text(String(format: "%.2f", sd)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Text(String(format: "%.1f", minVal)).font(.title2.monospacedDigit())
                            Text(String(format: "%.1f", maxVal)).font(.title2.monospacedDigit())
                            Text("unit.celsiusSymbol").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    // フォールバック（2行）
                    VStack(spacing: 8) {
                        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("stat.avg").font(.footnote).foregroundStyle(.secondary)
                                if settings.statShowAvg {
                                    Text("stat.standardDeviation.short").font(.footnote).foregroundStyle(.secondary)
                                }
                                Text("stat.min").font(.footnote).foregroundStyle(.secondary)
                            }
                            GridRow {
                                Text(String(format: "%.1f", avg)).font(.title2.monospacedDigit())
                                if settings.statShowAvg {
                                    Text(String(format: "%.2f", sd)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Text(String(format: "%.1f", minVal)).font(.title2.monospacedDigit())
                            }
                        }
                        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("stat.max").font(.footnote).foregroundStyle(.secondary)
                                Text("").frame(width: unitColW)
                            }
                            GridRow {
                                Text(String(format: "%.1f", maxVal)).font(.title2.monospacedDigit())
                                Text("unit.celsiusSymbol").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体温 24時間分布

struct Temp24HChartView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var validRecords: [(hour: Int, temp: Double)] {
        let cal = Calendar(identifier: .gregorian)
        return records
            .filter { $0.nTemp_10c > 0 }
            .map { r in
                let h = cal.component(.hour, from: r.dateTime)
                return (hour: h, temp: Double(r.nTemp_10c) / 10.0)
            }
    }

    /// データに合わせた Y 軸範囲（0.5℃ グリッドに揃え、上下にパディング）
    private var yDomain: ClosedRange<Double> {
        guard !validRecords.isEmpty else { return 35.5...37.5 }
        let temps = validRecords.map { $0.temp }
        let dataMin = temps.min()!
        let dataMax = temps.max()!
        let lower = (dataMin * 2).rounded(.down) / 2 - 0.5
        let upper = (dataMax * 2).rounded(.up)   / 2 + 0.5
        return max(34.0, lower)...min(42.0, upper)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("metric.bodyTemp24hDistribution")
                .font(.title3)
                .padding(.horizontal)

            Chart {
                ForEach(Array(validRecords.enumerated()), id: \.offset) { _, item in
                    PointMark(
                        x: .value("text.time", item.hour),
                        y: .value("metric.bodyTemp", item.temp)
                    )
                    .foregroundStyle(Color.pink.opacity(0.6))
                    .symbolSize(35)
                }
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: yDomain)
            .chartXAxisLabel("text.time")
            .chartYAxisLabel("unit.celsiusSymbol")
            .frame(height: adaptiveChartHeight(base: 220, width: chartWidth, dynamicTypeSize: dynamicTypeSize))
            .padding(.horizontal)
            .overlay {
                if validRecords.isEmpty {
                    Text("empty.noDataInPeriod")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体温分布ヒストグラム

struct TempHistogramView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var legendMinW: CGFloat = 130

    private struct Bin: Identifiable {
        let lower: Double
        let count: Int
        var id: Double { lower }
        var color: Color {
            if lower < 36.0 { return .blue }
            if lower < 37.0 { return .green }
            if lower < 37.5 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
            return .orange
        }
    }

    private var bins: [Bin] {
        let values = records.compactMap { $0.nTemp_10c > 0 ? $0.nTemp_10c : nil }
        return stride(from: 350, to: 410, by: 2).map { lo in
            Bin(lower: Double(lo) / 10.0, count: values.filter { $0 >= lo && $0 < lo + 2 }.count)
        }
    }

    private var hasData: Bool { bins.contains { $0.count > 0 } }

    private var xDomain: ClosedRange<Double> {
        let active = bins.filter { $0.count > 0 }.map(\.lower)
        guard let lo = active.min(), let hi = active.max() else { return 35.0...38.0 }
        // ビン幅 0.2 の 2 本分マージンを加え、0.5 刻みで丸める
        let domLo = (((lo - 0.4) * 2).rounded(.down) / 2)
        let domHi = (((hi + 0.6) * 2).rounded(.up)   / 2)
        return domLo...domHi
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("metric.bodyTempDistribution")
                .font(.title3)
                .padding(.horizontal)
            if hasData {
                chartContent
            } else {
                Text("empty.noDataInPeriod")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chartContent: some View {
        VStack(spacing: 8) {
            Chart(bins) { bin in
                RectangleMark(
                    xStart: .value("temp", bin.lower),
                    xEnd: .value("temp", bin.lower + 0.2),
                    yStart: .value("count", 0),
                    yEnd: .value("count", bin.count)
                )
                .foregroundStyle(bin.color.opacity(0.8))
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: 0.5)) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisTick()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.1f", v)).font(.caption)
                        }
                    }
                }
            }
            .chartXAxisLabel("unit.celsiusSymbol")
            .chartYAxisLabel("text.count")
            .frame(height: adaptiveChartHeight(base: 180, width: chartWidth, dynamicTypeSize: dynamicTypeSize))
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: legendMinW))], alignment: .center) {
                legendItem(color: .blue,
                           label: "metric.hypothermia36C")
                legendItem(color: .green,
                           label: "text.normal3637C")
                legendItem(color: Color(red: 1.0, green: 0.7, blue: 0.0),
                           label: "text.lowFever37375C")
                legendItem(color: .orange,
                           label: "text.fever375C")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }

    private func legendItem(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.8)).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 体重 × 血圧 相関散布図

struct WeightBpScatterView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Point: Identifiable {
        let id: Int
        let weight: Double  // kg
        let bp: Int         // mmHg
        let isSystolic: Bool
    }

    /// 体重・血圧どちらも記録されているレコードのみ使用
    private var validRecords: [BodyRecord] {
        records.filter { $0.nWeight_10Kg > 0 && $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    private var points: [Point] {
        var result: [Point] = []
        for (i, r) in validRecords.enumerated() {
            let w = Double(r.nWeight_10Kg) / 10.0
            result.append(Point(id: i * 2,     weight: w, bp: r.nBpHi_mmHg, isSystolic: true))
            result.append(Point(id: i * 2 + 1, weight: w, bp: r.nBpLo_mmHg, isSystolic: false))
        }
        return result
    }

    private var xDomain: ClosedRange<Double> {
        guard !validRecords.isEmpty else { return 40...100 }
        let ws = validRecords.map { Double($0.nWeight_10Kg) / 10.0 }
        let lo = (ws.min()! - 2).rounded(.down)
        let hi = (ws.max()! + 2).rounded(.up)
        return lo...hi
    }

    private var yDomain: ClosedRange<Int> {
        guard !validRecords.isEmpty else { return 50...180 }
        let allBp = validRecords.flatMap { [$0.nBpHi_mmHg, $0.nBpLo_mmHg] }
        let lower = max(30, (allBp.min()! / 10) * 10 - 10)
        let upper = min(260, ((allBp.max()! + 9) / 10) * 10 + 10)
        return lower...upper
    }

    /// ピアソン相関係数（体重 vs 収縮期）
    private var correlation: Double? {
        guard validRecords.count >= 3 else { return nil }
        let xs = validRecords.map { Double($0.nWeight_10Kg) / 10.0 }
        let ys = validRecords.map { Double($0.nBpHi_mmHg) }
        let n = Double(xs.count)
        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - xMean) * ($1 - yMean) }.reduce(0, +)
        let denX = sqrt(xs.map { pow($0 - xMean, 2) }.reduce(0, +))
        let denY = sqrt(ys.map { pow($0 - yMean, 2) }.reduce(0, +))
        guard denX > 0, denY > 0 else { return nil }
        return num / (denX * denY)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("metric.weightBpCorrelation")
                    .font(.title3)
                if let r = correlation {
                    Spacer()
                    Text(String(format: "r = %.2f", r))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(correlationColor(r))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(correlationColor(r).opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal)

            if validRecords.isEmpty {
                Text("empty.noDataInPeriod")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart(points) { pt in
                    PointMark(
                        x: .value("metric.weight", pt.weight),
                        y: .value("unit.mmHg", pt.bp)
                    )
                    .foregroundStyle(pt.isSystolic ? Color.red.opacity(0.55) : Color.blue.opacity(0.55))
                    .symbolSize(28)
                }
                .chartXScale(domain: xDomain)
                .chartYScale(domain: yDomain)
                .chartXAxisLabel("unit.kg")
                .chartYAxisLabel("unit.mmHg")
                .frame(height: adaptiveChartHeight(base: 240, width: chartWidth, dynamicTypeSize: dynamicTypeSize))
                .padding(.horizontal)

                // 凡例
                HStack(spacing: 14) {
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 8, height: 8)
                        Text("metric.systolic.short").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue.opacity(0.8)).frame(width: 8, height: 8)
                        Text("metric.diastolic.short").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // r 値の解説
                if correlation != nil {
                    Text("chart.correlationCoefficientRGuideAbsoluteValue")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func correlationColor(_ r: Double) -> Color {
        let abs = Swift.abs(r)
        if abs >= 0.7 { return .red }
        if abs >= 0.4 { return .orange }
        return .secondary
    }
}
