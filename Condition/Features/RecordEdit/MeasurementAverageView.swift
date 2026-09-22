// 複数回測定の平均を記録するための専用シート
// 試行（行）× 計測項目（列）の表＋常時表示テンキー
// 保存時に各項目の平均値と最大5回分の測定値を BodyRecord として登録する

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
        // 血圧の上/下は全体共通色（オレンジ／琥珀）。左右（L赤・R緑）と被らせない。
        case .bpHi:     return .bpSystolic
        case .bpLo:     return .bpDiastolic
        case .pulse:    return .orange
        case .weight:   return .indigo
        case .temp:     return .pink
        case .bodyFat:  return .purple
        case .skMuscle: return .teal
        }
    }

    var hasDecimal: Bool { spec.decimals > 0 }

    /// 永続化モデルからこの列の測定値を取得する
    func values(in set: MeasurementSampleSet) -> [Int?] {
        switch self {
        case .bpHi:     return set.bpHi
        case .bpLo:     return set.bpLo
        case .pulse:    return set.pulse
        case .weight:   return set.weight
        case .temp:     return set.temp
        case .bodyFat:  return set.bodyFat
        case .skMuscle: return set.skMuscle
        }
    }

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

/// 編集開始時との比較に使う画面状態
private struct MeasurementAverageSnapshot: Equatable {
    let dateTime: Date
    let dateOpt: DateOpt
    let bpSide: BpSide
    let samples: [AvgColumn: [Int?]]
    let trialCount: Int
    // メモ欄（測定場所・機器／メモ1／メモ2／注意フラグ）
    let equipment: String
    let note1: String
    let note2: String
    let caution: Bool
}

/// ばらつき（標準偏差）が「赤」になっている主因の測定値を特定する。
///
/// 標準偏差そのものは「どの値が原因か」を教えてくれないため、
/// 平均から最も離れた値を主因とみなして黄色で知らせ、測り直しや修正を促す。
enum MeasurementOutlierLogic {

    /// 標準偏差（母標準偏差。表示用の計算と揃える）
    static func standardDeviation(_ values: [Int]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let variance = values.reduce(0.0) { partial, v in
            let d = Double(v) - mean
            return partial + d * d
        } / Double(values.count)
        return sqrt(variance)
    }

    /// ばらつきが大きい（＝SDが赤域）ときに、その主因となっている値の位置を返す。
    ///
    /// - SDが赤のしきい値未満なら空（＝警告しない）
    /// - 平均から最も離れた値を主因とする
    /// - 同じだけ離れた値が複数ある（例: 2回測定で上下に開いている）場合は、
    ///   どちらが誤りとも言えないため、その全てを対象にする
    ///
    /// - Parameters:
    ///   - values: 入力済みの測定値（試行順に nil を含む）
    ///   - redThreshold: この標準偏差以上で「赤」とみなすしきい値
    /// - Returns: 主因となる値の添字（values 内の位置）
    static func outlierIndices(values: [Int?], redThreshold: Int) -> Set<Int> {
        let entered = values.enumerated().compactMap { index, value in
            value.map { (index: index, value: $0) }
        }
        // 2件未満ではばらつきを論じられない
        guard entered.count >= 2 else { return [] }
        // 画面に出ている「赤い標準偏差」と一致させるため、表示と同じ丸めで判定する
        guard let sd = standardDeviation(entered.map(\.value)),
              Int(sd.rounded()) >= redThreshold else { return [] }

        let mean = Double(entered.reduce(0) { $0 + $1.value }) / Double(entered.count)
        let distances = entered.map { abs(Double($0.value) - mean) }
        guard let maxDistance = distances.max(), maxDistance > 0 else { return [] }

        // 浮動小数の誤差で取りこぼさないよう、ごく小さい許容差で「最遠」を判定する
        return Set(
            zip(entered, distances)
                .filter { abs($0.1 - maxDistance) < 0.000_001 }
                .map(\.0.index)
        )
    }
}

/// 空セルでダイアルを動かしたときの初回確定値を決める
enum MeasurementSampleDialLogic {
    static func acceptedValue(
        currentValue: Int?,
        placeholder: Int?,
        proposedValue: Int,
        hasInputText: Bool
    ) -> Int {
        // 未入力かつプレースホルダー表示中なら、初回は増減前の値を採用する
        if currentValue == nil, !hasInputText, let placeholder {
            return placeholder
        }
        return proposedValue
    }
}

/// 新規作成と編集で保存前確認の要否を判定する
enum MeasurementAverageChangeLogic {
    static func hasUnsavedChanges(
        isEditing: Bool,
        hasAnyValue: Bool,
        hasInputText: Bool,
        matchesInitialSnapshot: Bool
    ) -> Bool {
        if !isEditing { return hasAnyValue }
        return hasInputText || !matchesInitialSnapshot
    }
}

// MARK: - シート本体

struct MeasurementAverageView: View {

    /// nilは新規作成、値がある場合は保存済み平均記録の修正
    let record: BodyRecord?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = AppSettings.shared

    @State private var dateTime: Date = Date()
    @State private var dateOpt: DateOpt = AppSettings.shared.autoDateOpt(for: Date())
    /// 血圧の測定箇所（左右）。新規は常に不明（・）で開始する。
    @State private var bpSide: BpSide = .unknown
    @State private var showDatePicker = false
    @State private var showDeleteAlert = false
    @State private var isDateOptExpanded = false
    // 編集で日時を同じ「分」の別記録に重ねようとしたときの警告
    @State private var showSameMinuteAlert = false
    // 削除に失敗したとき、リトライ／キャンセルを選ばせるためのアラート表示フラグ
    @State private var showDeleteFailedAlert = false

    // メモ欄（ダイアル式の記録編集と同じ項目を、標準偏差の下に置く）
    @State private var equipment: String = ""
    @State private var note1: String = ""
    @State private var note2: String = ""
    @State private var caution: Bool = false
    @FocusState private var focusEquipment: Bool
    @FocusState private var focusNote1: Bool
    @FocusState private var focusNote2: Bool
    /// 候補選択直後にIMEが未確定文字を書き戻すのを防ぐ
    @State private var pendingEquipmentSelection: String?
    /// 候補カプセル1行分の高さ
    @ScaledMetric(relativeTo: .body) private var scaledEquipmentCandidateRowHeight: CGFloat = 34
    /// ソフトキーボードが表示中か（テンキーを隠す判断に使う実測値）
    @State private var isKeyboardVisible = false
    /// 進めるとメモ入力を終了させるトークン（AZMemoEditor への明示的な終了指示）
    @State private var memoDismissToken = 0
    /// メモ欄の自動スクロールを最新の対象だけに限定する
    @State private var memoScrollTask: Task<Void, Never>? = nil
    // キーボード表示時に各メモ行を送るためのスクロールアンカー
    private let equipmentAnchorID = "measurementAvg-equipment-anchor"
    private let note1AnchorID = "measurementAvg-note1-anchor"
    private let note2AnchorID = "measurementAvg-note2-anchor"
    /// 測定場所・機器の履歴（プリセット含む）を作るための既存記録
    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var recordsForEquipmentHistory: [BodyRecord]
    /// 測定場所・機器の候補プール。履歴が変わったときだけ作り直す
    @State private var equipmentCandidateStore = EquipmentCandidateStore()

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
    /// onAppearの再実行による入力内容の上書きを防ぐ
    @State private var didLoadInitialValues = false
    /// 編集開始時の状態を保持して未変更か判定する
    @State private var initialSnapshot: MeasurementAverageSnapshot?

    /// キャンセル誤タップ防止
    @State private var isCancelArmed = false
    @State private var cancelArmTask: Task<Void, Never>? = nil
    /// バックグラウンドを経由したか（未入力の新規シートの日時取り直し用）
    @State private var didEnterBackground = false

    /// 「次へ」ボタンを左右どちらに置くか（trueで左、falseで右、デフォルト右）
    @AppStorage("measurementAvg.nextOnLeft") private var nextOnLeft: Bool = false

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMdEjmm")
        return f
    }()

    private let maxTrials = MeasurementSampleSet.maxTrials

    init(record: BodyRecord? = nil) {
        self.record = record
    }

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
        // 修正時は現在非表示の項目でも保存済み測定値があれば表示する
        for column in AvgColumn.allCases
        where !result.contains(column) && !(samples[column] ?? []).compactMap({ $0 }).isEmpty {
            result.append(column)
        }
        return result
    }

    // 表の有無
    private var hasAnyValue: Bool {
        for (_, arr) in samples where arr.contains(where: { $0 != nil }) { return true }
        return false
    }

    /// 編集開始時から画面内容が変わっているか
    private var hasUnsavedChanges: Bool {
        if record == nil {
            return MeasurementAverageChangeLogic.hasUnsavedChanges(
                isEditing: false,
                // メモだけ書いた状態でも「入力あり」として扱い、誤操作で閉じないようにする
                hasAnyValue: hasAnyValue || hasAnyMemoInput,
                hasInputText: !inputText.isEmpty,
                matchesInitialSnapshot: false
            )
        }
        guard let initialSnapshot else { return false }
        // 入力途中の文字も含めて編集開始時との差を判定する
        return MeasurementAverageChangeLogic.hasUnsavedChanges(
            isEditing: true,
            hasAnyValue: hasAnyValue,
            hasInputText: !inputText.isEmpty,
            matchesInitialSnapshot: initialSnapshot == currentSnapshot
        )
    }

    private var currentSnapshot: MeasurementAverageSnapshot {
        MeasurementAverageSnapshot(
            dateTime: dateTime,
            dateOpt: dateOpt,
            bpSide: bpSide,
            samples: samples,
            trialCount: trialCount,
            equipment: equipment,
            note1: note1,
            note2: note2,
            caution: caution
        )
    }

    /// メモ欄に何か入力されているか（新規シートの「変更あり」判定に使う）
    private var hasAnyMemoInput: Bool {
        !equipment.isEmpty || !note1.isEmpty || !note2.isEmpty || caution
    }

    var body: some View {
        let content = NavigationStack {
            VStack(spacing: 0) {
                topMetaBar
                Divider()
                tableScroll
                // メモ入力中はソフトキーボードが出るので、テンキーは隠して入力欄を広く使う。
                // ここで if によりビューを取り除くと、フォーカス確定と同じフレームで
                // レイアウトが崩れて first responder を取り逃がし、キーボードが出ないことがある。
                // そのため subtree は残したまま高さ 0 に畳んで隠す。
                if !hidesKeypad { Divider() }
                keypadArea
                    .opacity(hidesKeypad ? 0 : 1)
                    .allowsHitTesting(!hidesKeypad)
            }
            // ソフトキーボードの表示／非表示を実測して、テンキーの出し分けに使う
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in
                isKeyboardVisible = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                isKeyboardVisible = false
                // スクロールでの終了は UIKit 側が閉じるため @FocusState が残る。
                // テンキー表示へ戻すために、ここで揃える。
                if isMemoFocused { dismissMemoFocus() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // アイコンだけでは何のシートか分からないので用途を文字で添える。
                    // Label はツールバー内だとアイコンだけに畳まれることがあるので HStack で並べる
                    HStack(spacing: 4) {
                        Image(systemName: "text.badge.plus")
                        Text("records.toolbar.measurement")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("record.measurementAvg.title"))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        handleCancelTapped()
                    } label: {
                        Text("action.cancel")
                            .font(hasUnsavedChanges ? .caption2 : .body)
                            .foregroundColor(isCancelArmed ? .white : .primary)
                            .padding(.horizontal, hasUnsavedChanges ? 6 : 0)
                            .padding(.vertical, hasUnsavedChanges ? 3 : 0)
                            .background {
                                if isCancelArmed {
                                    Capsule().fill(Color.red)
                                }
                            }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { saveAndDismiss() }
                        .disabled(!hasAnyValue || (record != nil && !hasUnsavedChanges))
                        .bold()
                }
                // 削除は「次へ」ボタンの真上に赤背景で配置（sideNextButtonWithToggle）
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $dateTime) {
                    dateOpt = settings.autoDateOpt(for: dateTime)
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .alert("record.delete.confirm", isPresented: $showDeleteAlert) {
                Button("action.delete", role: .destructive) {
                    deleteRecord()
                }
                Button("action.cancel", role: .cancel) {}
            }
            .alert("record.sameMinute.title", isPresented: $showSameMinuteAlert) {
                Button("action.ok", role: .cancel) { }
            } message: {
                Text("record.sameMinute.message")
            }
            .alert(
                "record.delete.failed.title",
                isPresented: $showDeleteFailedAlert
            ) {
                Button("action.retry") {
                    // アラートを一度確実に閉じてから再削除する。
                    // true→true のままだと SwiftUI が再表示をトリガーせず、
                    // 再失敗時にアラートが出ないため、フラグをクリアして次サイクルで実行する。
                    showDeleteFailedAlert = false
                    Task { @MainActor in deleteRecord() }
                }
                Button("action.cancel", role: .cancel) { showDeleteFailedAlert = false }
            } message: {
                Text("record.delete.failed.message")
            }
            .onAppear {
                equipmentCandidateStore.refresh(with: recordsForEquipmentHistory)
                guard !didLoadInitialValues else { return }
                didLoadInitialValues = true
                if let record {
                    loadSavedRecord(record)
                } else {
                    ensureSamplesArrays()
                    loadInitialDateOpt()
                }
                if columns.isEmpty { return }
                if focused == nil, let first = columns.first {
                    focused = AvgCell(column: first, trial: 0)
                }
            }
            .onChange(of: dateOpt) { _, _ in
                // 区分を切り替えた直後でまだ入力していなければ、新しい区分の直近値で初期化し直す
                loadFirstTrialDefaultsFromRecent()
            }
            // 履歴が変わったときだけ候補プールを作り直す（入力のたびの再集計を避ける）。
            // @Model は同一性で比較されるため、既存記録の測定場所を書き換えただけでは
            // 配列自体は変化しない。中身の並びを見て判定する。
            .onChange(of: equipmentHistorySignature) { _, _ in
                equipmentCandidateStore.refresh(with: recordsForEquipmentHistory)
            }
            // 未入力の新規シートがバックグラウンド→復帰したら、日時と区分を現在時刻基準へ取り直す。
            // 入力済み（値・入力途中の文字）や修正時は触らない。inactive の一過性遷移では動かさない。
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    didEnterBackground = true
                case .active:
                    guard didEnterBackground else { return }
                    didEnterBackground = false
                    refreshDateForForeground()
                default:
                    break
                }
            }
            .onDisappear {
                cancelArmTask?.cancel()
                memoScrollTask?.cancel()
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

    // MARK: 血圧の測定箇所（左右）

    /// 血圧の列が表示されているときだけ左右セグメントを出す
    private var showsBpSide: Bool {
        columns.contains(.bpHi) || columns.contains(.bpLo)
    }

    /// 「追加」ボタンと、血圧の部位（左右）セグメントを1行に並べる。
    /// 部位は上下共通なので列見出しの上に浮かせず、ここにラベル付きでまとめる。
    /// 血圧列が無いときはセグメントを出さない。追加ボタンは最大回数で消えるが、
    /// セグメントはそれと独立して表示し続ける。
    @ViewBuilder
    private var addTrialAndBpSideRow: some View {
        HStack(spacing: 8) {
            if trialCount < maxTrials {
                addTrialButton
            }
            if showsBpSide {
                // 追加ボタンのすぐ右に左寄せで並べ、余った幅は右側の余白として吸わせる
                Text("record.measurementAvg.bpSideLabel")
                    .font(.footnote)
                    // 「上」列見出しと同じ色をやや薄めて、血圧まわりの表示だと分かるようにする
                    .foregroundStyle(AvgColumn.bpHi.color.opacity(0.7))
                    .padding(.leading, 8)
                bpSideSegment
                Spacer(minLength: 0)
            }
        }
    }

    private var bpSideSegment: some View {
        AZRadioPicker(
            options: BpSide.allCases,
            selection: $bpSide,
            minOptionWidth: 0,
            maxOptionWidth: 60,
            horizontalPadding: 10,
            optionSpacing: 4,
            groupPadding: 2,
            wrapsOptions: false,
            fillsWidth: false,
            optionTint: { $0.badgeColor }
        ) { side in
            Text(side.code)
        }
    }

    // MARK: 表

    private var tableScroll: some View {
        ScrollViewReader { proxy in
            // 縦スクロールは画面全体、横スクロールは表だけに限定する。
            // メモ欄は画面幅で折り返して読めるよう、横スクロールの外側に置く。
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.horizontal) {
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
                            // 「追加」ボタンと血圧の部位セグメントを同じ行に置く。
                            // 部位は上下（収縮期・拡張期）共通なので列見出しの上に浮かせず、
                            // 表のスクロール範囲を圧迫しないこの行にまとめる。血圧列が無ければ非表示。
                            addTrialAndBpSideRow
                                .padding(.leading, trialLabelWidth + 4)
                                .padding(.top, 2)
                            Divider().padding(.vertical, 4)
                            summaryRow(metric: .average)
                            summaryRow(metric: .standardDeviation)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .scrollIndicators(.hidden)
                    // 標準偏差の下に、ダイアル式の記録編集と同じメモ欄を置く
                    memoSection
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
            .scrollIndicators(.hidden)
            // スクロールでの終了は標準の挙動に任せる（指の動きに追従して閉じる）
            .scrollDismissesKeyboard(.interactively)
            // メモ欄（AZMemoEditor）外のタップは AZMemoEditor 側のウィンドウ監視が閉じる。
            // ここは UITextView を持たない測定場所欄のための保険。
            .contentShape(Rectangle())
            .onTapGesture {
                if focusEquipment { dismissMemoFocus() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .bottom) {
                if hidesKeypad {
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if focusEquipment && !shownEquipmentCandidates.isEmpty {
                            // 確保領域の下端に候補バーを表示する
                            equipmentCandidateBar
                        }
                    }
                    .frame(height: memoInputReservedHeight)
                }
            }
            .onChange(of: focused) { _, newValue in
                // フォーカス移動先が見切れているときだけ最小限の横スクロールで寄せる
                guard let cell = newValue else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(cell, anchor: nil)
                }
            }
            // メモ欄にフォーカスが入ったら、キーボードに隠れないようその行まで送る
            .onChange(of: focusEquipment) { _, isOn in
                if isOn { scrollMemoIntoView(equipmentAnchorID, proxy: proxy, anchor: .top) }
            }
            .onChange(of: focusNote1) { _, isOn in
                if isOn { scrollMemoIntoView(note1AnchorID, proxy: proxy) }
            }
            .onChange(of: focusNote2) { _, isOn in
                if isOn { scrollMemoIntoView(note2AnchorID, proxy: proxy) }
            }
            // 入力で行が伸びたときも、フォーカス中の行を見えるところに保つ
            .onChange(of: note1) { _, _ in
                if focusNote1 { scrollMemoIntoView(note1AnchorID, proxy: proxy) }
            }
            .onChange(of: note2) { _, _ in
                if focusNote2 { scrollMemoIntoView(note2AnchorID, proxy: proxy) }
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
                let currentValue = samples[cell.column]?[cell.trial]
                let placeholder = effectivePlaceholder(for: cell.column, trial: cell.trial)
                let acceptedValue = MeasurementSampleDialLogic.acceptedValue(
                    currentValue: currentValue,
                    placeholder: placeholder,
                    proposedValue: newValue,
                    hasInputText: !inputText.isEmpty
                )
                inputText = ""
                var arr = samples[cell.column] ?? Array(repeating: nil, count: trialCount)
                if arr.isEmpty { arr = Array(repeating: nil, count: trialCount) }
                // 空セルの初回操作は増減せず、表示中のプレースホルダー値を確定する
                arr[cell.trial] = min(max(acceptedValue, cell.column.spec.min), cell.column.spec.max)
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
        // ばらつき（±SD）が赤い主因の値は、その数値だけを赤くして知らせる
        if isOutlierCell(column: column, trial: trial) { return .red }
        if focused, !inputText.isEmpty { return .primary }
        if samples[column]?[trial] != nil { return .primary }
        return Color(.tertiaryLabel)
    }

    /// 標準偏差が赤くなっている主因の値かどうか。
    /// 該当セルを黄色で示し、どの測定値がばらつきを生んでいるかを分かるようにする。
    private func isOutlierCell(column: AvgColumn, trial: Int) -> Bool {
        outlierTrials(for: column).contains(trial)
    }

    /// その列で、ばらつきの主因になっている試行の位置。
    /// 入力途中の文字列も反映して、確定前から色が追従するようにする。
    private func outlierTrials(for column: AvgColumn) -> Set<Int> {
        var values = samples[column] ?? []
        // 入力中のセルは、まだ確定していない値を使って判定する
        if let cell = focused, cell.column == column, !inputText.isEmpty,
           cell.trial < values.count {
            values[cell.trial] = parsedInputText(for: column)
        }
        return MeasurementOutlierLogic.outlierIndices(
            values: values,
            redThreshold: column.sdTolerance.red
        )
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

    // MARK: メモ欄

    /// メモ欄にフォーカスがあるか（スクロール送りの判定に使う）
    private var isMemoFocused: Bool {
        focusEquipment || focusNote1 || focusNote2
    }

    /// テンキーを隠すか。
    /// @FocusState は AZMemoEditor（UITextView）経由だと反映が1フレーム遅れることがあり、
    /// 「キーボードが出ているのにテンキーも出ている」状態になりうる。
    /// 実際のキーボード表示通知を真とし、フォーカス状態と OR で判定する。
    private var hidesKeypad: Bool {
        isKeyboardVisible || isMemoFocused
    }

    /// メモ入力を抜けてテンキー表示に戻す。
    /// @FocusState を落とすだけでは UITextView 側が first responder を握ったままの
    /// ことがあるため、UIKit にも明示的に終了を依頼して確実に閉じる。
    private func dismissMemoFocus() {
        memoScrollTask?.cancel()
        focusEquipment = false
        focusNote1 = false
        focusNote2 = false
        // AZMemoEditor（UITextView）は isFocused の false では閉じない設計なので、
        // トークンを進めて明示的に入力終了を指示する
        memoDismissToken &+= 1
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// キーボード表示中もメモ欄の入力行が隠れないよう、少し遅らせて寄せる
    private func scrollMemoIntoView(
        _ anchorID: String, proxy: ScrollViewProxy, anchor: UnitPoint = .bottom
    ) {
        memoScrollTask?.cancel()
        // キーボードのレイアウト確定後に最新の入力欄へ1度だけ寄せる
        memoScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, isFocusedMemoAnchor(anchorID) else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(anchorID, anchor: anchor)
            }
        }
    }

    /// 遅延中にフォーカス先が変わっていないか確認する
    private func isFocusedMemoAnchor(_ anchorID: String) -> Bool {
        switch anchorID {
        case equipmentAnchorID: focusEquipment
        case note1AnchorID: focusNote1
        case note2AnchorID: focusNote2
        default: false
        }
    }

    /// キーボード上に表示する候補の行数
    private static let equipmentCandidateRows = 2
    /// 候補カプセルの行間
    private let equipmentCandidateRowSpacing: CGFloat = 6

    /// 候補プールを作り直すべきかの判定材料（測定場所・機器の並び）
    private var equipmentHistorySignature: [String] {
        recordsForEquipmentHistory.map(\.sEquipment)
    }

    /// 入力語へ前方一致する候補を優先し、部分一致を続ける
    /// （候補プールの集計は履歴変更時のみ。equipmentCandidateStore を参照）
    private var shownEquipmentCandidates: [String] {
        equipmentCandidateStore.shownCandidates(matching: equipment)
    }

    /// 候補バーを2行分へ抑える
    private var equipmentCandidateBarHeight: CGFloat {
        let rowHeight = min(scaledEquipmentCandidateRowHeight, 48)
        let rows = CGFloat(Self.equipmentCandidateRows)
        return rowHeight * rows + equipmentCandidateRowSpacing * (rows - 1)
    }

    /// 入力欄を切り替えても変化させないキーボード上の確保高さ
    private var memoInputReservedHeight: CGFloat {
        max(60, equipmentCandidateBarHeight + 16)
    }

    /// キーボード直上へ測定場所・機器の候補をカプセル表示する
    private var equipmentCandidateBar: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                AZFlowLayout(
                    spacing: 8,
                    rowSpacing: equipmentCandidateRowSpacing,
                    alignment: .leading,
                    packToFill: true
                ) {
                    ForEach(shownEquipmentCandidates, id: \.self) { candidate in
                        Button {
                            selectEquipmentCandidate(candidate)
                        } label: {
                            equipmentCandidateLabel(
                                candidate,
                                maximumCapsuleWidth: max(0, geometry.size.width - 4)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // 3行目以降をスクロールしてもキーボードを閉じない
            .scrollDismissesKeyboard(.never)
        }
        .frame(height: equipmentCandidateBarHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        // 候補の選択やスクロールでキーボードを閉じない
        .azKeyboardDismissExcluded()
    }

    /// IMEを閉じてから候補値を確定する
    private func selectEquipmentCandidate(_ candidate: String) {
        pendingEquipmentSelection = candidate
        dismissMemoFocus()
        DispatchQueue.main.async {
            equipment = candidate
        }
    }

    /// 入力語へ一致した候補部分を強調する
    private func equipmentCandidateText(_ candidate: String) -> Text {
        let displayCandidate = nonbreakingEquipmentCandidate(candidate)
        let keyword = nonbreakingEquipmentCandidate(
            equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !keyword.isEmpty,
              let range = displayCandidate.range(of: keyword, options: .caseInsensitive) else {
            return Text(displayCandidate).foregroundStyle(.primary)
        }
        return Text(displayCandidate[displayCandidate.startIndex..<range.lowerBound]).foregroundStyle(.secondary)
            + Text(displayCandidate[range]).foregroundStyle(.primary).bold()
            + Text(displayCandidate[range.upperBound...]).foregroundStyle(.secondary)
    }

    /// 候補内の空白を改行されない空白へ置き換える
    private func nonbreakingEquipmentCandidate(_ candidate: String) -> String {
        candidate.map { $0.isWhitespace ? "\u{00A0}" : String($0) }.joined()
    }

    /// 自然幅を優先し、画面幅を超える候補だけ末尾を省略する
    private func equipmentCandidateLabel(
        _ candidate: String,
        maximumCapsuleWidth: CGFloat
    ) -> some View {
        // 空白を含む文字列もUIFontで実測して早すぎる省略を防ぐ
        let font = UIFont.systemFont(ofSize: equipmentCandidateFontSize, weight: .bold)
        let displayCandidate = nonbreakingEquipmentCandidate(candidate)
        let textWidth = ceil((displayCandidate as NSString).size(withAttributes: [.font: font]).width)
        let capsuleWidth = min(maximumCapsuleWidth, textWidth + 24)
        return equipmentCandidateText(candidate)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: max(0, capsuleWidth - 24), alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
    }

    /// アプリの文字サイズ設定に対応する候補計測用フォントサイズ
    private var equipmentCandidateFontSize: CGFloat {
        if settings.fontScale.followsSystem {
            return UIFont.preferredFont(forTextStyle: .body).pointSize
        }
        switch settings.fontScale {
        case .system:   return UIFont.preferredFont(forTextStyle: .body).pointSize
        case .standard: return 17
        case .large:    return 23
        case .xLarge:   return 33
        }
    }

    /// 標準偏差の下に置く、ダイアル式の記録編集と同じメモ欄
    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("record.memo.section")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            // 候補は入力欄ではなくキーボード直上へ表示する
            HStack(spacing: 8) {
                TextField("record.device", text: $equipment)
                    .id(equipmentAnchorID)
                    .focused($focusEquipment)
                    .onChange(of: focusEquipment) { _, isFocused in
                        // 再入力時は候補選択の保留値を解除する
                        if isFocused { pendingEquipmentSelection = nil }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { dismissMemoFocus() }
                    .onChange(of: equipment) { _, newValue in
                        // IMEの遅延書き戻しより候補選択を優先する
                        if let pending = pendingEquipmentSelection {
                            if newValue == pending {
                                pendingEquipmentSelection = nil
                            } else {
                                equipment = pending
                            }
                            return
                        }
                        // 測定場所・機器は最大100文字へ制限する
                        if 100 < newValue.count {
                            equipment = String(newValue.prefix(100))
                            return
                        }
                        // 末尾改行を除去
                        let trimmed = newValue.replacingOccurrences(
                            of: "\n+$", with: "", options: .regularExpression
                        )
                        if trimmed != newValue { equipment = trimmed }
                    }

                // 入力中だけ内容をまとめて消せるようにする
                if !equipment.isEmpty {
                    Button {
                        pendingEquipmentSelection = nil
                        equipment = ""
                        focusEquipment = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("action.clear"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            AZMemoEditor(
                placeholder: "record.memo1",
                text: $note1,
                isFocused: $focusNote1,
                dismissToken: memoDismissToken
            )
            .padding(.horizontal, 3)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .id(note1AnchorID)
            AZMemoEditor(
                placeholder: "record.memo2",
                text: $note2,
                isFocused: $focusNote2,
                dismissToken: memoDismissToken
            )
            .padding(.horizontal, 3)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .id(note2AnchorID)

            Toggle(isOn: $caution) {
                HStack(spacing: 6) {
                    if caution {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("record.cautionFlag")
                }
            }
            .padding(.top, 2)
        }
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
        // メモ入力中は高さ 0 に畳んで隠す（ビュー自体は残す。理由は body 側のコメント参照）
        .frame(height: hidesKeypad ? 0 : dialRowHeight + 16 + keypadHeight)
        .padding(.top, hidesKeypad ? 0 : 8)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.bottom, hidesKeypad ? 0 : 8)
        .background(Color(.systemBackground))
        .clipped()
    }

    private let dialRowHeight: CGFloat = 44
    private let keypadButtonH: CGFloat = 48
    private let keypadSpacing: CGFloat = 8
    private var keypadHeight: CGFloat { 4 * keypadButtonH + 3 * keypadSpacing }

    /// 「次へ」ボタン本体の真上に、修正時は削除ボタン（赤い円形）、新規追加時は左右切り替えトグルを配置。
    private func sideNextButtonWithToggle(width: CGFloat) -> some View {
        sideNextButton(width: width)
            .overlay(alignment: .top) {
                if record != nil {
                    // 修正時：削除ボタン（ダイアル行の高さの赤い円形）
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: deleteButtonSize, height: deleteButtonSize)
                            .background(Circle().fill(Color.red))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("record.delete.button"))
                    // ダイアル行（keypad の 16pt 上・高さ dialRowHeight）の中央に合わせる
                    .offset(y: -(16 + dialRowHeight / 2 + deleteButtonSize / 2))
                } else {
                    // 新規追加時：削除が無いので左右切り替えトグルを表示
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
    }

    /// 削除ボタン（円形）の直径。ダイアル行の高さに収める。
    private var deleteButtonSize: CGFloat { dialRowHeight - 6 }
    /// 左右切り替えトグルの高さ
    private let toggleButtonHeight: CGFloat = 24

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

    /// 保存済みの平均記録と各試行値を修正画面へ復元する
    private func loadSavedRecord(_ record: BodyRecord) {
        dateTime = record.dateTime
        dateOpt = record.dateOpt
        bpSide = record.bpSide
        equipment = record.sEquipment
        note1 = record.sNote1
        note2 = record.sNote2
        caution = record.bCaution
        guard let set = record.measurementSampleSet else {
            ensureSamplesArrays()
            initialSnapshot = currentSnapshot
            return
        }
        trialCount = max(1, min(maxTrials, set.trialCount))
        var loadedSamples: [AvgColumn: [Int?]] = [:]
        for column in AvgColumn.allCases {
            var values = column.values(in: set)
            if values.count < trialCount {
                values.append(contentsOf: Array(repeating: nil, count: trialCount - values.count))
            }
            loadedSamples[column] = Array(values.prefix(trialCount))
        }
        samples = loadedSamples
        // 復元完了後の状態を未変更の基準にする
        initialSnapshot = MeasurementAverageSnapshot(
            dateTime: record.dateTime,
            dateOpt: record.dateOpt,
            bpSide: record.bpSide,
            samples: loadedSamples,
            trialCount: trialCount,
            equipment: record.sEquipment,
            note1: record.sNote1,
            note2: record.sNote2,
            caution: record.bCaution
        )
    }

    /// 未入力の新規平均シートがバックグラウンド→復帰したとき、日時と区分を現在時刻基準へ取り直す。
    /// 値入力・入力途中の文字があるとき、または修正（record != nil）では何もしない。
    private func refreshDateForForeground() {
        guard record == nil, !hasAnyValue, !hasAnyMemoInput, inputText.isEmpty else { return }
        dateTime = Date()
        dateOpt  = settings.autoDateOpt(for: dateTime)   // 前回値が無い場合の既定区分
        // 開いた直後と同じ手順で、まとめ時間内の直前区分／推定により区分を取り直し、参考値も更新する。
        loadInitialDateOpt()
    }

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
        // 表のセルへ移るときはメモ入力を抜けて、ソフトキーボードをテンキーに戻す
        dismissMemoFocus()
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
        autoCompleteIfNeeded(cell.column)
    }

    private func tapDecimal() {
        guard let cell = focused, cell.column.hasDecimal else { return }
        guard !inputText.contains(".") else { return }
        inputText = inputText.isEmpty ? "0." : inputText + "."
    }

    /// 桁入力後、これ以上入力が不要と判定できたら値を確定して次のセルへ進む
    private func autoCompleteIfNeeded(_ column: AvgColumn) {
        guard column.spec.shouldAutoComplete(after: inputText) else { return }
        advanceFocus()
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
        guard hasUnsavedChanges else {
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

    /// 修正中の平均記録を削除する
    private func deleteRecord() {
        guard let record else { return }
        // 削除前に「アプリが書いたHK分の日時」を控える（削除後は参照できないため）
        let hkDeleteDate = HealthKitService.shared.appWrittenDateForDeletion(of: record)
        context.delete(record)
        do {
            try context.save()
            // 保存成功後にだけ、同日時のアプリ書込分を HealthKit からも削除する（失敗時は永続再試行）
            if let hkDeleteDate {
                HealthKitService.shared.scheduleDelete(at: hkDeleteDate)
            }
            showDeleteFailedAlert = false
            dismiss()
        } catch {
            // 失敗時は閉じずにエラーを提示し、リトライ／キャンセルを選べるようにする。
            // context はロールバック済みなので、リトライで再削除できる。
            // 技術的な詳細は Analytics のみに送り、画面にはローカライズ済みの案内文だけを見せる。
            context.rollback()
            AppAnalytics.shared.record(error: error, name: "measurement_average_sheet_delete_failed")
            showDeleteFailedAlert = true
        }
    }

    /// 保存対象として残す試行の位置（どこか1列でも値がある行）を、元の順序で返す
    private func nonEmptyTrialIndices() -> [Int] {
        (0..<trialCount).filter { trial in
            AvgColumn.allCases.contains { column in
                guard let arr = samples[column], trial < arr.count else { return false }
                return arr[trial] != nil
            }
        }
    }

    /// 空行を取り除いた、その列の測定値配列を作る
    private func compactedSamples(for column: AvgColumn, keeping trials: [Int]) -> [Int?] {
        let arr = samples[column] ?? []
        return trials.map { $0 < arr.count ? arr[$0] : nil }
    }

    private func saveAndDismiss() {
        commitInputText()
        guard hasAnyValue else { return }

        // 編集で日時を同じ「分」の別記録へ重ねようとしたら、保存せず警告して分をズラすよう促す。
        // 対象はアプリが HealthKit へ書き戻す記録のみ（HK由来は書き戻さないので除外）。
        if let editing = record,
           editing.dataSource != .hkImport, editing.dataSource != .hkModified,
           RecordEditViewModel.hasSameMinuteConflict(
               newDate: dateTime,
               previousDate: editing.dateTime,
               editing: editing,
               context: context
           ) {
            showSameMinuteAlert = true
            return
        }

        // 修正時は同じレコードを更新し、新規時だけレコードを作成する
        let target = record ?? BodyRecord(dateTime: dateTime, dateOpt: dateOpt)
        // 日時を変えた編集では、旧日時のアプリ書込サンプルを HealthKit から消すため、上書き前の日時を控える
        let previousHealthKitDate: Date? = record?.dateTime
        target.dateTime = dateTime
        target.dateOpt = dateOpt
        target.dataSource = record == nil ? .appInput : .appModified

        target.nBpHi_mmHg = 0
        target.nBpLo_mmHg = 0
        target.nPulse_bpm = 0
        target.nWeight_10Kg = 0
        target.nTemp_10c = 0
        target.nBodyFat_10p = 0
        target.nSkMuscle_10p = 0

        for col in AvgColumn.allCases {
            guard let avg = averageValue(enteredValues(for: col)) else { continue }
            switch col {
            case .bpHi:     target.nBpHi_mmHg    = avg
            case .bpLo:     target.nBpLo_mmHg    = avg
            case .pulse:    target.nPulse_bpm    = avg
            case .weight:   target.nWeight_10Kg  = avg
            case .temp:     target.nTemp_10c     = avg
            case .bodyFat:  target.nBodyFat_10p  = avg
            case .skMuscle: target.nSkMuscle_10p = avg
            }
        }

        // 左右は血圧固有。血圧が無い記録には付けない。
        target.bpSide = (target.nBpHi_mmHg > 0 || target.nBpLo_mmHg > 0) ? bpSide : .unknown

        // メモ欄（ダイアル式の記録編集と同じく前後の改行を落として保存する）
        target.sEquipment = equipment.trimmingCharacters(in: .newlines)
        target.sNote1 = note1.trimmingCharacters(in: .newlines)
        target.sNote2 = note2.trimmingCharacters(in: .newlines)
        target.bCaution = caution

        // 全列が空の行（＝入力せずに残った試行）は詰めて保存する。
        // 残しても平均には影響しないが、修正時に空行として復元されて紛らわしいため。
        // 一部の列だけ空の行は測定として有効なので残す。
        let keptTrials = nonEmptyTrialIndices()
        target.measurementSampleSet = MeasurementSampleSet(
            bpHi: compactedSamples(for: .bpHi, keeping: keptTrials),
            bpLo: compactedSamples(for: .bpLo, keeping: keptTrials),
            pulse: compactedSamples(for: .pulse, keeping: keptTrials),
            weight: compactedSamples(for: .weight, keeping: keptTrials),
            temp: compactedSamples(for: .temp, keeping: keptTrials),
            bodyFat: compactedSamples(for: .bodyFat, keeping: keptTrials),
            skMuscle: compactedSamples(for: .skMuscle, keeping: keptTrials)
        )

        if record == nil {
            context.insert(target)
        }
        do {
            try context.save()
            AppAnalytics.shared.logOperation(
                "measurement_average_sheet_save",
                // 画面上の行数ではなく、実際に測定値が入っていた行数を記録する
                parameters: ["trial_count": keptTrials.count]
            )
            // 通常記録と同じく HealthKit へ書き戻す（設定が有効な場合）
            if settings.hkEnabled,
               HKSyncDirection(rawValue: settings.hkDirection)?.canWrite == true {
                // 日時を変更した編集では、旧日時のアプリ書込サンプルを HealthKit から削除する。
                // 放置すると後のインポートで旧日時の記録が復活するため、空値クリアで消す。
                if let staleDate = RecordEditViewModel.staleHealthKitDate(
                    previousDate: previousHealthKitDate, newDate: target.dateTime
                ) {
                    HealthKitService.shared.scheduleDelete(at: staleDate)
                }
                HealthKitService.shared.scheduleWrite(
                    HealthKitValues(
                        date: target.dateTime,
                        bpHi: target.nBpHi_mmHg,
                        bpLo: target.nBpLo_mmHg,
                        pulse: target.nPulse_bpm,
                        temp: target.nTemp_10c,
                        weight: target.nWeight_10Kg,
                        bodyFat: target.nBodyFat_10p
                    )
                )
            }
            dismiss()
        } catch {
            // 保存に失敗したら、上書き済みのモデル（target.dateTime など）を巻き戻す。
            // 巻き戻さないと、再保存時に「新日時」が旧日時として取得され、
            // 実際の旧 HealthKit サンプルを削除できなくなる（新規時は挿入も取り消される）。
            context.rollback()
            AppAnalytics.shared.record(
                error: error,
                name: "measurement_average_sheet_save_failed",
                parameters: ["trial_count": trialCount]
            )
        }
    }
}
