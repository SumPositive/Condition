// 複数回測定の平均を記録するための専用シート
// 試行（行）× 計測項目（列）の表＋常時表示テンキー
// 保存時に各項目の平均値を1件の BodyRecord として登録する

import SwiftUI
import SwiftData
import AZDial

// MARK: - 列モデル

private enum AvgColumn: Hashable, CaseIterable {
    case bpHi, bpLo, pulse, weight, temp, bodyFat, skMuscle

    var spec: MeasureSpec {
        switch self {
        case .bpHi:     return MeasureRange.bpHi
        case .bpLo:     return MeasureRange.bpLo
        case .pulse:    return MeasureRange.pulse
        case .weight:   return MeasureRange.weight
        case .temp:     return MeasureRange.temp
        case .bodyFat:  return MeasureRange.bodyFat
        case .skMuscle: return MeasureRange.skMuscle
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .bpHi:     return "metric.systolic.short"
        case .bpLo:     return "metric.diastolic.short"
        case .pulse:    return "metric.heartRate"
        case .weight:   return "metric.weight"
        case .temp:     return "metric.bodyTemp"
        case .bodyFat:  return "metric.bodyFat"
        case .skMuscle: return "metric.skeletalMuscle"
        }
    }

    var color: Color {
        switch self {
        case .bpHi:     return .red
        case .bpLo:     return .blue
        case .pulse:    return .orange
        case .weight:   return .indigo
        case .temp:     return .pink
        case .bodyFat:  return .purple
        case .skMuscle: return .teal
        }
    }

    var hasDecimal: Bool { spec.decimals > 0 }

    /// 標準偏差の許容範囲（青=良好以下、赤=注意以上）
    var sdTolerance: (blue: Int, red: Int) {
        switch self {
        case .bpHi, .bpLo, .pulse:
            return (5, 10)
        case .weight:
            return (2, 5)
        case .temp:
            return (1, 3)
        case .bodyFat, .skMuscle:
            return (5, 15)
        }
    }
}

private struct AvgCell: Hashable {
    let column: AvgColumn
    let trial: Int          // 0 始まり
}

// MARK: - シート本体

struct MeasurementAverageView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var settings = AppSettings.shared

    @State private var dateTime: Date = Date()
    @State private var dateOpt: DateOpt = AppSettings.shared.autoDateOpt(for: Date())
    @State private var showDatePicker = false
    @State private var isDateOptExpanded = false

    /// 入力済みの値（nil は未入力）
    @State private var samples: [AvgColumn: [Int?]] = [:]
    /// 1回目セルに薄く表示するプレースホルダー値（同区分・1ヶ月以内の直近記録）
    @State private var firstTrialPlaceholders: [AvgColumn: Int] = [:]
    /// 表示中の試行数（1〜5）
    @State private var trialCount: Int = 1
    /// 現在フォーカス中のセル
    @State private var focused: AvgCell? = nil
    /// 入力中の文字列（フォーカス中セルに対応）
    @State private var inputText: String = ""

    /// キャンセル誤タップ防止
    @State private var isCancelArmed = false
    @State private var cancelArmTask: Task<Void, Never>? = nil

    /// 「次へ」ボタンを左右どちらに置くか（trueで左、falseで右、デフォルト右）
    @AppStorage("measurementAvg.nextOnLeft") private var nextOnLeft: Bool = false

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMdEjmm")
        return f
    }()

    private let maxTrials = 5

    // MARK: 表示する列

    private var columns: [AvgColumn] {
        let hidden = Set(settings.hiddenFields)
        var result: [AvgColumn] = []
        for raw in settings.graphPanelOrder {
            guard let kind = GraphKind(rawValue: raw), kind.isRecordField,
                  !hidden.contains(raw) else { continue }
            switch kind {
            case .bp:       result.append(.bpHi); result.append(.bpLo)
            case .pulse:    result.append(.pulse)
            case .weight:   result.append(.weight)
            case .temp:     result.append(.temp)
            case .bodyFat:  result.append(.bodyFat)
            case .skMuscle: result.append(.skMuscle)
            default:        break
            }
        }
        return result
    }

    // 表の有無
    private var hasAnyValue: Bool {
        for (_, arr) in samples where arr.contains(where: { $0 != nil }) { return true }
        return false
    }

    var body: some View {
        let content = NavigationStack {
            VStack(spacing: 0) {
                topMetaBar
                Divider()
                tableScroll
                Divider()
                keypadArea
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(systemName: "text.badge.plus")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(Text("record.measurementAvg.title"))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        handleCancelTapped()
                    } label: {
                        Text("action.cancel")
                            .font(hasAnyValue ? .caption2 : .body)
                            .foregroundColor(isCancelArmed ? .white : .primary)
                            .padding(.horizontal, hasAnyValue ? 6 : 0)
                            .padding(.vertical, hasAnyValue ? 3 : 0)
                            .background {
                                if isCancelArmed {
                                    Capsule().fill(Color.red)
                                }
                            }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { saveAndDismiss() }
                        .disabled(!hasAnyValue)
                        .bold()
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $dateTime) {
                    dateOpt = settings.autoDateOpt(for: dateTime)
                }
            }
            .interactiveDismissDisabled(hasAnyValue)
            .onAppear {
                if columns.isEmpty { return }
                ensureSamplesArrays()
                loadInitialDateOpt()
                if focused == nil, let first = columns.first {
                    focused = AvgCell(column: first, trial: 0)
                }
            }
            .onChange(of: dateOpt) { _, _ in
                // 区分を切り替えた直後でまだ入力していなければ、新しい区分の直近値で初期化し直す
                loadFirstTrialDefaultsFromRecent()
            }
            .onDisappear {
                cancelArmTask?.cancel()
            }
        }
        if settings.fontScale.followsSystem {
            content
        } else {
            content.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
        }
    }

    // MARK: 上部メタ情報（日時・区分）

    private var topMetaBar: some View {
        HStack(spacing: 8) {
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(Self.dateTimeFormatter.string(from: dateTime))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .font(.callout)
            }
            Spacer(minLength: 8)
            dateOptPicker
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var dateOptPicker: some View {
        var style = AZPickerStyle.form
        style.preservesLabelForegroundStyle = true
        return AZDropdownPicker(
            options: settings.orderedDefinedDateOpts,
            selection: $dateOpt,
            isExpanded: $isDateOptExpanded,
            minWidth: 150,
            style: style
        ) { opt in
            HStack(spacing: 6) {
                Image(systemName: opt.icon)
                    .foregroundStyle(opt.color)
                Text(opt.isDefined ? opt.displayName : opt.placeholderName)
                    .foregroundStyle(opt.color)
            }
            .font(.callout)
        }
    }

    // MARK: 表

    private var tableScroll: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 4) {
                    BeginnerHelpBanner(
                        hintKey: "record.measurementAvg.hint",
                        messageKey: "record.measurementAvg.help",
                        storageKey: "helpDismissed.record.measurementAvg",
                        compact: true
                    )
                    .padding(.leading, 40)
                    .padding(.bottom, 2)
                    headerRow
                    ForEach(0..<trialCount, id: \.self) { trial in
                        trialRow(trial: trial)
                    }
                    if trialCount < maxTrials {
                        addTrialButton
                            .padding(.leading, trialLabelWidth + 4)
                            .padding(.top, 2)
                    }
                    Divider().padding(.vertical, 4)
                    summaryRow(metric: .average)
                    summaryRow(metric: .standardDeviation)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: focused) { _, newValue in
                // フォーカス移動先が見切れているときだけ最小限の横スクロールで寄せる
                guard let cell = newValue else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(cell, anchor: nil)
                }
            }
        }
    }

    // 文字サイズに応じて列幅・行高さも少し大きくなるようにする
    @ScaledMetric(relativeTo: .footnote) private var trialLabelWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .callout) private var cellWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .callout) private var cellHeight: CGFloat = 42

    private var headerRow: some View {
        HStack(spacing: 6) {
            Group {
                if settings.userLevel == .expert {
                    // 達人モードでは、ヒント文の代わりに左上セルへ (?) アイコンだけ置く
                    BeginnerHelpBanner(
                        "record.measurementAvg.help",
                        storageKey: "helpDismissed.record.measurementAvg",
                        compact: true
                    )
                } else {
                    Color.clear
                }
            }
            .frame(width: trialLabelWidth, height: 24)
            ForEach(columns, id: \.self) { col in
                Text(col.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(col.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: cellWidth, height: 24)
            }
            Color.clear.frame(width: 28)
        }
    }

    private func trialRow(trial: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(trial + 1)")
                .font(.footnote.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: trialLabelWidth, alignment: .trailing)
            ForEach(columns, id: \.self) { col in
                cellButton(column: col, trial: trial)
            }
            Button {
                removeTrial(at: trial)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.callout)
                    .foregroundStyle(canRemoveTrial(at: trial) ? .red : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: cellHeight)
            .disabled(!canRemoveTrial(at: trial))
        }
    }

    @ViewBuilder
    private func cellButton(column: AvgColumn, trial: Int) -> some View {
        let cell = AvgCell(column: column, trial: trial)
        let isFocused = (focused == cell)
        Button {
            focus(cell)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? column.color.opacity(0.14) : Color(.systemGray6))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? column.color : Color(.separator),
                                  lineWidth: isFocused ? 1.5 : 0.5)
                Text(cellDisplayText(column: column, trial: trial, focused: isFocused))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(cellDisplayColor(column: column, trial: trial, focused: isFocused))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 4)
            }
            .frame(width: cellWidth, height: cellHeight)
        }
        .buttonStyle(.plain)
        .id(cell)
    }

    private func cellDisplayText(column: AvgColumn, trial: Int, focused: Bool) -> String {
        if focused, !inputText.isEmpty {
            return inputText
        }
        if let v = samples[column]?[trial] {
            return ValueFormatter.format(v, decimals: column.spec.decimals)
        }
        if let placeholder = effectivePlaceholder(for: column, trial: trial) {
            return ValueFormatter.format(placeholder, decimals: column.spec.decimals)
        }
        return "–"
    }

    /// 直近で参照できるプレースホルダーを返す。
    /// 1回目: 同区分1ヶ月以内の直近記録
    /// 2回目以降: 前行の値、なければ前行のプレースホルダー（再帰）
    private func effectivePlaceholder(for column: AvgColumn, trial: Int) -> Int? {
        if trial == 0 { return firstTrialPlaceholders[column] }
        if let prev = samples[column]?[trial - 1] { return prev }
        return effectivePlaceholder(for: column, trial: trial - 1)
    }

    /// inputText / 確定値 / プレースホルダー / spec.initVal の順でダイアル初期値を決める
    private func dialBinding(for cell: AvgCell) -> Binding<Int> {
        Binding(
            get: {
                if !inputText.isEmpty, let parsed = parsedInputText(for: cell.column) {
                    return parsed
                }
                if let v = samples[cell.column]?[cell.trial] { return v }
                if let p = effectivePlaceholder(for: cell.column, trial: cell.trial) { return p }
                return cell.column.spec.initVal
            },
            set: { newValue in
                // ダイアル操作は入力バッファをクリアして直接セルへ書く
                inputText = ""
                var arr = samples[cell.column] ?? Array(repeating: nil, count: trialCount)
                if arr.isEmpty { arr = Array(repeating: nil, count: trialCount) }
                arr[cell.trial] = min(max(newValue, cell.column.spec.min), cell.column.spec.max)
                samples[cell.column] = arr
            }
        )
    }

    private func parsedInputText(for column: AvgColumn) -> Int? {
        guard !inputText.isEmpty else { return nil }
        let normalized = inputText.hasSuffix(".") ? inputText + "0" : inputText
        let decimals = column.spec.decimals
        if decimals == 0 {
            return Int(normalized)
        }
        return Double(normalized).map {
            Int(($0 * pow(10.0, Double(decimals))).rounded())
        }
    }

    private func cellDisplayColor(column: AvgColumn, trial: Int, focused: Bool) -> Color {
        if focused, !inputText.isEmpty { return .primary }
        if samples[column]?[trial] != nil { return .primary }
        return Color(.tertiaryLabel)
    }

    private func canRemoveTrial(at trial: Int) -> Bool {
        if trialCount > 1 { return true }
        // 1行しかないときは、値が入っているときだけ削除（クリア）できる
        return columns.contains { samples[$0]?[trial] != nil }
    }

    private var addTrialButton: some View {
        Button {
            addTrial()
        } label: {
            Label("record.measurementAvg.addTrial", systemImage: "plus.circle.fill")
                .font(.callout.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .disabled(trialCount >= maxTrials)
    }

    // MARK: 平均・標準偏差 行

    private enum SummaryMetric { case average, standardDeviation }

    private func summaryRow(metric: SummaryMetric) -> some View {
        HStack(spacing: 6) {
            Group {
                switch metric {
                case .average:           Text("stat.average.short")
                case .standardDeviation: Text("stat.standardDeviation.short")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: trialLabelWidth, alignment: .trailing)
            ForEach(columns, id: \.self) { col in
                summaryCell(column: col, metric: metric)
            }
            Color.clear.frame(width: 28)
        }
    }

    @ViewBuilder
    private func summaryCell(column: AvgColumn, metric: SummaryMetric) -> some View {
        let values = enteredValues(for: column)
        Group {
            switch metric {
            case .average:
                if let avg = averageValue(values) {
                    Text(ValueFormatter.format(avg, decimals: column.spec.decimals))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.blue)
                } else {
                    Text("–")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            case .standardDeviation:
                if values.count >= 2, let sd = standardDeviation(values) {
                    Text(ValueFormatter.format(sd, decimals: column.spec.decimals))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(sdColor(sd, column: column))
                } else {
                    Text(" ")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: cellWidth, height: metric == .average ? 30 : 24)
    }

    private func enteredValues(for column: AvgColumn) -> [Int] {
        (samples[column] ?? []).compactMap { $0 }
    }

    private func averageValue(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0, +)
        return (sum + values.count / 2) / values.count
    }

    private func standardDeviation(_ values: [Int]) -> Int? {
        guard values.count >= 2 else { return nil }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let variance = values.reduce(0.0) { partial, v in
            let d = Double(v) - mean
            return partial + d * d
        } / Double(values.count)
        return Int(sqrt(variance).rounded())
    }

    private func sdColor(_ value: Int, column: AvgColumn) -> Color {
        let t = column.sdTolerance
        if value <= t.blue { return .blue }
        if value >= t.red { return .red }
        let p = Double(value - t.blue) / Double(t.red - t.blue)
        return Color(red: p, green: 0.48 * (1 - p), blue: (1 - p))
    }

    // MARK: テンキー

    private var keypadArea: some View {
        GeometryReader { proxy in
            // 全幅を4列等分（テンキー3列＋次へ1列）、間隔は keypadSpacing × 3
            let cellW = max(40, (proxy.size.width - 3 * keypadSpacing) / 4)
            VStack(spacing: 16) {
                // ダイアル行：テンキーと同じ横幅範囲に配置（サイド列ぶんの空白を反対側に）
                HStack(spacing: keypadSpacing) {
                    if nextOnLeft { Color.clear.frame(width: cellW) }
                    dialRow
                        .frame(maxWidth: .infinity)
                    if !nextOnLeft { Color.clear.frame(width: cellW) }
                }
                // テンキー行：テンキー＋「次へ」（トグルは「次へ」の真上に overlay）
                HStack(spacing: keypadSpacing) {
                    if nextOnLeft { sideNextButtonWithToggle(width: cellW) }
                    keypad
                    if !nextOnLeft { sideNextButtonWithToggle(width: cellW) }
                }
            }
        }
        .frame(height: dialRowHeight + 16 + keypadHeight)
        .padding(.top, 8)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private let dialRowHeight: CGFloat = 44
    private let keypadButtonH: CGFloat = 48
    private let keypadSpacing: CGFloat = 8
    private let toggleButtonHeight: CGFloat = 24
    private var keypadHeight: CGFloat { 4 * keypadButtonH + 3 * keypadSpacing }

    /// 「次へ」ボタンの真上 4pt にトグルを overlay 配置（次へ本体には影響なし）
    private func sideNextButtonWithToggle(width: CGFloat) -> some View {
        sideNextButton(width: width)
            .overlay(alignment: .top) {
                Button {
                    nextOnLeft.toggle()
                } label: {
                    // iOS 26 では inset 系の見栄えの良いシンボル、未収録 OS では矢印へフォールバック
                    Image(systemNameResolving: nextOnLeft
                          ? "inset.filled.righthalf.arrow.right.rectangle"
                          : "inset.filled.lefthalf.arrow.left.rectangle",
                          "arrow.left.and.right")
                        .font(.footnote.weight(.semibold))
                        .frame(width: width, height: toggleButtonHeight)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("record.measurementAvg.nextSideToggle"))
                .offset(y: -(toggleButtonHeight + 4))
            }
    }

    /// 縦長「次へ」ボタン本体（テンキーと同じ高さ）
    private func sideNextButton(width: CGFloat) -> some View {
        let enabled = (focused != nil)
        return Button {
            advanceFocus()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                Text("record.measurementAvg.next")
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .frame(width: width, height: keypadHeight)
            .foregroundStyle(enabled ? Color.accentColor : Color(.tertiaryLabel))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((enabled ? Color.accentColor : Color.gray).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var dialRow: some View {
        if let cell = focused {
            GeometryReader { proxy in
                // 94pt はステッパー幅、12pt は AZDialView 内部のステッパー〜ダイアル間スペース
                let dialW = max(80, min(220, proxy.size.width - 94 - 12))
                HStack {
                    Spacer(minLength: 0)
                    AZDialView(
                        value: dialBinding(for: cell),
                        min: cell.column.spec.min,
                        max: cell.column.spec.max,
                        step: 1,
                        stepperStep: 1,
                        decimals: cell.column.spec.decimals,
                        style: DialStyle.builtin(id: settings.dialStyle) ?? .shape,
                        dialWidth: dialW,
                        tuning: settings.dialTuning
                    )
                    .id(cell)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: dialRowHeight)
        } else {
            Color.clear.frame(height: dialRowHeight)
        }
    }

    private var keypad: some View {
        let cols = focused?.column
        let hasDecimal = cols?.hasDecimal ?? false
        let buttonH: CGFloat = keypadButtonH
        let spacing: CGFloat = keypadSpacing
        return VStack(spacing: spacing) {
            ForEach([[7, 8, 9], [4, 5, 6], [1, 2, 3]], id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { d in
                        digitKey(label: "\(d)", height: buttonH) { tapDigit(d) }
                    }
                }
            }
            GeometryReader { proxy in
                let cellW = (proxy.size.width - 2 * spacing) / 3
                HStack(spacing: spacing) {
                    if hasDecimal {
                        digitKey(label: "0", height: buttonH) { tapDigit(0) }
                            .frame(width: cellW)
                        digitKey(label: ".", height: buttonH) { tapDecimal() }
                            .frame(width: cellW)
                    } else {
                        // 整数項目では「0」を「.」の位置まで広げて押しやすくする
                        digitKey(label: "0", height: buttonH) { tapDigit(0) }
                            .frame(width: cellW * 2 + spacing)
                    }
                    deleteKey(height: buttonH) { tapDelete() }
                        .frame(width: cellW)
                }
            }
            .frame(height: buttonH)
        }
        .frame(height: keypadHeight)
        .disabled(focused == nil)
        .opacity(focused == nil ? 0.5 : 1)
    }

    private func digitKey(label: String, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title.weight(.medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: height)
    }

    private func deleteKey(height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "delete.left")
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: height)
    }

    // MARK: 入力ハンドリング

    /// 新規記録と同じロジックで区分の初期値を決める
    /// （まとめ時間内の直前区分 ＞ 推定 ＞ 時刻帯マップ）
    /// 続いて、決定した区分で1ヶ月以内の直近記録があれば1回目の初期値として読み込む。
    private func loadInitialDateOpt() {
        let now = dateTime
        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate<BodyRecord> { $0.dateTime < now && $0.dateTime < bodyRecordGoalDate },
            sortBy: [SortDescriptor(\BodyRecord.dateTime, order: .reverse)]
        )
        guard let allPrev = try? context.fetch(descriptor), let prev = allPrev.first else { return }

        let windowMinutes = settings.mergeWindowMinutes
        var resolved = false
        if windowMinutes > 0 {
            let diff = now.timeIntervalSince(prev.dateTime)
            if diff >= 0, diff <= TimeInterval(windowMinutes) * 60 {
                dateOpt = prev.dateOpt
                resolved = true
            }
        }
        if !resolved, settings.estimateDateOpt {
            dateOpt = DateOptEstimator.estimate(
                from: allPrev,
                targetDate: now,
                hourMap: settings.dateOptHourMap,
                referenceDate: now
            )
        }

        loadFirstTrialDefaultsFromRecent(allPrev: allPrev)
    }

    /// 同じ区分で1ヶ月以内の直近記録を、1回目セルのプレースホルダーとして読み込む
    /// （実際の値としては保存せず、淡色の参考表示にとどめる）
    private func loadFirstTrialDefaultsFromRecent(allPrev: [BodyRecord]? = nil) {
        firstTrialPlaceholders = [:]
        guard !columns.isEmpty else { return }

        let now = dateTime
        let cal = Calendar.current
        guard let oneMonthAgo = cal.date(byAdding: .month, value: -1, to: now) else { return }

        let records: [BodyRecord]
        if let allPrev {
            records = allPrev
        } else {
            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate<BodyRecord> { $0.dateTime < now && $0.dateTime < bodyRecordGoalDate },
                sortBy: [SortDescriptor(\BodyRecord.dateTime, order: .reverse)]
            )
            records = (try? context.fetch(descriptor)) ?? []
        }

        let targetRaw = dateOpt.rawValue
        guard let recent = records.first(where: {
            $0.nDateOpt == targetRaw && $0.dateTime >= oneMonthAgo
        }) else { return }

        for col in columns {
            let v: Int = {
                switch col {
                case .bpHi:     return recent.nBpHi_mmHg
                case .bpLo:     return recent.nBpLo_mmHg
                case .pulse:    return recent.nPulse_bpm
                case .weight:   return recent.nWeight_10Kg
                case .temp:     return recent.nTemp_10c
                case .bodyFat:  return recent.nBodyFat_10p
                case .skMuscle: return recent.nSkMuscle_10p
                }
            }()
            guard v > 0 else { continue }
            firstTrialPlaceholders[col] = v
        }
    }

    private func ensureSamplesArrays() {
        for col in columns where samples[col] == nil {
            samples[col] = Array(repeating: nil, count: trialCount)
        }
        for col in columns {
            var arr = samples[col] ?? []
            if arr.count < trialCount {
                arr.append(contentsOf: Array(repeating: nil, count: trialCount - arr.count))
            }
            samples[col] = arr
        }
    }

    private func focus(_ cell: AvgCell) {
        commitInputText()
        focused = cell
        inputText = ""
    }

    private func tapDigit(_ d: Int) {
        guard let cell = focused else { return }
        let decimals = cell.column.spec.decimals
        if inputText.contains(".") {
            let typed = decimalPlacesTyped()
            if typed >= decimals { return }
        }
        if inputText == "0" && d != 0 {
            inputText = String(d)
        } else {
            inputText += String(d)
        }
    }

    private func tapDecimal() {
        guard let cell = focused, cell.column.hasDecimal else { return }
        guard !inputText.contains(".") else { return }
        inputText = inputText.isEmpty ? "0." : inputText + "."
    }

    private func tapDelete() {
        guard let cell = focused else { return }
        if !inputText.isEmpty {
            inputText.removeLast()
            return
        }
        // 入力中バッファが空なら確定済みの値を消す
        if var arr = samples[cell.column] {
            arr[cell.trial] = nil
            samples[cell.column] = arr
        }
    }

    private func decimalPlacesTyped() -> Int {
        guard let dot = inputText.firstIndex(of: ".") else { return 0 }
        return inputText.distance(from: inputText.index(after: dot), to: inputText.endIndex)
    }

    /// 現在の inputText を、フォーカス中セルに反映する
    private func commitInputText() {
        guard let cell = focused, !inputText.isEmpty else { return }
        let normalized = inputText.hasSuffix(".") ? inputText + "0" : inputText
        let decimals = cell.column.spec.decimals
        let parsed: Int?
        if decimals == 0 {
            parsed = Int(normalized)
        } else {
            parsed = Double(normalized).map {
                Int(($0 * pow(10.0, Double(decimals))).rounded())
            }
        }
        guard let v = parsed else { return }
        let clamped = min(max(v, cell.column.spec.min), cell.column.spec.max)
        if var arr = samples[cell.column] {
            arr[cell.trial] = clamped
            samples[cell.column] = arr
        }
    }

    private func addTrial() {
        commitInputText()
        guard trialCount < maxTrials else { return }
        trialCount += 1
        for col in columns {
            var arr = samples[col] ?? []
            arr.append(nil)
            samples[col] = arr
        }
        // 新しい試行の先頭列にフォーカスを移す
        if let first = columns.first {
            focused = AvgCell(column: first, trial: trialCount - 1)
            inputText = ""
        }
    }

    private func removeTrial(at trial: Int) {
        commitInputText()
        if trialCount > 1 {
            trialCount -= 1
            for col in columns {
                var arr = samples[col] ?? []
                if trial < arr.count {
                    arr.remove(at: trial)
                }
                samples[col] = arr
            }
            // フォーカス位置を調整する
            if let cell = focused {
                if cell.trial == trial {
                    let newTrial = min(trial, trialCount - 1)
                    focused = AvgCell(column: cell.column, trial: newTrial)
                } else if cell.trial > trial {
                    focused = AvgCell(column: cell.column, trial: cell.trial - 1)
                }
            }
            inputText = ""
        } else {
            // 1試行目だけのとき：その行の値をクリアする（行は残す）
            for col in columns {
                var arr = samples[col] ?? []
                if trial < arr.count {
                    arr[trial] = nil
                }
                samples[col] = arr
            }
            inputText = ""
        }
    }

    private func advanceFocus() {
        commitInputText()
        guard let cell = focused,
              let idx = columns.firstIndex(of: cell.column) else { return }
        if idx + 1 < columns.count {
            focused = AvgCell(column: columns[idx + 1], trial: cell.trial)
        } else if cell.trial + 1 < trialCount {
            focused = AvgCell(column: columns[0], trial: cell.trial + 1)
        } else if trialCount < maxTrials {
            addTrial()
            return
        } else {
            // 末尾なら先頭へ戻す
            focused = AvgCell(column: columns[0], trial: 0)
        }
        inputText = ""
    }

    // MARK: キャンセル

    private func handleCancelTapped() {
        guard hasAnyValue else {
            dismiss()
            return
        }
        if isCancelArmed {
            clearCancelArmed()
            dismiss()
            return
        }
        isCancelArmed = true
        cancelArmTask?.cancel()
        cancelArmTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { isCancelArmed = false }
        }
    }

    private func clearCancelArmed() {
        cancelArmTask?.cancel()
        cancelArmTask = nil
        isCancelArmed = false
    }

    // MARK: 保存

    private func saveAndDismiss() {
        commitInputText()
        guard hasAnyValue else { return }

        let record = BodyRecord(dateTime: dateTime, dateOpt: dateOpt)
        record.dataSource = .appInput

        for col in columns {
            guard let avg = averageValue(enteredValues(for: col)) else { continue }
            switch col {
            case .bpHi:     record.nBpHi_mmHg    = avg
            case .bpLo:     record.nBpLo_mmHg    = avg
            case .pulse:    record.nPulse_bpm    = avg
            case .weight:   record.nWeight_10Kg  = avg
            case .temp:     record.nTemp_10c     = avg
            case .bodyFat:  record.nBodyFat_10p  = avg
            case .skMuscle: record.nSkMuscle_10p = avg
            }
        }

        context.insert(record)
        do {
            try context.save()
            AppAnalytics.shared.logOperation(
                "measurement_average_sheet_save",
                parameters: ["trial_count": trialCount]
            )
            // 通常記録と同じく HealthKit へ書き戻す（設定が有効な場合）
            if settings.hkEnabled,
               HKSyncDirection(rawValue: settings.hkDirection)?.canWrite == true {
                HealthKitService.shared.scheduleWrite(
                    HealthKitValues(
                        date: record.dateTime,
                        bpHi: record.nBpHi_mmHg,
                        bpLo: record.nBpLo_mmHg,
                        pulse: record.nPulse_bpm,
                        temp: record.nTemp_10c,
                        weight: record.nWeight_10Kg,
                        bodyFat: record.nBodyFat_10p
                    )
                )
            }
            dismiss()
        } catch {
            AppAnalytics.shared.record(
                error: error,
                name: "measurement_average_sheet_save_failed",
                parameters: ["trial_count": trialCount]
            )
        }
    }
}
