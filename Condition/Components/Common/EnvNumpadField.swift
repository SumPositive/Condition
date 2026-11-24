// EnvNumpadField.swift
// 環境シートの数値入力。タップで専用テンキーシートを開く
//
// 測定値の NumpadValueText とは扱う型が違う（あちらは Int + 小数桁、こちらは String）。
// 環境の値は「未入力」を空文字で表す必要があり、気温は氷点下も入るため、
// 共用せず専用に持つ。見た目（キーの大きさ・色）は測定側と揃える

import SwiftUI

// MARK: - 入力項目

/// テンキーで入力する1項目の内容
struct EnvNumpadItem {
    let titleKey: LocalizedStringKey
    let text: Binding<String>
    /// 小数を受け付けるか（気温・気圧・室温）
    let decimal: Bool
    /// マイナスを受け付けるか（気温・室温）
    var allowsNegative: Bool = false
    /// 単位。値の右に薄く添える
    var unit: String? = nil
    /// この桁数を打ったら自動で小数点を入れる（気温の 302 → 30.2）
    var autoDecimalAfter: Int? = nil
    /// 打てる値の範囲。範囲外は決定できない
    let range: ClosedRange<Double>
}

// MARK: - 入力行

/// 「ラベル ＋ 数値」の行。タップするとテンキーシートが開く
struct EnvNumpadField: View {
    let item: EnvNumpadItem
    /// 値を打って決定したら、シートを閉じずに順に入力する項目（気温 → 湿度 → 気圧）
    var following: [EnvNumpadItem] = []

    @State private var showSheet = false
    @State private var settings = AppSettings.shared

    var body: some View {
        Button {
            showSheet = true
        } label: {
            LabeledContent(item.titleKey) {
                HStack(spacing: 4) {
                    if item.text.wrappedValue.isEmpty {
                        Text("environment.summary.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(item.text.wrappedValue)
                            .monospacedDigit()
                            .foregroundStyle(Color.primary)
                        if let unit = item.unit {
                            Text(unit)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            // ラベルを含む行全体を押せるようにする
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            // .sheet は親の dynamicTypeSize を引き継がないことがあるため明示する
            let sheet = EnvNumpadSheet(items: [item] + following)
            if settings.fontScale.followsSystem {
                sheet
            } else {
                sheet.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
            }
        }
    }
}

// MARK: - キー

private enum EnvNumpadKey {
    case digit(Int)
    case decimal
    case sign
    case delete
    case clear
}

// MARK: - 入力シート

private struct EnvNumpadSheet: View {
    /// 順に入力する項目（1つ以上）。最後の項目は決定で閉じる
    let items: [EnvNumpadItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 打ち込んだ値。空のうちは元の値をプレースホルダーとして薄く出す
    @State private var draft: String = ""
    /// ⌫ や C で明示的に消したか。
    /// 「何も触らず決定（＝元の値を残す）」と区別するために持つ
    @State private var didClear = false
    /// いま入力している項目の位置
    @State private var index = 0

    /// いま入力している項目
    private var current: EnvNumpadItem { items[index] }

    private var isCompact: Bool { UIScreen.main.bounds.height <= 700 }

    /// dynamicTypeSize に応じた UI スケール係数（測定側のテンキーと同じ刻み）
    private var uiScale: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large: return 1.00
        case .xLarge:          return 1.06
        case .xxLarge:         return 1.13
        case .xxxLarge:        return 1.20
        case .accessibility1:  return 1.30
        case .accessibility2:  return 1.42
        case .accessibility3:  return 1.55
        case .accessibility4:  return 1.68
        case .accessibility5:  return 1.82
        @unknown default:      return 1.00
        }
    }

    private var buttonH: CGFloat { 56 * uiScale }
    private var btnSpacing: CGFloat { 10 * uiScale }
    private var keypadH: CGFloat { buttonH * 4 + btnSpacing * 3 }

    private var idealHeight: CGFloat {
        let title: CGFloat = 24 * Swift.min(uiScale, 1.4)
        let display: CGFloat = 68 * Swift.min(uiScale, 1.4)
        // 範囲の案内は常に場所を取る（出し入れで高さが動かないようにする）
        let hint: CGFloat = 18 * Swift.min(uiScale, 1.4)
        let okBtn: CGFloat = 52 * uiScale
        return ceil(16 + title + 8 + display + 8 + hint + 12 + keypadH + 12 + okBtn + 8 + 34)
    }

    /// 未入力のうちは元の値を薄く出す。打ち始めたらそれを置き換える
    private var displayText: String {
        if !draft.isEmpty { return draft }
        let text = current.text.wrappedValue
        return text.isEmpty ? "0" : text
    }

    private var displayColor: Color {
        if isOutOfRange { return .red }
        return draft.isEmpty ? Color(.tertiaryLabel) : .primary
    }

    /// 打った値が範囲外か。入力中の「-」や「5.」は判定しない
    private var isOutOfRange: Bool {
        guard let value = Double(normalizedDraft) else { return false }
        return !current.range.contains(value)
    }

    /// 「5.」「-.」のような途中の形を数値にできる形へ整える
    private var normalizedDraft: String {
        var t = draft
        if t.hasSuffix(".") { t.removeLast() }
        if t.hasPrefix(".") { t = "0" + t }
        if t.hasPrefix("-.") { t = "-0" + t.dropFirst(1) }
        return t
    }

    /// 範囲の案内。桁を打ち間違えたときに何が悪いか分かるようにする
    private var rangeHint: String {
        let fmt: (Double) -> String = { v in
            v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
        }
        return "\(fmt(current.range.lowerBound)) 〜 \(fmt(current.range.upperBound))"
    }

    var body: some View {
        VStack(spacing: 12) {
            // どの項目を入力しているか分かるようにする
            Text(current.titleKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            Text(displayText)
                .font(.system(size: 52 * Swift.min(uiScale, 1.35),
                              weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(displayColor)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
                .animation(.snappy, value: draft)

            // 範囲外のときだけ、打てる範囲を知らせる
            Text(rangeHint)
                .font(.footnote)
                .foregroundStyle(isOutOfRange ? .red : .secondary)
                .opacity(isOutOfRange ? 1 : 0)

            EnvNumpad(
                hasDecimal: current.decimal,
                hasSign: current.allowsNegative,
                buttonH: buttonH,
                spacing: btnSpacing,
                onKey: handleKey
            )

            Button {
                confirm()
            } label: {
                Text("action.ok")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12 * uiScale)
            }
            .buttonStyle(.borderedProminent)
            // 範囲外のまま決定させない。押せてしまうと、保存時に黙って
            // 切り詰められた値が入り、打った値と食い違う
            .disabled(isOutOfRange)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .presentationDetents(isCompact ? [.large] : [.height(idealHeight), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - キー操作

    private func handleKey(_ key: EnvNumpadKey) {
        switch key {
        case .digit(let d):
            // 「0」から始めて別の数字を打ったら置き換える（007 のようにしない）
            if draft == "0" && d != 0 {
                draft = String(d)
            } else if draft == "-0" && d != 0 {
                draft = "-\(d)"
            } else {
                draft += String(d)
            }
            insertAutoDecimalIfNeeded()
        case .decimal:
            guard current.decimal, !draft.contains(".") else { return }
            draft = draft.isEmpty ? "0." : draft + "."
        case .sign:
            guard current.allowsNegative else { return }
            if draft.hasPrefix("-") {
                draft.removeFirst()
            } else {
                draft = "-" + draft
            }
        case .delete:
            if !draft.isEmpty {
                draft.removeLast()
                // 全部消したら「値を消す」意思表示として扱う
                if draft.isEmpty { didClear = true }
            } else {
                // 何も打っていない状態での ⌫ は、元の値を消す操作にする
                didClear = true
            }
        case .clear:
            draft = ""
            didClear = true
        }
    }

    /// 小数点を打たなくても、指定の桁数で自動的に入れる。
    /// 気温を「302」と打てば「30.2」になり、キー操作が1つ減る
    private func insertAutoDecimalIfNeeded() {
        guard let digits = current.autoDecimalAfter, current.decimal, !draft.contains(".") else { return }
        // 符号を除いた桁数で数える
        let body = draft.hasPrefix("-") ? String(draft.dropFirst()) : draft
        guard body.count == digits else { return }
        let sign = draft.hasPrefix("-") ? "-" : ""
        draft = sign + body + "."
    }

    // MARK: - 確定

    /// 決定ボタン。値を打ったときは続きの項目へ移り、それ以外は閉じる。
    /// 値を消しただけ・何も打っていないときは、続けて入力する意図が無いとみなす
    private func confirm() {
        apply()
        guard index + 1 < items.count,
              !draft.isEmpty, !current.text.wrappedValue.isEmpty else {
            dismiss()
            return
        }
        // シートを開き直さず中身だけ差し替える（閉じて開く間を待たせない）
        draft = ""
        didClear = false
        index += 1
    }

    private func apply() {
        // 何も打たずに決定したら元の値のまま。
        // 消したいときは ⌫ で全部消してから決定する
        guard !draft.isEmpty else {
            if didClear { current.text.wrappedValue = "" }
            return
        }
        // 「-」だけ、「5.」のような中途半端な入力を整える
        var normalized = draft
        if normalized == "-" || normalized == "." || normalized == "-." {
            current.text.wrappedValue = ""
            return
        }
        if normalized.hasSuffix(".") { normalized.removeLast() }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasPrefix("-.") { normalized = "-0" + normalized.dropFirst(1) }
        // 範囲外は書き戻さない（決定ボタンは無効だが、念のため）
        guard let value = Double(normalized), current.range.contains(value) else { return }
        current.text.wrappedValue = normalized
    }
}

// MARK: - テンキーレイアウト

private struct EnvNumpad: View {
    let hasDecimal: Bool
    let hasSign: Bool
    let buttonH: CGFloat
    let spacing: CGFloat
    let onKey: (EnvNumpadKey) -> Void

    private let rows = [[7, 8, 9], [4, 5, 6], [1, 2, 3]]
    private let hPadding: CGFloat = 20

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { digit in
                        EnvNumpadButton(label: "\(digit)", minH: buttonH) {
                            onKey(.digit(digit))
                        }
                    }
                }
            }
            // 下段：[± または空] [0] [. ] [⌫] を3列に収める
            GeometryReader { proxy in
                let cellW = (proxy.size.width - 2 * spacing) / 3
                HStack(spacing: spacing) {
                    leadingKey(cellW: cellW)
                    EnvNumpadButton(label: "0", minH: buttonH) { onKey(.digit(0)) }
                        .frame(width: cellW)
                    EnvNumpadButton(
                        systemImage: "delete.left",
                        minH: buttonH,
                        background: Color(.systemGray4)
                    ) { onKey(.delete) }
                        .frame(width: cellW)
                }
            }
            .frame(height: buttonH)
        }
        .padding(.horizontal, hPadding)
    }

    /// 左下のキー。小数と符号のどちらが要るかで入れ替える。
    /// 両方要る項目（気温）は符号を優先し、小数点は1つ上の段に入れない代わりに
    /// 「0」の左へ置く
    @ViewBuilder
    private func leadingKey(cellW: CGFloat) -> some View {
        if hasSign, hasDecimal {
            // 気温のように両方使う項目は、符号と小数点を半分ずつに分ける
            HStack(spacing: spacing) {
                EnvNumpadButton(label: "±", minH: buttonH) { onKey(.sign) }
                EnvNumpadButton(label: ".", minH: buttonH) { onKey(.decimal) }
            }
            .frame(width: cellW)
        } else if hasSign {
            EnvNumpadButton(label: "±", minH: buttonH) { onKey(.sign) }
                .frame(width: cellW)
        } else if hasDecimal {
            EnvNumpadButton(label: ".", minH: buttonH) { onKey(.decimal) }
                .frame(width: cellW)
        } else {
            // どちらも要らない項目は、まとめて消せるキーにする
            EnvNumpadButton(label: "C", minH: buttonH) { onKey(.clear) }
                .frame(width: cellW)
        }
    }
}

// MARK: - ボタン

private struct EnvNumpadButton: View {
    var label: String? = nil
    var systemImage: String? = nil
    let minH: CGFloat
    var background: Color = Color(.systemGray5)
    let action: () -> Void

    init(
        label: String,
        minH: CGFloat,
        background: Color = Color(.systemGray5),
        action: @escaping () -> Void
    ) {
        self.label = label
        self.minH = minH
        self.background = background
        self.action = action
    }

    init(
        systemImage: String,
        minH: CGFloat,
        background: Color = Color(.systemGray5),
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.minH = minH
        self.background = background
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.title2)
                } else {
                    Text(label ?? "").font(.title.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: minH)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
