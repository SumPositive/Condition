// NumpadValueText.swift
// 数値テキストをタップすると専用テンキーシートで入力できるコンポーネント

import SwiftUI

// MARK: - 公開コンポーネント

/// 値（＋単位）をタップするとテンキー入力シートを表示する Button
struct NumpadValueText: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let decimals: Int
    let color: Color
    var unit: LocalizedStringKey? = nil   // 単位ラベル（指定するとボタン内に表示）

    @State private var showSheet = false
    @State private var settings = AppSettings.shared

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 4) {
                valueLabel
                if let unit { unitLabel(unit) }
            }
            // 自然幅（1行分）を正確に申告することで、
            // 外側 dialRow の ViewThatFits が1行 vs 2行を正しく判断できる
            .fixedSize()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            // .sheet は親の dynamicTypeSize 環境を引き継がないことがあるため
            // AppSettings から直接フォントスケールを適用する
            let sheet = NumpadInputSheet(value: $value, min: min, max: max, decimals: decimals)
            if settings.fontScale.followsSystem {
                sheet
            } else {
                sheet.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
            }
        }
    }

    // MARK: - ラベルパーツ

    private var valueLabel: some View {
        ZStack(alignment: .trailing) {
            // 最大値を不可視で置き、常に最大桁数分の幅を確保する
            // → 値が2桁⇔3桁で切り替わっても1行/2行レイアウトが変動しない
            Text(ValueFormatter.format(max, decimals: decimals))
                .hidden()
            Text(ValueFormatter.format(value, decimals: decimals))
                .foregroundStyle(color)
        }
        .font(.title.bold().monospacedDigit())
    }

    private func unitLabel(_ unit: LocalizedStringKey) -> some View {
        Text(unit)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color.opacity(0.7))
    }
}

// MARK: - テンキーキー

private enum NumpadKey {
    case digit(Int)
    case decimal
    case delete
}

// MARK: - 入力シート（内部）

struct NumpadInputSheet: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let decimals: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var inputText: String = ""

    private var isCompact: Bool { UIScreen.main.bounds.height <= 700 }

    /// dynamicTypeSize に応じた UI スケール係数
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

    private var buttonH:  CGFloat { 56 * uiScale }
    private var btnSpacing: CGFloat { 10 * uiScale }
    private var keypadH:  CGFloat { buttonH * 4 + btnSpacing * 3 }

    /// シート高さ（dynamicTypeSize 連動）
    private var idealHeight: CGFloat {
        let display: CGFloat = 68 * Swift.min(uiScale,1.4)   // 表示行（大きくなりすぎない上限）
        let okBtn:   CGFloat = 52 * uiScale
        return ceil(16 + display + 12 + keypadH + 12 + okBtn + 8 + 34)
    }

    private var displayText: String {
        inputText.isEmpty ? ValueFormatter.format(value, decimals: decimals) : inputText
    }
    private var displayColor: Color {
        inputText.isEmpty ? Color(.tertiaryLabel) : .primary
    }

    private var decimalPlacesTyped: Int {
        guard let dot = inputText.firstIndex(of: ".") else { return 0 }
        return inputText.distance(from: inputText.index(after: dot), to: inputText.endIndex)
    }

    var body: some View {
        VStack(spacing: 12) {
            // 現在値表示
            HStack {
                Spacer()
                Text(displayText)
                    .font(.system(size: 52 * Swift.min(uiScale,1.35),
                                  weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(displayColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: inputText)
                Spacer()
            }
            .padding(.top, 16)

            // テンキー
            ConditionNumpad(
                hasDecimal: decimals > 0,
                buttonH: buttonH,
                spacing: btnSpacing,
                onKey: handleKey
            )

            // 決定ボタン
            Button {
                apply()
                dismiss()
            } label: {
                Text("action.ok")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12 * uiScale)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .presentationDetents(isCompact ? [.large] : [.height(idealHeight), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - キー操作

    private func handleKey(_ key: NumpadKey) {
        switch key {
        case .digit(let d):
            if inputText.contains(".") && decimalPlacesTyped >= decimals { return }
            if inputText == "0" && d != 0 {
                inputText = String(d)
            } else {
                inputText += String(d)
            }
        case .decimal:
            guard decimals > 0, !inputText.contains(".") else { return }
            inputText = inputText.isEmpty ? "0." : inputText + "."
        case .delete:
            if !inputText.isEmpty { inputText.removeLast() }
        }
    }

    // MARK: - 確定

    private func apply() {
        guard !inputText.isEmpty else { return }
        let normalized = inputText.hasSuffix(".") ? inputText + "0" : inputText
        let parsed: Int?
        if decimals == 0 {
            parsed = Int(normalized)
        } else {
            parsed = Double(normalized).map {
                Int(($0 * pow(10.0, Double(decimals))).rounded())
            }
        }
        guard let v = parsed, v >= min, v <= max else { return }
        value = v
    }
}

// MARK: - テンキーレイアウト

private struct ConditionNumpad: View {
    let hasDecimal: Bool
    let buttonH: CGFloat
    let spacing: CGFloat
    let onKey: (NumpadKey) -> Void

    private let rows = [[7, 8, 9], [4, 5, 6], [1, 2, 3]]
    private let hPadding: CGFloat = 20

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { digit in
                        NumpadDigitButton(label: "\(digit)", minH: buttonH) {
                            onKey(.digit(digit))
                        }
                    }
                }
            }
            // 下段：[.または空] [0] [⌫]
            HStack(spacing: spacing) {
                if hasDecimal {
                    NumpadDigitButton(label: ".", minH: buttonH) { onKey(.decimal) }
                } else {
                    Spacer()
                }
                NumpadDigitButton(label: "0", minH: buttonH) { onKey(.digit(0)) }
                NumpadDeleteButton(minH: buttonH) { onKey(.delete) }
            }
        }
        .padding(.horizontal, hPadding)
    }
}

// MARK: - ボタンパーツ

private struct NumpadDigitButton: View {
    let label: String
    let minH: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: minH)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct NumpadDeleteButton: View {
    let minH: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "delete.left")
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: minH)
                .background(Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
