// GraphView.swift
// グラフ画面（刷新版）

import SwiftUI
import SwiftData
import Charts

// MARK: - スクロール位置キャプチャ

private final class ScrollCapture: @unchecked Sendable {
    var positions: [GraphKind: Date] = [:]
}
private struct ScrollCaptureKey: EnvironmentKey {
    static let defaultValue = ScrollCapture()
}
extension EnvironmentValues {
    fileprivate var scrollCapture: ScrollCapture {
        get { self[ScrollCaptureKey.self] }
        set { self[ScrollCaptureKey.self] = newValue }
    }
}

private struct ExportScrollDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}
extension EnvironmentValues {
    fileprivate var exportScrollDate: Date? {
        get { self[ExportScrollDateKey.self] }
        set { self[ExportScrollDateKey.self] = newValue }
    }
}

// MARK: - 表示期間

enum GraphPeriod: Int, CaseIterable, Identifiable {
    case week        = 7
    case month       = 30
    case threeMonths = 90
    case sixMonths   = 180
    case year        = 365

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week:        return "period.week"
        case .month:       return "period.month"
        case .threeMonths: return "period.threeMonths"
        case .sixMonths:   return "period.sixMonths"
        case .year:        return "period.year"
        }
    }

    var domainSeconds: Int { rawValue * 24 * 3600 }

    var xAxisCount: Int {
        switch self {
        case .week:        return 7
        case .month:       return 6
        case .threeMonths: return 6
        case .sixMonths:   return 6
        case .year:        return 6
        }
    }
}

// MARK: - GraphView

struct GraphView: View {
    /// バックグラウンドでプリフェッチする日数将来 730・1095 等に変更可能
    private static let preloadDays = 365

    @State private var period: GraphPeriod = .month
    @State private var showSettings = false
    @State private var didPrefetchFullRange = false
    /// フェーズ1: デフォルト期間分だけ即クエリ（高速初期表示）
    @State private var cutoffDate = Calendar.current.date(
        byAdding: .day, value: -GraphPeriod.month.rawValue, to: Date()
    ) ?? Date()

    var body: some View {
        NavigationStack {
            GraphContentView(
                cutoffDate: cutoffDate,
                period: $period,
                isWaitingForPrefetch: !didPrefetchFullRange
            )
                .navigationTitle("tab.graph")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSettings = true } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    let content = NavigationStack {
                        GraphSettingsView(isModal: true)
                    }
                    if AppSettings.shared.fontScale.followsSystem {
                        content
                    } else {
                        content.dynamicTypeSize(AppSettings.shared.fontScale.dynamicTypeSize)
                    }
                }
                // フェーズ2: 初期表示後にプリフェッチ範囲まで拡張（横スクロール対応）
                .task { await prefetchFullRange() }
                // 期間変更がプリフェッチ完了前の場合も即時対応
                .onChange(of: period) { _, newPeriod in
                    expandCutoffIfNeeded(days: newPeriod.rawValue)
                }
        }
    }

    /// 初期レンダリング完了を待ってから cutoffDate を拡張する
    private func prefetchFullRange() async {
        // 初回表示と最初の操作を優先し、広い期間の取得は少し遅らせる
        try? await Task.sleep(for: .milliseconds(900))
        expandCutoffIfNeeded(days: Self.preloadDays)
        didPrefetchFullRange = true
    }

    /// target が現在の cutoffDate より古ければ cutoffDate を更新する
    private func expandCutoffIfNeeded(days: Int) {
        let target = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        if target < cutoffDate {
            cutoffDate = target
        }
    }
}

// MARK: - GraphContentView

/// period に応じた日付範囲で @Query を組み立てる内部ビュー
/// cutoffDate が変わると SwiftUI が再初期化し @Query が再実行される
private struct GraphContentView: View {
    private static let initialChartCount = 2
    private static let chartBatchCount = 2
    private static let chartBatchDelayMS = 120

    @Query private var records: [BodyRecord]
    @Binding var period: GraphPeriod
    let isWaitingForPrefetch: Bool

    private var settings: AppSettings { AppSettings.shared }
    @State private var chartWidth: CGFloat = 390
    @State private var isExporting = false
    @State private var scrollCapture = ScrollCapture()
    @State private var stagedChartCount = GraphContentView.initialChartCount

    init(cutoffDate: Date, period: Binding<GraphPeriod>, isWaitingForPrefetch: Bool) {
        let predicate = #Predicate<BodyRecord> {
            cutoffDate <= $0.dateTime && $0.dateTime < bodyRecordGoalDate
        }
        _records = Query(filter: predicate, sort: \BodyRecord.dateTime, order: .reverse)
        _period = period
        self.isWaitingForPrefetch = isWaitingForPrefetch
    }

    var body: some View {
        Group {
            if records.isEmpty && isWaitingForPrefetch {
                // 初期範囲に記録がない場合は、広い範囲の取得完了まで No Data を出さない
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                ContentUnavailableView(
                    "empty.noData",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            } else {
                scrollContent
            }
        }
        .overlay { if isExporting { exportingOverlay } }
        // 区分のアイコン・名称・色を変更したらグラフ表示も再生成する
        .id(settings.dateOptAppearanceRevision)
        .environment(\.scrollCapture, scrollCapture)
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
                .disabled(records.isEmpty || isExporting)
            }
        }
    }

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

    private var scrollContent: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                BeginnerHelpBanner("help.graph", storageKey: "helpDismissed.graph")
                LazyVStack(spacing: 16) {
                    // 対象期間はDynamic Typeで欠けにくいラジオPickerで選ぶ
                    AZRadioPicker(
                        options: GraphPeriod.allCases,
                        selection: $period,
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

                    ForEach(stagedGraphKinds, id: \.self) { kind in
                        graphPanel(kind: kind)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { chartWidth = $0 }
        }
        .environment(\.chartAvailableWidth, chartWidth)
        .task(id: graphStageID) {
            await revealCharts(total: visibleGraphKinds.count)
        }
    }

    private var visibleGraphKinds: [GraphKind] {
        let hidden = Set(settings.graphHiddenPanels)
        return settings.graphDisplayOrder.compactMap { raw in
            guard !hidden.contains(raw) else { return nil }
            return GraphKind(rawValue: raw)
        }
    }

    private var stagedGraphKinds: [GraphKind] {
        Array(visibleGraphKinds.prefix(min(stagedChartCount, visibleGraphKinds.count)))
    }

    private var graphStageID: String {
        visibleGraphKinds.map { String($0.rawValue) }.joined(separator: "|")
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
    private func graphPanel(kind: GraphKind) -> some View {
        switch kind {
        case .bp:
            BpChartView(records: records, period: period)
        case .bpAvg:
            BpPpChartView(records: records, period: period, goalValue: settings.goalBpPp)
        case .pulse:
            LineChartView(records: records, keyPath: \.nPulse_bpm,
                          title: kind.title, unit: "unit.bpm", color: .orange,
                          goalValue: settings.goalPulse, period: period,
                          tightDomain: true, usesDateOptFilterAndLineMode: true, kind: kind)
        case .temp:
            LineChartView(records: records, keyPath: \.nTemp_10c,
                          title: kind.title, unit: "unit.celsius", color: .pink,
                          goalValue: settings.goalTemp, decimals: 1, period: period,
                          tightDomain: true, kind: kind)
        case .weight:
            LineChartView(records: records, keyPath: \.nWeight_10Kg,
                          title: kind.title, unit: "unit.kg", color: .indigo,
                          goalValue: settings.goalWeight, decimals: 1, period: period,
                          tightDomain: true, showMovingAverage: settings.graphWeightMA, kind: kind)
        case .bmi:
            if settings.graphBMITall > 0 {
                BMIChartView(records: records, heightCm: settings.graphBMITall, period: period, goalValue: settings.goalBMI)
            }
        case .weightChange:
            WeightChangeChartView(records: records, period: period)
        case .bodyFat:
            LineChartView(records: records, keyPath: \.nBodyFat_10p,
                          title: kind.title, unit: "%", color: .purple,
                          goalValue: settings.goalBodyFat, decimals: 1, period: period,
                          tightDomain: true, kind: kind)
        case .skMuscle:
            LineChartView(records: records, keyPath: \.nSkMuscle_10p,
                          title: kind.title, unit: "%", color: .teal,
                          goalValue: settings.goalSkMuscle, decimals: 1, period: period,
                          tightDomain: true, kind: kind)
        }
    }

    // MARK: - PDF エクスポート

    private func doExport() {
        let hidden = Set(settings.graphHiddenPanels)
        let visibleKinds = settings.graphDisplayOrder
            .filter { !hidden.contains($0) }
            .compactMap { GraphKind(rawValue: $0) }

        let pdfW = PDFPanelExporter.contentW
        let panels: [AnyView] = visibleKinds.map { kind in
            AnyView(
                graphPanel(kind: kind)
                    .environment(\.chartAvailableWidth, pdfW)
                    .environment(\.exportScrollDate, scrollCapture.positions[kind])
            )
        }

        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("yMd")
        let now = Date()
        let fromDate = Calendar.current.date(byAdding: .day, value: -period.rawValue, to: now) ?? now
        let localizedPeriod = NSLocalizedString(period.label, comment: "")
        let subtitle = localizedPeriod + "  " + df.string(from: fromDate) + String(localized: "format.range.separator") + df.string(from: now)
        let title = String(localized: "tab.graph")

        let data = PDFPanelExporter.export(panels: panels, title: title, subtitle: subtitle)
        let tabName = String(localized: "tab.graph")
        let dateTag = Self.exportDateTag()
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

    private static func exportDateTag() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}

// MARK: - パネル共通部品

/// パネル全体のコンテナ
private struct PanelContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// 統計ラベル（ラベル: 値 の横1行）
private struct StatCell: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// 選択レコードの詳細行（パネル下部）
private struct SelectionDetailRow: View {
    let record: BodyRecord
    let detail: String      // 値＋単位の文字列
    let color: Color

    private var dateText: String {
        let c = Calendar.current
        let m  = c.component(.month,  from: record.dateTime)
        let d  = c.component(.day,    from: record.dateTime)
        let h  = c.component(.hour,   from: record.dateTime)
        let mn = c.component(.minute, from: record.dateTime)
        let y  = c.component(.year,   from: record.dateTime)
        return String(format: "%d/%d/%d %d:%02d", y, m, d, h, mn)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // 通常サイズ: 1行
            HStack(spacing: 6) {
                Image(systemName: record.dateOpt.icon)
                Text(record.dateOpt.displayName)
                Text(dateText).foregroundStyle(color.opacity(0.7))
                Spacer()
                Text(detail).bold()
            }
            // 大文字サイズ: 2行（区分+日時 左寄せ / 値+単位 右寄せ）
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: record.dateOpt.icon)
                    Text(record.dateOpt.displayName)
                    Text(dateText).foregroundStyle(color.opacity(0.7))
                }
                Text(detail)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(color)
        .font(.footnote)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - JSH 血圧区分

struct BpZone {
    let min: Int; let max: Int; let color: Color
}

// MARK: - BMI区分（日本肥満学会 JASSO基準）

struct BMIZone {
    let min: Double; let max: Double; let color: Color; let swatch: Color; let label: String
}

let bmiZones: [BMIZone] = [
    .init(min:  0.0, max: 18.5, color: Color(red: 0.30, green: 0.60, blue: 0.95).opacity(0.13), swatch: Color(red: 0.30, green: 0.60, blue: 0.95), label: "bmi.underweight"),
    .init(min: 18.5, max: 25.0, color: Color(red: 0.18, green: 0.65, blue: 0.28).opacity(0.11), swatch: Color(red: 0.18, green: 0.65, blue: 0.28), label: "bmi.normalWeight"),
    .init(min: 25.0, max: 30.0, color: Color(red: 0.90, green: 0.75, blue: 0.10).opacity(0.13), swatch: Color(red: 0.90, green: 0.75, blue: 0.10), label: "bmi.obesity1"),
    .init(min: 30.0, max: 35.0, color: Color(red: 0.95, green: 0.45, blue: 0.10).opacity(0.14), swatch: Color(red: 0.95, green: 0.45, blue: 0.10), label: "bmi.obesity2"),
    .init(min: 35.0, max: 60.0, color: Color(red: 0.80, green: 0.10, blue: 0.10).opacity(0.15), swatch: Color(red: 0.80, green: 0.10, blue: 0.10), label: "bmi.obesity3Plus"),
]

/// JSH 2019 基準による血圧区分カラー（上・下の高い方で分類）
func jshColor(hi: Int, lo: Int) -> Color {
    if hi >= 180 || lo >= 110 { return Color(red: 0.80, green: 0.00, blue: 0.00) }
    if hi >= 160 || lo >= 100 { return Color(red: 0.95, green: 0.25, blue: 0.00) }
    if hi >= 140 || lo >= 90  { return Color(red: 1.00, green: 0.55, blue: 0.00) }
    if hi >= 130 || lo >= 80  { return Color(white: 0.20) }
    if hi >= 120              { return Color(red: 0.25, green: 0.72, blue: 0.35) }
    return Color(red: 0.20, green: 0.50, blue: 0.90)
}

let bpHiZones: [BpZone] = [
    .init(min:  80, max: 120, color: Color(red: 0.20, green: 0.50, blue: 0.90).opacity(0.09)),
    .init(min: 120, max: 130, color: Color(red: 0.45, green: 0.72, blue: 0.28).opacity(0.09)),
    .init(min: 130, max: 140, color: Color(white: 0.55).opacity(0.12)),
    .init(min: 140, max: 160, color: Color.orange.opacity(0.11)),
    .init(min: 160, max: 180, color: Color(red: 0.90, green: 0.30, blue: 0.10).opacity(0.12)),
    .init(min: 180, max: 220, color: Color(red: 0.75, green: 0.10, blue: 0.10).opacity(0.14)),
]

let bpLoZones: [BpZone] = [
    .init(min:  40, max:  80, color: Color(red: 0.20, green: 0.50, blue: 0.90).opacity(0.09)),
    .init(min:  80, max:  90, color: Color(white: 0.55).opacity(0.12)),
    .init(min:  90, max: 100, color: Color.orange.opacity(0.11)),
    .init(min: 100, max: 110, color: Color(red: 0.90, green: 0.30, blue: 0.10).opacity(0.12)),
    .init(min: 110, max: 140, color: Color(red: 0.75, green: 0.10, blue: 0.10).opacity(0.14)),
]

// MARK: - 血圧 分布バー

/// JSH ゾーン背景 + 測定範囲カプセル + 平均マーカーを Canvas で描画する横バー
struct BpDistributionBar: View {
    let label: String
    let color: Color
    let values: [Int]
    let zones: [BpZone]
    let barMin: Int
    let barMax: Int

    @Environment(\.colorScheme) private var colorScheme

    private var minVal: Int? { values.min() }
    private var maxVal: Int? { values.max() }
    private var avgVal: Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(label))
                .font(.caption.bold())
                .foregroundStyle(color)
                .frame(width: 14, alignment: .center)

            Canvas { ctx, size in
                let w = size.width; let h = size.height
                let span = CGFloat(barMax - barMin)
                func xf(_ v: Int) -> CGFloat { CGFloat(v - barMin) / span * w }

                // カプセル形にクリップ
                ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: h / 2))

                // ゾーン背景（ダークモードは opacity を増幅）
                let zoneOpacity: CGFloat = colorScheme == .dark ? 5.0 : 1.0
                for z in zones {
                    let x0 = xf(max(z.min, barMin))
                    let x1 = xf(min(z.max, barMax))
                    guard x1 > x0 else { continue }
                    ctx.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: h)),
                             with: .color(z.color.opacity(zoneOpacity)))
                }

                // 測定範囲カプセル（min〜max）
                if let mn = minVal, let mx = maxVal, mx > mn {
                    let rx = xf(mn); let rw = max(6, xf(mx) - rx)
                    ctx.fill(
                        Path(roundedRect: CGRect(x: rx, y: 2, width: rw, height: h - 4), cornerRadius: (h - 4) / 2),
                        with: .color(color.opacity(0.45))
                    )
                }

                // 平均マーカー（白抜き円）
                if let avg = avgVal {
                    let cx = xf(avg); let cy = h / 2; let r: CGFloat = 5
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                             with: .color(.white))
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - r + 1, y: cy - r + 1,
                                                      width: (r - 1) * 2, height: (r - 1) * 2)),
                               with: .color(color), lineWidth: 1.5)
                }
            }
            .frame(height: 16)
        }
    }
}

// MARK: - 共通 X 軸モディファイア

private extension View {
    /// タップのみで日付を選択／解除する（ドラッグは横スクロールへ通過させる）
    func tapToSelectDay(_ selectedDate: Binding<Date?>, validDays: Set<Date>) -> some View {
        chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { tap in
                    let tapX = tap.location.x
                    let tolerancePx: CGFloat = 44  // タップ許容範囲（ポイント）
                    // タップ位置に最も近い有効日をピクセル距離で探す
                    let nearest = validDays.compactMap { day -> (Date, CGFloat)? in
                        guard let x = proxy.position(forX: day) else { return nil }
                        return (day, abs(x - tapX))
                    }.min(by: { $0.1 < $1.1 })
                    guard let (day, distance) = nearest, distance <= tolerancePx else {
                        selectedDate.wrappedValue = nil   // 許容範囲外 → 選択解除
                        return
                    }
                    if let sel = selectedDate.wrappedValue,
                       Calendar.current.isDate(sel, inSameDayAs: day) {
                        selectedDate.wrappedValue = nil   // 同じ日を再タップ → 解除
                    } else {
                        selectedDate.wrappedValue = day
                    }
                }
        }
    }

    /// 横スクロール可能なX軸スクロール位置をキャプチャし、エクスポート時に再現する
    func standardXAxis(period: GraphPeriod, scrollPosition: Binding<Date>, kind: GraphKind? = nil, oldestDate: Date? = nil, newestDate: Date? = nil) -> some View {
        modifier(StandardXAxisModifier(period: period, scrollPosition: scrollPosition, kind: kind, oldestDate: oldestDate, newestDate: newestDate))
    }
}

private struct StandardXAxisModifier: ViewModifier {
    let period: GraphPeriod
    @Binding var scrollPosition: Date
    let kind: GraphKind?
    let oldestDate: Date?
    let newestDate: Date?
    @Environment(\.scrollCapture) private var scrollCapture
    @Environment(\.exportScrollDate) private var exportScrollDate

    func body(content: Content) -> some View {
        let domainEnd = (newestDate ?? Date()).addingTimeInterval(1 * 24 * 3600)

        if let exportStart = exportScrollDate {
            // PDF エクスポート: 固定ドメイン（スクロールなし）
            let exportEnd = exportStart.addingTimeInterval(TimeInterval(period.domainSeconds))
            content
                .chartXScale(domain: exportStart...exportEnd)
                .chartXAxis { xAxisMarks }
        } else {
            // 通常表示: スクロール可能
            let maxLookback = domainEnd.addingTimeInterval(-730 * 24 * 3600)
            let rawStart = oldestDate.map { max($0, maxLookback) } ?? domainEnd.addingTimeInterval(-TimeInterval(period.domainSeconds))
            let domainStart = min(rawStart.addingTimeInterval(-2 * 24 * 3600), domainEnd)
            content
                .chartXScale(domain: domainStart...domainEnd)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: period.domainSeconds)
                .chartScrollPosition(x: $scrollPosition)
                .onAppear {
                    scrollPosition = domainEnd.addingTimeInterval(-TimeInterval(period.domainSeconds))
                }
                .onChange(of: scrollPosition) { _, new in
                    if let kind { scrollCapture.positions[kind] = new }
                }
                .onChange(of: period) { _, newPeriod in
                    scrollPosition = domainEnd.addingTimeInterval(-TimeInterval(newPeriod.domainSeconds))
                }
                .chartXAxis { xAxisMarks }
        }
    }

    private var xAxisMarks: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: period.xAxisCount)) { value in
            AxisGridLine().foregroundStyle(.gray.opacity(0.2))
            AxisTick()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    let m = Calendar.current.component(.month, from: date)
                    let d = Calendar.current.component(.day, from: date)
                    Text("\(m)/\(d)").font(.caption)
                }
            }
        }
    }
}

// MARK: - 日次集計ヘルパー構造体

private struct DailyBpAvg: Identifiable {
    let date: Date
    let mean: Double
    let pp: Double
    var id: Date { date }
}

private struct DailyLineValue: Identifiable {
    let date: Date
    let avg: Double
    var id: Date { date }
}

private struct DailyCategoryLineValue: Identifiable {
    let date: Date
    let dateOpt: DateOpt
    let avg: Double
    var id: String { "\(dateOpt.rawValue)-\(date.timeIntervalSince1970)" }
}

// MARK: - 血圧グラフパネル

private struct DailyBp: Identifiable {
    let date: Date   // start of day
    let hi: Double
    let lo: Double
    var map: Double { (hi + 2 * lo) / 3 }
    var pp:  Double { hi - lo }
    var id: Date { date }
}

private struct DailyCategoryBp: Identifiable {
    let date: Date
    let dateOpt: DateOpt
    let hi: Double
    let lo: Double
    var id: String { "\(dateOpt.rawValue)-\(date.timeIntervalSince1970)" }
}

struct BpChartView: View {
    let records: [BodyRecord]
    let period: GraphPeriod

    private let cal = Calendar.current
    private var settings: AppSettings { AppSettings.shared }
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    @Environment(\.chartAvailableWidth) private var chartWidth
    @ScaledMetric(relativeTo: .body) private var scaledBase: CGFloat = 150

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }
    private var hiddenDateOptRawValues: Set<Int> {
        Set(settings.graphBpHiddenDateOpts)
    }
    private var visibleRecords: [BodyRecord] {
        let hidden = hiddenDateOptRawValues
        return validRecords.filter { record in
            // 未使用区分は凡例にも出さず、血圧グラフにも描画しない
            guard let dateOpt = DateOpt(rawValue: record.nDateOpt), dateOpt.isDefined else { return false }
            return !hidden.contains(dateOpt.rawValue)
        }
    }
    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { visibleRecords.filter { periodStart <= $0.dateTime } }

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private var dailyAverages: [DailyBp] {
        let grouped = Dictionary(grouping: visibleRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let hi = Double(recs.map(\.nBpHi_mmHg).reduce(0, +)) / Double(recs.count)
            let lo = Double(recs.map(\.nBpLo_mmHg).reduce(0, +)) / Double(recs.count)
            return DailyBp(date: date, hi: hi, lo: lo)
        }.sorted { $0.date < $1.date }
    }

    private var dailyCategoryAverages: [DailyCategoryBp] {
        let grouped = Dictionary(grouping: visibleRecords) { record in
            "\(record.nDateOpt)-\(dayStart(record.dateTime).timeIntervalSince1970)"
        }
        return grouped.compactMap { _, recs in
            guard let first = recs.first,
                  let dateOpt = DateOpt(rawValue: first.nDateOpt), dateOpt.isDefined else { return nil }
            let hi = Double(recs.map(\.nBpHi_mmHg).reduce(0, +)) / Double(recs.count)
            let lo = Double(recs.map(\.nBpLo_mmHg).reduce(0, +)) / Double(recs.count)
            return DailyCategoryBp(date: dayStart(first.dateTime), dateOpt: dateOpt, hi: hi, lo: lo)
        }.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.dateOpt.rawValue < rhs.dateOpt.rawValue
            }
            return lhs.date < rhs.date
        }
    }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return visibleRecords.filter { dayStart($0.dateTime) == target }
    }

    private var avgHi: Int? {
        let v = periodRecords.map(\.nBpHi_mmHg); guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }
    private var avgLo: Int? {
        let v = periodRecords.map(\.nBpLo_mmHg); guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }

    private var avgMap: Int? {
        guard let hi = avgHi, let lo = avgLo else { return nil }
        return (hi + 2 * lo) / 3
    }
    private var avgPP: Int? {
        guard let hi = avgHi, let lo = avgLo else { return nil }
        return hi - lo
    }

    // Y軸タイトドメイン用（過去1年の上最大・下最小）
    private var yearRecords: [BodyRecord] {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return visibleRecords.filter { oneYearAgo <= $0.dateTime }
    }
    private var yearMaxHi: Int? { yearRecords.map(\.nBpHi_mmHg).max() }
    private var yearMinLo: Int? { yearRecords.map(\.nBpLo_mmHg).min() }

    private var bpLineMode: Binding<GraphBpLineMode> {
        Binding(
            get: { GraphBpLineMode(rawValue: settings.graphBpLineMode) ?? .average },
            set: { settings.graphBpLineMode = $0.rawValue }
        )
    }

    var body: some View {
        PanelContainer {
            // ヘッダー
            let bpRange: String? = {
                guard let mnHi = periodRecords.map(\.nBpHi_mmHg).min(),
                      let mxHi = periodRecords.map(\.nBpHi_mmHg).max(),
                      let mnLo = periodRecords.map(\.nBpLo_mmHg).min(),
                      let mxLo = periodRecords.map(\.nBpLo_mmHg).max() else { return nil }
                return "\(mnHi)–\(mxHi)／\(mnLo)–\(mxLo)"
            }()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(GraphKind.bp.title)).font(.callout.weight(.semibold))
                    Spacer()
                    if let txt = bpRange { StatCell(label: "text.range", value: txt) }
                    Text("unit.mmHg").font(.callout.weight(.semibold)).foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(GraphKind.bp.title)).font(.callout.weight(.semibold))
                    HStack {
                        if let txt = bpRange { StatCell(label: "text.range", value: txt) }
                        Spacer()
                        Text("unit.mmHg").font(.callout.weight(.semibold)).foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // チャート
            Chart {
                if bpLineMode.wrappedValue == .average {
                    // 上〜下の帯（日次平均）
                    ForEach(dailyAverages) { d in
                        AreaMark(
                            x: .value("record.datetime", d.date),
                            yStart: .value("metric.diastolic.short", d.lo),
                            yEnd:   .value("metric.systolic.short", d.hi)
                        )
                        .foregroundStyle(Color.purple.opacity(0.08))
                        .interpolationMethod(.catmullRom)
                    }
                    // 上ライン（日次平均を経由）
                    ForEach(dailyAverages) { d in
                        LineMark(x: .value("record.datetime", d.date), y: .value("metric.systolic.short", d.hi),
                                 series: .value("chart.series", "metric.systolic.short"))
                            .foregroundStyle(.red)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                    // 下ライン（日次平均を経由）
                    ForEach(dailyAverages) { d in
                        LineMark(x: .value("record.datetime", d.date), y: .value("metric.diastolic.short", d.lo),
                                 series: .value("chart.series", "metric.diastolic.short"))
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                } else {
                    // 区分別モードでは、ON区分ごとの日次平均を区分色で描く
                    ForEach(dailyCategoryAverages) { d in
                        LineMark(
                            x: .value("record.datetime", d.date),
                            y: .value("metric.systolic.short", d.hi),
                            series: .value("chart.series", "\(d.dateOpt.rawValue)-hi")
                        )
                        .foregroundStyle(d.dateOpt.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                    ForEach(dailyCategoryAverages) { d in
                        LineMark(
                            x: .value("record.datetime", d.date),
                            y: .value("metric.diastolic.short", d.lo),
                            series: .value("chart.series", "\(d.dateOpt.rawValue)-lo")
                        )
                        .foregroundStyle(d.dateOpt.color.opacity(0.72))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                // 上ポイント（個別レコード、同日は同X）
                ForEach(visibleRecords) { r in
                    PointMark(x: .value("record.datetime", dayStart(r.dateTime)), y: .value("metric.systolic.short", Double(r.nBpHi_mmHg)))
                        .foregroundStyle(r.dateOpt.color)
                        .symbolSize(18)
                }
                // 下ポイント（個別レコード、同日は同X）
                ForEach(visibleRecords) { r in
                    PointMark(x: .value("record.datetime", dayStart(r.dateTime)), y: .value("metric.diastolic.short", Double(r.nBpLo_mmHg)))
                        .foregroundStyle(r.dateOpt.color)
                        .symbolSize(18)
                }
                // 平均血圧ライン（graphBpMean ON 時のみ）
                if settings.graphBpMean && bpLineMode.wrappedValue == .average {
                    ForEach(dailyAverages) { d in
                        LineMark(x: .value("record.datetime", d.date), y: .value("metric.meanBloodPressure.short", d.map),
                                 series: .value("chart.series", "metric.meanBloodPressure.short"))
                            .foregroundStyle(.purple)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                            .interpolationMethod(.catmullRom)
                    }
                    if let last = dailyAverages.last {
                        PointMark(x: .value("record.datetime", last.date), y: .value("metric.meanBloodPressure.short", last.map))
                            .symbolSize(0)
                            .annotation(position: .trailing, alignment: .center, spacing: 3) {
                                Text("metric.meanBloodPressure.short")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.purple)
                            }
                    }
                }
                // 選択ルール
                if let date = selectedDate {
                    RuleMark(x: .value("chart.selected", dayStart(date)))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                // 目標ライン
                if settings.goalBpHi > 0 {
                    RuleMark(y: .value("chart.goalSystolic", settings.goalBpHi))
                        .foregroundStyle(.red.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .trailing, alignment: .center, spacing: 3) {
                            Text("goal.title")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                }
                if settings.goalBpLo > 0 {
                    RuleMark(y: .value("chart.goalDiastolic", settings.goalBpLo))
                        .foregroundStyle(.blue.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .trailing, alignment: .center, spacing: 3) {
                            Text("goal.title")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                }
            }
            .chartYTightDomain(enabled: true, minVal: yearMinLo, maxVal: yearMaxHi,
                               goalValues: [settings.goalBpLo, settings.goalBpHi])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(String(Int(v.rounded()))).font(.caption) } }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(visibleRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, kind: .bp, oldestDate: visibleRecords.first?.dateTime, newestDate: visibleRecords.last?.dateTime)
            .frame(height: adaptiveChartHeight(base: scaledBase, width: chartWidth))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            bpCategoryLegend
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            bpLineModePicker
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            // 選択詳細（同日複数レコードも全表示）
            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    let map = (r.nBpHi_mmHg + 2 * r.nBpLo_mmHg) / 3
                    let mapStr = settings.graphBpMean ? "  \(String(localized: "stat.avg")) \(map)" : ""
                    SelectionDetailRow(
                        record: r,
                        detail: "\(r.nBpHi_mmHg)／\(r.nBpLo_mmHg)\(mapStr) mmHg",
                        color: r.dateOpt.color
                    )
                }
            }

        }
    }

    private var bpCategoryLegend: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, alignment: .center, spacing: 8) {
            ForEach(DateOpt.allCases.filter(\.isDefined), id: \.self) { opt in
                let isOn = !hiddenDateOptRawValues.contains(opt.rawValue)
                Button {
                    toggleBpDistributionDateOpt(opt)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            .font(.caption2)
                        Image(systemName: opt.icon)
                            .font(.caption2)
                        Text(opt.displayName)
                            .font(.caption)
                    }
                    .foregroundStyle(isOn ? opt.color : Color.secondary)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bpLineModePicker: some View {
        HStack(spacing: 8) {
            Text("graph.bpLineMode")
                .font(.caption)
                .foregroundStyle(.secondary)
            AZRadioPicker(
                options: GraphBpLineMode.allCases,
                selection: bpLineMode,
                minOptionWidth: 64,
                maxOptionWidth: 120,
                horizontalPadding: 10,
                optionSpacing: 4,
                groupPadding: 4,
                wrapsOptions: false,
                fillsWidth: false
            ) { mode in
                Text(LocalizedStringKey(mode.titleKey))
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Spacer(minLength: 0)
        }
    }

    private func toggleBpDistributionDateOpt(_ opt: DateOpt) {
        var hidden = hiddenDateOptRawValues
        if hidden.contains(opt.rawValue) {
            hidden.remove(opt.rawValue)
        } else {
            // グラフ専用のON/OFFとして統計とは独立して保存する
            hidden.insert(opt.rawValue)
        }
        settings.graphBpHiddenDateOpts = hidden.sorted()
    }
}

// MARK: - 脈圧グラフパネル

struct BpPpChartView: View {
    let records: [BodyRecord]
    let period: GraphPeriod
    var goalValue: Int = 0

    private let cal = Calendar.current
    private var settings: AppSettings { AppSettings.shared }
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    @Environment(\.chartAvailableWidth) private var chartWidth
    @ScaledMetric(relativeTo: .body) private var scaledBase: CGFloat = 120

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }
    private var hiddenDateOptRawValues: Set<Int> {
        Set(settings.graphBpHiddenDateOpts)
    }
    private var visibleRecords: [BodyRecord] {
        let hidden = hiddenDateOptRawValues
        return validRecords.filter { record in
            // 未使用区分は凡例にも出さず、脈圧グラフにも描画しない
            guard let dateOpt = DateOpt(rawValue: record.nDateOpt), dateOpt.isDefined else { return false }
            return !hidden.contains(dateOpt.rawValue)
        }
    }

    private var dailyPP: [DailyBpAvg] {
        let grouped = Dictionary(grouping: visibleRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let pp = Double(recs.map { $0.nBpHi_mmHg - $0.nBpLo_mmHg }.reduce(0, +)) / Double(recs.count)
            return DailyBpAvg(date: date, mean: pp, pp: pp)
        }.sorted { $0.date < $1.date }
    }

    private var dailyCategoryPP: [DailyCategoryLineValue] {
        let grouped = Dictionary(grouping: visibleRecords) { record in
            "\(record.nDateOpt)-\(dayStart(record.dateTime).timeIntervalSince1970)"
        }
        return grouped.compactMap { _, recs in
            guard let first = recs.first,
                  let dateOpt = DateOpt(rawValue: first.nDateOpt), dateOpt.isDefined else { return nil }
            let pp = Double(recs.map { $0.nBpHi_mmHg - $0.nBpLo_mmHg }.reduce(0, +)) / Double(recs.count)
            return DailyCategoryLineValue(date: dayStart(first.dateTime), dateOpt: dateOpt, avg: pp)
        }.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.dateOpt.rawValue < rhs.dateOpt.rawValue
            }
            return lhs.date < rhs.date
        }
    }

    private var ppValues: [(record: BodyRecord, value: Int)] {
        visibleRecords.map { r in (r, r.nBpHi_mmHg - r.nBpLo_mmHg) }
    }

    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodPPValues: [Int] {
        visibleRecords.filter { periodStart <= $0.dateTime }.map { $0.nBpHi_mmHg - $0.nBpLo_mmHg }
    }
    private var avgPP: Int? {
        guard !periodPPValues.isEmpty else { return nil }
        return Int((Double(periodPPValues.reduce(0, +)) / Double(periodPPValues.count)).rounded())
    }
    private var minPP: Int? { periodPPValues.min() }
    private var maxPP: Int? { periodPPValues.max() }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return visibleRecords.filter { dayStart($0.dateTime) == target }
    }

    private var bpLineMode: Binding<GraphBpLineMode> {
        Binding(
            get: { GraphBpLineMode(rawValue: settings.graphBpLineMode) ?? .average },
            set: { settings.graphBpLineMode = $0.rawValue }
        )
    }

    var body: some View {
        PanelContainer {
            // ヘッダー（血圧セクションと同スタイル）
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("metric.pulsePressure").font(.callout.weight(.semibold))
                    Spacer()
                    if let avg = avgPP { StatCell(label: "stat.avg", value: "\(avg)") }
                    if let mn = minPP, let mx = maxPP { StatCell(label: "text.range", value: "\(mn)–\(mx)") }
                    Text("unit.mmHg").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("metric.pulsePressure").font(.callout.weight(.semibold))
                    HStack {
                        if let avg = avgPP { StatCell(label: "stat.avg", value: "\(avg)") }
                        if let mn = minPP, let mx = maxPP { StatCell(label: "text.range", value: "\(mn)–\(mx)") }
                        Spacer()
                        Text("unit.mmHg").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Chart {
                // 正常範囲帯（40〜50 mmHg）
                RectangleMark(yStart: .value("chart.normalLower", 40), yEnd: .value("chart.normalUpper", 50))
                    .foregroundStyle(Color.green.opacity(0.12))
                // 正常範囲の境界線
                RuleMark(y: .value("chart.normalLower", 40))
                    .foregroundStyle(Color.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                RuleMark(y: .value("chart.normalUpper", 50))
                    .foregroundStyle(Color.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                if bpLineMode.wrappedValue == .average {
                    // 日次平均ライン
                    ForEach(dailyPP) { d in
                        LineMark(x: .value("record.datetime", d.date), y: .value("metric.pulsePressure", d.pp),
                                 series: .value("type", "pp"))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                } else {
                    // 区分別モードでは、ON区分ごとの日次平均を区分色で描く
                    ForEach(dailyCategoryPP) { d in
                        LineMark(
                            x: .value("record.datetime", d.date),
                            y: .value("metric.pulsePressure", d.avg),
                            series: .value("type", "\(d.dateOpt.rawValue)-pp")
                        )
                        .foregroundStyle(d.dateOpt.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                }
                // 個別ポイント
                ForEach(ppValues, id: \.record.dateTime) { item in
                    PointMark(x: .value("record.datetime", dayStart(item.record.dateTime)),
                              y: .value("metric.pulsePressure", Double(item.value)))
                        .foregroundStyle(item.record.dateOpt.color)
                        .symbolSize(16)
                }
                // 選択ルール
                if let date = selectedDate {
                    RuleMark(x: .value("chart.selected", dayStart(date)))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                // 目標ライン
                if goalValue > 0 {
                    RuleMark(y: .value("goal.title", goalValue))
                        .foregroundStyle(Color.orange.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .trailing, alignment: .center, spacing: 3) {
                            Text("goal.title")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.orange.opacity(0.7))
                        }
                }
            }
            .chartYTightDomain(enabled: true, minVal: minPP, maxVal: maxPP,
                               goalValues: [goalValue])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(String(Int(v.rounded()))).font(.caption) } }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(visibleRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, kind: .bpAvg, oldestDate: visibleRecords.first?.dateTime, newestDate: visibleRecords.last?.dateTime)
            .frame(height: adaptiveChartHeight(base: scaledBase, width: chartWidth))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    SelectionDetailRow(record: r,
                                       detail: "\(String(localized: "metric.pulsePressure")) \(r.nBpHi_mmHg - r.nBpLo_mmHg) \(String(localized: "unit.mmHg"))",
                                       color: r.dateOpt.color)
                }
            }
        }
    }

}

// MARK: - 汎用折れ線グラフパネル

private extension View {
    @ViewBuilder
    func chartYTightDomain(enabled: Bool, minVal: Int?, maxVal: Int?, goalValues: [Int] = []) -> some View {
        let goals = goalValues.filter { $0 > 0 }
        let lo = ([minVal].compactMap { $0 } + goals).min()
        let hi = ([maxVal].compactMap { $0 } + goals).max()
        if enabled, let lo, let hi, lo < hi {
            let pad = Swift.max(Double(hi - lo) * 0.15, 5.0)
            self.chartYScale(domain: (Double(lo) - pad)...(Double(hi) + pad))
        } else {
            self.chartYScale(domain: .automatic(includesZero: false))
        }
    }

    @ViewBuilder
    func chartYTightDomain(minVal: Double?, maxVal: Double?, goalValues: [Double] = []) -> some View {
        let goals = goalValues.filter { $0 > 0 }
        let lo = ([minVal].compactMap { $0 } + goals).min()
        let hi = ([maxVal].compactMap { $0 } + goals).max()
        if let lo, let hi, lo < hi {
            let pad = Swift.max((hi - lo) * 0.15, 0.5)
            self.chartYScale(domain: (lo - pad)...(hi + pad))
        } else {
            self.chartYScale(domain: .automatic(includesZero: false))
        }
    }
}

struct LineChartView: View {
    let records: [BodyRecord]
    let keyPath: KeyPath<BodyRecord, Int>
    let title: String
    let unit: String
    let color: Color
    let goalValue: Int
    var decimals: Int = 0
    let period: GraphPeriod
    var tightDomain: Bool = false
    var showMovingAverage: Bool = false
    var showAsBar: Bool = false
    var usesDateOptFilterAndLineMode: Bool = false
    var kind: GraphKind? = nil

    private let cal = Calendar.current
    private var settings: AppSettings { AppSettings.shared }
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    @Environment(\.chartAvailableWidth) private var chartWidth
    @ScaledMetric(relativeTo: .body) private var scaledBase: CGFloat = 120

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private var validRecords: [BodyRecord] {
        records.filter { $0[keyPath: keyPath] > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }
    private var hiddenDateOptRawValues: Set<Int> {
        Set(settings.graphBpHiddenDateOpts)
    }
    private var visibleRecords: [BodyRecord] {
        guard usesDateOptFilterAndLineMode else { return validRecords }
        let hidden = hiddenDateOptRawValues
        return validRecords.filter { record in
            // 心拍数グラフも血圧と同じ区分ON/OFF条件で描画する
            guard let dateOpt = DateOpt(rawValue: record.nDateOpt), dateOpt.isDefined else { return false }
            return !hidden.contains(dateOpt.rawValue)
        }
    }
    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { visibleRecords.filter { periodStart <= $0.dateTime } }

    private var dailyValues: [DailyLineValue] {
        let grouped = Dictionary(grouping: visibleRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let avg = Double(recs.map { $0[keyPath: keyPath] }.reduce(0, +)) / Double(recs.count)
            return DailyLineValue(date: date, avg: avg)
        }.sorted { $0.date < $1.date }
    }

    private var dailyCategoryValues: [DailyCategoryLineValue] {
        let grouped = Dictionary(grouping: visibleRecords) { record in
            "\(record.nDateOpt)-\(dayStart(record.dateTime).timeIntervalSince1970)"
        }
        return grouped.compactMap { _, recs in
            guard let first = recs.first,
                  let dateOpt = DateOpt(rawValue: first.nDateOpt), dateOpt.isDefined else { return nil }
            let avg = Double(recs.map { $0[keyPath: keyPath] }.reduce(0, +)) / Double(recs.count)
            return DailyCategoryLineValue(date: dayStart(first.dateTime), dateOpt: dateOpt, avg: avg)
        }.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.dateOpt.rawValue < rhs.dateOpt.rawValue
            }
            return lhs.date < rhs.date
        }
    }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return visibleRecords.filter { dayStart($0.dateTime) == target }
    }

    private var avgValue: Int? {
        let v = periodRecords.map { $0[keyPath: keyPath] }
        guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }
    private var minValue: Int? { periodRecords.map { $0[keyPath: keyPath] }.min() }
    private var maxValue: Int? { periodRecords.map { $0[keyPath: keyPath] }.max() }

    // Y軸タイトドメイン用（過去1年全体の最大最小）
    private var yearRecords: [BodyRecord] {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return visibleRecords.filter { oneYearAgo <= $0.dateTime }
    }
    private var yearMinValue: Int? { yearRecords.map { $0[keyPath: keyPath] }.min() }
    private var yearMaxValue: Int? { yearRecords.map { $0[keyPath: keyPath] }.max() }

    // 直近7件の移動平均（dailyValues の各インデックスで最大7件遡って平均）
    private var movingAverageValues: [DailyLineValue] {
        guard showMovingAverage else { return [] }
        let sorted = dailyValues
        return sorted.indices.map { i in
            let start = max(0, i - 6)
            let window = sorted[start...i]
            let avg = window.map { $0.avg }.reduce(0, +) / Double(window.count)
            return DailyLineValue(date: sorted[i].date, avg: avg)
        }
    }

    private var bpLineMode: Binding<GraphBpLineMode> {
        Binding(
            get: { GraphBpLineMode(rawValue: settings.graphBpLineMode) ?? .average },
            set: { settings.graphBpLineMode = $0.rawValue }
        )
    }

    private func fmt(_ v: Int) -> String { ValueFormatter.format(v, decimals: decimals) }

    var body: some View {
        PanelContainer {
            // ヘッダー
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(title)).font(.callout.weight(.semibold))
                    Spacer()
                    if let avg = avgValue { StatCell(label: "stat.avg", value: "\(fmt(avg))") }
                    if let mn = minValue, let mx = maxValue { StatCell(label: "text.range", value: "\(fmt(mn))–\(fmt(mx))") }
                    Text(LocalizedStringKey(unit)).font(.callout.weight(.semibold)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title)).font(.callout.weight(.semibold))
                    HStack {
                        if let avg = avgValue { StatCell(label: "stat.avg", value: "\(fmt(avg))") }
                        if let mn = minValue, let mx = maxValue { StatCell(label: "text.range", value: "\(fmt(mn))–\(fmt(mx))") }
                        Spacer()
                        Text(LocalizedStringKey(unit)).font(.callout.weight(.semibold)).foregroundStyle(color)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // チャート
            Chart {
                if showAsBar {
                    // 棒グラフ（日次平均）
                    ForEach(dailyValues) { d in
                        BarMark(
                            x: .value("record.datetime", d.date),
                            y: .value(unit, d.avg)
                        )
                        .foregroundStyle(color.opacity(0.75))
                    }
                } else {
                    // 移動平均ライン（直近7件）― エリア・ライン・ドットより背面になるよう先頭に描画
                    ForEach(movingAverageValues) { d in
                        LineMark(
                            x: .value("record.datetime", d.date),
                            y: .value("chart.movingAverage", d.avg),
                            series: .value("series", "ma")
                        )
                        .foregroundStyle(Color.orange.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                    if !usesDateOptFilterAndLineMode || bpLineMode.wrappedValue == .average {
                        // エリア（日次平均）
                        ForEach(dailyValues) { d in
                            AreaMark(
                                x: .value("record.datetime", d.date),
                                y: .value(unit, d.avg)
                            )
                            .foregroundStyle(
                                LinearGradient(colors: [color.opacity(0.25), color.opacity(0.0)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .interpolationMethod(.catmullRom)
                        }
                        // ライン（日次平均を経由）
                        ForEach(dailyValues) { d in
                            LineMark(
                                x: .value("record.datetime", d.date),
                                y: .value(unit, d.avg)
                            )
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                        }
                    } else {
                        // 区分別モードでは、ON区分ごとの日次平均を区分色で描く
                        ForEach(dailyCategoryValues) { d in
                            LineMark(
                                x: .value("record.datetime", d.date),
                                y: .value(unit, d.avg),
                                series: .value("series", "\(d.dateOpt.rawValue)-line")
                            )
                            .foregroundStyle(d.dateOpt.color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    // ポイント（個別レコード、同日は同X）
                    ForEach(visibleRecords) { r in
                        PointMark(
                            x: .value("record.datetime", dayStart(r.dateTime)),
                            y: .value(unit, Double(r[keyPath: keyPath]))
                        )
                        .foregroundStyle(r.dateOpt.color)
                        .symbolSize(16)
                    }
                }
                // 選択ルール
                if let date = selectedDate {
                    RuleMark(x: .value("chart.selected", dayStart(date)))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                // 目標ライン
                if goalValue > 0 {
                    RuleMark(y: .value("goal.title", goalValue))
                        .foregroundStyle(color.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .trailing, alignment: .center, spacing: 3) {
                            Text("goal.title")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color.opacity(0.7))
                        }
                }
            }
            .chartYTightDomain(enabled: tightDomain && !showAsBar, minVal: yearMinValue, maxVal: yearMaxValue,
                               goalValues: [goalValue])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(fmt(Int(v.rounded()))).font(.caption)
                        }
                    }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(visibleRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, kind: kind, oldestDate: visibleRecords.first?.dateTime, newestDate: visibleRecords.last?.dateTime)
            .frame(height: adaptiveChartHeight(base: scaledBase, width: chartWidth))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // 選択詳細（同日複数レコードも全表示）
            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    SelectionDetailRow(
                        record: r,
                        detail: "\(fmt(r[keyPath: keyPath])) \(NSLocalizedString(unit, comment: ""))",
                        color: r.dateOpt.color
                    )
                }
            }
        }
    }

}

// MARK: - BMIグラフパネル

private struct BMIChartView: View {
    let records: [BodyRecord]
    let heightCm: Int
    let period: GraphPeriod
    var goalValue: Int = 0  // ×10 スケール（例: 220 = 22.0）

    private let cal = Calendar.current
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    @State private var showBMIInfo = false
    private var isJapanese: Bool { Locale.preferredLanguages.first?.hasPrefix("ja") ?? true }
    @Environment(\.chartAvailableWidth) private var chartWidth
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var scaledBase: CGFloat = 120

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private func bmi(for record: BodyRecord) -> Double? {
        guard record.nWeight_10Kg > 0 else { return nil }
        let hm = Double(heightCm) / 100.0
        return (Double(record.nWeight_10Kg) / 10.0) / (hm * hm)
    }

    private var validRecords: [BodyRecord] {
        records.filter { bmi(for: $0) != nil }
            .sorted { $0.dateTime < $1.dateTime }
    }

    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { validRecords.filter { $0.dateTime >= periodStart } }

    private var dailyValues: [DailyLineValue] {
        let grouped = Dictionary(grouping: validRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let vals = recs.compactMap { bmi(for: $0) }
            let avg = vals.reduce(0.0, +) / Double(vals.count)
            return DailyLineValue(date: date, avg: avg)
        }.sorted { $0.date < $1.date }
    }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return validRecords.filter { dayStart($0.dateTime) == target }
    }

    private var avgValue: Double? {
        let v = periodRecords.compactMap { bmi(for: $0) }
        guard !v.isEmpty else { return nil }
        return v.reduce(0.0, +) / Double(v.count)
    }
    private var minValue: Double? { periodRecords.compactMap { bmi(for: $0) }.min() }
    private var maxValue: Double? { periodRecords.compactMap { bmi(for: $0) }.max() }

    private var yearMinBMI: Double? {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return validRecords.filter { $0.dateTime >= oneYearAgo }.compactMap { bmi(for: $0) }.min()
    }
    private var yearMaxBMI: Double? {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return validRecords.filter { $0.dateTime >= oneYearAgo }.compactMap { bmi(for: $0) }.max()
    }

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    var body: some View {
        PanelContainer {
            // ヘッダー（タイトル行 + 統計行の2段構成）
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("metric.bmi").font(.callout.weight(.semibold))
                    Button {
                        showBMIInfo = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.title3)
                            Text(isJapanese ? String(localized: "text.jassoStandard") : "WHO BMI")
                                .font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showBMIInfo, arrowEdge: .bottom) {
                        BMIStandardsPopover(isJapanese: isJapanese)
                    }
                    Spacer()
                }
                if avgValue != nil || (minValue != nil && maxValue != nil) {
                    HStack {
                        if let avg = avgValue { StatCell(label: "stat.avg", value: fmt(avg)) }
                        if let mn = minValue, let mx = maxValue { StatCell(label: "text.range", value: "\(fmt(mn))–\(fmt(mx))") }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // チャート
            Chart {
                // JASSO BMI 肥満度区分 背景帯
                ForEach(bmiZones, id: \.label) { z in
                    RectangleMark(
                        yStart: .value("chart.lowerBound", z.min),
                        yEnd:   .value("chart.upperBound", z.max)
                    )
                    .foregroundStyle(z.swatch.opacity(colorScheme == .dark ? 0.22 : 0.16))
                }
                // ゾーン境界ライン＋ゾーン名ラベル
                ForEach(bmiZones.dropFirst(), id: \.label) { z in
                    RuleMark(y: .value("chart.boundary", z.min))
                        .foregroundStyle(z.swatch.opacity(colorScheme == .dark ? 0.55 : 0.40))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                        .annotation(position: .overlay, alignment: .topLeading) {
                            Text(LocalizedStringKey(z.label))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(z.swatch.opacity(colorScheme == .dark ? 0.90 : 0.75))
                                .padding(.leading, 2)
                                .padding(.top, 1)
                        }
                }

                ForEach(dailyValues) { d in
                    AreaMark(
                        x: .value("record.datetime", d.date),
                        y: .value("metric.bmi", d.avg)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Color.cyan.opacity(0.25), Color.cyan.opacity(0.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                }
                ForEach(dailyValues) { d in
                    LineMark(
                        x: .value("record.datetime", d.date),
                        y: .value("metric.bmi", d.avg)
                    )
                    .foregroundStyle(Color.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(validRecords) { r in
                    if let b = bmi(for: r) {
                        PointMark(
                            x: .value("record.datetime", dayStart(r.dateTime)),
                            y: .value("metric.bmi", b)
                        )
                        .foregroundStyle(r.dateOpt.color)
                        .symbolSize(16)
                    }
                }
                if let date = selectedDate {
                    RuleMark(x: .value("chart.selected", dayStart(date)))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                // 目標ライン
                if goalValue > 0 {
                    let goalBMIDouble = Double(goalValue) / 10.0
                    RuleMark(y: .value("goal.title", goalBMIDouble))
                        .foregroundStyle(Color.cyan.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .trailing, alignment: .center, spacing: 3) {
                            Text("goal.title")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.cyan.opacity(0.7))
                        }
                }
            }
            .chartYTightDomain(minVal: yearMinBMI, maxVal: yearMaxBMI,
                               goalValues: [goalValue > 0 ? Double(goalValue) / 10.0 : 0])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(fmt(v)).font(.caption)
                        }
                    }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(validRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, kind: .bmi, oldestDate: validRecords.first?.dateTime, newestDate: validRecords.last?.dateTime)
            .frame(height: adaptiveChartHeight(base: scaledBase, width: chartWidth))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // 選択詳細
            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    if let b = bmi(for: r) {
                        SelectionDetailRow(
                            record: r,
                            detail: "BMI \(fmt(b))",
                            color: r.dateOpt.color
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 体重変化量グラフ

private struct DailyWeightChange: Identifiable {
    let id: Date
    let date: Date
    let change: Double  // kg（正 = 増加、負 = 減少）
}

struct WeightChangeChartView: View {
    let records: [BodyRecord]
    let period: GraphPeriod

    private let cal = Calendar.current
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    @Environment(\.chartAvailableWidth) private var chartWidth
    @ScaledMetric(relativeTo: .body) private var scaledBase: CGFloat = 100

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nWeight_10Kg > 0 }.sorted { $0.dateTime < $1.dateTime }
    }

    private var dailyAvg: [(date: Date, avg: Double)] {
        let grouped = Dictionary(grouping: validRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let avg = Double(recs.map { $0.nWeight_10Kg }.reduce(0, +)) / Double(recs.count) / 10.0
            return (date: date, avg: avg)
        }.sorted { $0.date < $1.date }
    }

    private var changeValues: [DailyWeightChange] {
        let avgs = dailyAvg
        guard avgs.count > 1 else { return [] }
        var result: [DailyWeightChange] = []
        for i in 1..<avgs.count {
            let change = avgs[i].avg - avgs[i - 1].avg
            result.append(DailyWeightChange(id: avgs[i].date, date: avgs[i].date, change: change))
        }
        return result
    }

    private var selectedChange: DailyWeightChange? {
        guard let date = selectedDate else { return nil }
        return changeValues.first { $0.date == dayStart(date) }
    }

    private var validDays: Set<Date> { Set(changeValues.map { $0.date }) }

    private var allChanges: [Double] { changeValues.map { $0.change } }
    private var minChange: Double? { allChanges.min() }
    private var maxChange: Double? { allChanges.max() }

    var body: some View {
        PanelContainer {
            HStack(alignment: .firstTextBaseline) {
                Text("metric.weightChange").font(.callout.weight(.semibold))
                Spacer()
                Text("unit.kg").font(.callout.weight(.semibold)).foregroundStyle(.indigo)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Chart {
                RuleMark(y: .value("chart.zero", 0))
                    .foregroundStyle(.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(changeValues) { d in
                    BarMark(
                        x: .value("record.datetime", d.date),
                        y: .value("metric.changeAmount", d.change)
                    )
                    .foregroundStyle(d.change >= 0 ? Color.orange.opacity(0.75) : Color.teal.opacity(0.75))
                }
                if let date = selectedDate {
                    RuleMark(x: .value("chart.selected", dayStart(date)))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartYTightDomain(minVal: minChange, maxVal: maxChange)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%+.1f", v)).font(.caption)
                        }
                    }
                }
            }
            .tapToSelectDay($selectedDate, validDays: validDays)
            .standardXAxis(period: period, scrollPosition: $scrollPosition, kind: .weightChange, oldestDate: changeValues.first?.date, newestDate: changeValues.last?.date)
            .frame(height: adaptiveChartHeight(base: scaledBase, width: chartWidth))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            if let ch = selectedChange {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: ch.change >= 0 ? "arrow.up" : "arrow.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ch.change >= 0 ? .orange : .teal)
                    Text(String(format: "%+.1f kg", ch.change))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(ch.change >= 0 ? Color.orange : Color.teal)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - BMI基準ポップアップ

private struct BMIStandardsPopover: View {
    let isJapanese: Bool
    private struct Row {
        let zone: BMIZone
        var rangeText: String {
            if zone.min <= 0  { return "< \(String(format: "%.1f", zone.max))" }
            if zone.max >= 60 { return "≥ \(String(format: "%.1f", zone.min))" }
            return "\(String(format: "%.1f", zone.min)) – \(String(format: "%.1f", zone.max))"
        }
    }
    private let rows = bmiZones.reversed().map { Row(zone: $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isJapanese ? String(localized: "text.jassoObesityClassification") : "WHO BMI Classification")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            Divider()
            ForEach(rows, id: \.zone.label) { row in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(row.zone.swatch.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                        .frame(width: 18, height: 18)
                    Text(LocalizedStringKey(row.zone.label))
                        .font(.callout)
                    Spacer()
                    Text(row.rangeText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().padding(.leading, 44)
            }
        }
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }
}
