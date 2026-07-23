//
//  AZ選択コントロール群
//  ドロップダウン、ポップオーバー、ラジオ形式の共通Pickerをまとめる
//
import SwiftUI
import UIKit

private extension DynamicTypeSize {
    /// UIKitの文字サイズ設定をSwiftUIのDynamicTypeSizeへ変換する
    init(uiContentSizeCategory category: UIContentSizeCategory) {
        switch category {
        case .extraSmall:
            self = .xSmall
        case .small:
            self = .small
        case .medium:
            self = .medium
        case .large:
            self = .large
        case .extraLarge:
            self = .xLarge
        case .extraExtraLarge:
            self = .xxLarge
        case .extraExtraExtraLarge:
            self = .xxxLarge
        case .accessibilityMedium:
            self = .accessibility1
        case .accessibilityLarge:
            self = .accessibility2
        case .accessibilityExtraLarge:
            self = .accessibility3
        case .accessibilityExtraExtraLarge:
            self = .accessibility4
        case .accessibilityExtraExtraExtraLarge:
            self = .accessibility5
        default:
            self = .large
        }
    }
}

/// 幅不足時のテキスト処理
enum AZPickerTextFitMode {
    /// 文字サイズを維持して複数行にする
    case wrap
    /// 1行表示を優先し、収まらない時だけ縮小する
    case scale(minimumScaleFactor: CGFloat = 0.50)
}

/// `AZDropdownPicker` のボタン右端に出すインジケータ
enum AZDropdownIndicator {
    /// インジケータを表示しない（デフォルト）
    case none
    /// 山型 chevron（展開で chevron.up、収納で chevron.down）
    case chevron
}

private extension View {
    /// Picker内テキストの幅不足時処理を適用する
    @ViewBuilder
    func azPickerTextFit(_ mode: AZPickerTextFitMode, alignment: TextAlignment) -> some View {
        switch mode {
        case .wrap:
            self
                .lineLimit(nil)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
        case .scale(let minimumScaleFactor):
            self
                .lineLimit(1)
                .minimumScaleFactor(minimumScaleFactor)
                .allowsTightening(true)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// AZPicker共通の見た目設定
struct AZPickerStyle {
    /// 選択ボタン・候補枠・ラジオ項目の角丸
    var cornerRadius: CGFloat = 8
    /// 選択ボタンとラジオ全体パネルの背景色
    var panelBackground: Color = Color(.secondarySystemGroupedBackground)
    /// ドロップダウン候補と未選択ラジオ項目の背景色
    var optionBackground: Color = Color(.systemBackground)
    /// 選択中の候補・ラジオ項目に重ねるアクセント背景の濃さ
    var selectedBackgroundOpacity: Double = 0.14
    /// 通常時の選択ボタン・候補・ラジオ項目の枠線の濃さ
    var borderOpacity: Double = 0.35
    /// 選択中または展開中の枠線の濃さ
    var selectedBorderOpacity: Double = 0.55
    /// ドロップダウン候補一覧とラジオ全体パネルの外枠線の濃さ
    var panelBorderOpacity: Double = 0.28
    /// ラジオ全体パネルだけ外枠線を表示するか
    var radioPanelShowsBorder: Bool = true
    /// ラジオ未選択項目の枠線を表示するか
    var radioOptionShowsBorder: Bool = true
    /// 選択ボタン・ラジオパネル・ラジオ項目の影の濃さ
    var shadowOpacity: Double = 0
    /// 選択ボタン・ラジオパネル・ラジオ項目の影のぼかし
    var shadowRadius: CGFloat = 0
    /// 選択ボタン・ラジオパネル・ラジオ項目の影の縦方向位置
    var shadowY: CGFloat = 0
    /// ラジオ全体パネル専用の薄い背景色
    var radioPanelBackground: Color = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.secondarySystemFill
            : UIColor.systemGray6.withAlphaComponent(0.96)
    })
    /// ラジオ未選択項目も薄く塗り、文字だけに見えないようにする
    var radioOptionBackground: Color = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.tertiarySystemFill
            : UIColor.systemBackground.withAlphaComponent(0.98)
    })
    /// ドロップダウン候補一覧パネルの角丸
    var popoverCornerRadius: CGFloat = 10
    /// ドロップダウン候補一覧パネルの影の濃さ
    var popoverShadowOpacity: Double = 0.10
    /// ドロップダウン候補一覧パネルの影のぼかし
    var popoverShadowRadius: CGFloat = 5
    /// ドロップダウン候補一覧パネルの影の縦方向位置
    var popoverShadowY: CGFloat = 2
    /// ドロップダウン各候補の枠内配置
    var dropdownOptionAlignment: Alignment = .leading
    /// ドロップダウン候補一覧内で候補枠を並べる横方向基準
    var dropdownOptionStackAlignment: HorizontalAlignment = .leading
    /// ドロップダウン各候補の複数行テキスト配置
    var dropdownOptionTextAlignment: TextAlignment = .leading
    /// ドロップダウン候補一覧パネル内側の余白
    var dropdownPopoverPadding: CGFloat = 10
    /// ドロップダウン各候補枠内の左右余白
    var dropdownOptionHorizontalPadding: CGFloat = 16
    /// ドロップダウン各候補枠内の上下余白
    var dropdownOptionVerticalPadding: CGFloat = 10
    /// ドロップダウン候補一覧だけに適用する文字サイズ範囲
    var dropdownPopoverDynamicTypeRange: ClosedRange<DynamicTypeSize> = DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5
    /// ドロップダウン選択中表示と候補一覧の幅不足時処理
    var dropdownTextFitMode: AZPickerTextFitMode = .wrap
    /// ラベル内で指定した色をそのまま使う
    var preservesLabelForegroundStyle: Bool = false
    /// 選択ボタン右端のインジケータデフォルトは非表示
    var dropdownIndicator: AZDropdownIndicator = .none

    /// 標準のフォーム向けスタイル
    static let form = AZPickerStyle()

    /// ドロップダウンの幅不足時処理だけを差し替える
    func dropdownTextFitMode(_ mode: AZPickerTextFitMode) -> AZPickerStyle {
        var copy = self
        copy.dropdownTextFitMode = mode
        return copy
    }
}

/// SPM化を見据えた、Dynamic Type対応のプルダウンPicker
struct AZDropdownPicker<Option: Hashable & Identifiable, Label: View>: View {
    @State private var buttonFrame: CGRect = .zero
    @State private var screenHeight: CGFloat = 0
    let options: [Option]
    @Binding var selection: Option
    @Binding var isExpanded: Bool
    var minWidth: CGFloat = 180
    var popoverDynamicTypeSize: DynamicTypeSize?
    /// 選択ボタンを親の横幅いっぱいに広げる
    var fillsWidth: Bool = false
    var style: AZPickerStyle = .form
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        collapsedButton
            .azDropdownPopover(
                isPresented: $isExpanded,
                anchorFrame: $buttonFrame,
                screenHeight: $screenHeight,
                backgroundColor: style.optionBackground,
                dynamicTypeSize: popoverDynamicTypeSize,
                dynamicTypeRange: style.dropdownPopoverDynamicTypeRange
            ) {
                expandedOptions
            }
            .zIndex(isExpanded ? 100 : 0)
    }

    private var popupOpensUpward: Bool {
        AZDropdownPopoverMetrics.opensUpward(anchorFrame: buttonFrame, screenHeight: screenHeight)
    }

    private var popupMaxHeight: CGFloat {
        let margin: CGFloat = 20
        let minimumHeight: CGFloat = 120
        return AZDropdownPopoverMetrics.maxHeight(
            anchorFrame: buttonFrame,
            screenHeight: screenHeight,
            margin: margin,
            minimumHeight: minimumHeight
        )
    }

    private var optionPanelWidth: CGFloat {
        max(minWidth, buttonFrame.width)
    }

    private var collapsedButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                selectedLabel
                indicatorView
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(
                minWidth: minWidth,
                maxWidth: fillsWidth ? .infinity : nil,
                alignment: .center
            )
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(style.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isExpanded ? Color.accentColor.opacity(style.selectedBorderOpacity) : Color.secondary.opacity(style.borderOpacity),
                        lineWidth: isExpanded ? 1.2 : 1
                    )
            )
            .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedLabel: some View {
        if style.preservesLabelForegroundStyle {
            label(selection)
                .font(.subheadline)
                .azPickerTextFit(style.dropdownTextFitMode, alignment: .center)
        } else {
            label(selection)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .azPickerTextFit(style.dropdownTextFitMode, alignment: .center)
        }
    }

    /// 選択ボタン右端のインジケータスタイル設定で非表示／chevron を切り替える
    @ViewBuilder
    private var indicatorView: some View {
        switch style.dropdownIndicator {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down").dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var expandedOptions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: style.dropdownOptionStackAlignment, spacing: 4) {
                    ForEach(options) { option in
                        optionButton(option)
                            // 選択中行へスクロールできるよう、各オプションに id を付与する
                            .id(option.id)
                    }
                }
                .frame(minWidth: optionPanelWidth, alignment: style.dropdownOptionAlignment)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: popupMaxHeight)
            // ポップオーバーが描画された直後に、選択中の行を中央に表示するようスクロールする
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(selection.id, anchor: .center)
                    }
                }
            }
        }
        .padding(style.dropdownPopoverPadding)
        // 内部パネルの塗りと枠線は描かず、popover背景と候補枠だけを使う
        .shadow(
            color: Color.black.opacity(style.popoverShadowOpacity),
            radius: style.popoverShadowRadius,
            x: 0,
            y: style.popoverShadowY
        )
    }

    private func optionButton(_ option: Option) -> some View {
        let isSelected = selection == option
        return Button {
            selection = option
            withAnimation(.easeOut(duration: 0.12)) {
                isExpanded = false
            }
        } label: {
            AZDropdownOptionButton(
                isSelected: isSelected,
                minWidth: optionPanelWidth,
                style: style
            ) {
                label(option)
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
enum AZDropdownPopoverMetrics {
    static func opensUpward(anchorFrame: CGRect, screenHeight: CGFloat) -> Bool {
        if anchorFrame == .zero {
            return true
        }
        let screenHeight = resolvedScreenHeight(screenHeight)
        let upperSpace = anchorFrame.minY
        let lowerSpace = screenHeight - anchorFrame.maxY
        return lowerSpace < upperSpace
    }

    static func maxHeight(
        anchorFrame: CGRect,
        screenHeight: CGFloat,
        margin: CGFloat = 20,
        minimumHeight: CGFloat = 120
    ) -> CGFloat {
        let screenHeight = resolvedScreenHeight(screenHeight)
        let upperSpace = max(minimumHeight, anchorFrame.minY - margin)
        let lowerSpace = max(minimumHeight, screenHeight - anchorFrame.maxY - margin)
        return opensUpward(anchorFrame: anchorFrame, screenHeight: screenHeight) ? upperSpace : lowerSpace
    }

    private static func resolvedScreenHeight(_ screenHeight: CGFloat) -> CGFloat {
        // 呼び出し側が画面高さを渡せない時は、MainActor上でUIKitから取得する
        if 0 < screenHeight {
            return screenHeight
        }
        return UIScreen.main.bounds.height
    }
}

struct AZDropdownPopoverModifier<PopoverContent: View>: ViewModifier {
    @State private var settings = AppSettings.shared
    @Binding var isPresented: Bool
    @Binding var anchorFrame: CGRect
    @Binding var screenHeight: CGFloat
    var backgroundColor: Color
    var dynamicTypeSize: DynamicTypeSize?
    var dynamicTypeRange: ClosedRange<DynamicTypeSize>
    @ViewBuilder let popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: AZDropdownPopoverMetrics.opensUpward(anchorFrame: anchorFrame, screenHeight: screenHeight) ? .bottom : .top
            ) {
                popoverContent()
                    // popover内は親環境を失いやすいため、標準で文字サイズを明示適用する
                    .dynamicTypeSize(resolvedDynamicTypeSize)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(backgroundColor)
                    // popoverの不透明背景を使い、内側パネルの角欠けを避ける
                    .padding(6)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            // 表示位置を測って、上下の広い側へ吹き出す
                            anchorFrame = proxy.frame(in: .global)
                            screenHeight = UIScreen.main.bounds.height
                        }
                        .onChange(of: proxy.frame(in: .global)) { _, newValue in
                            anchorFrame = newValue
                            // 実画面の高さで上下余白を比べ、狭い側へ縮む判定を避ける
                            screenHeight = UIScreen.main.bounds.height
                        }
                }
            }
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        let baseSize: DynamicTypeSize
        if let dynamicTypeSize {
            baseSize = dynamicTypeSize
        } else if settings.fontScale.followsSystem {
            baseSize = DynamicTypeSize(uiContentSizeCategory: UIApplication.shared.preferredContentSizeCategory)
        } else {
            baseSize = settings.fontScale.dynamicTypeSize
        }

        if baseSize < dynamicTypeRange.lowerBound {
            return dynamicTypeRange.lowerBound
        }
        if dynamicTypeRange.upperBound < baseSize {
            return dynamicTypeRange.upperBound
        }
        return baseSize
    }
}

extension View {
    func azDropdownPopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        anchorFrame: Binding<CGRect>,
        screenHeight: Binding<CGFloat> = .constant(0),
        backgroundColor: Color = Color(.systemBackground),
        dynamicTypeSize: DynamicTypeSize? = nil,
        dynamicTypeRange: ClosedRange<DynamicTypeSize> = DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        modifier(
            AZDropdownPopoverModifier(
                isPresented: isPresented,
                anchorFrame: anchorFrame,
                screenHeight: screenHeight,
                backgroundColor: backgroundColor,
                dynamicTypeSize: dynamicTypeSize,
                dynamicTypeRange: dynamicTypeRange,
                popoverContent: content
            )
        )
    }
}

struct AZDropdownOptionButton<Label: View>: View {
    let isSelected: Bool
    var minWidth: CGFloat
    var lineLimit: Int? = nil
    var style: AZPickerStyle = .form
    @ViewBuilder let label: () -> Label

    var body: some View {
        optionLabel
            .padding(.horizontal, style.dropdownOptionHorizontalPadding)
            .padding(.vertical, style.dropdownOptionVerticalPadding)
            .frame(minWidth: minWidth, maxWidth: .infinity, alignment: style.dropdownOptionAlignment)
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(style.selectedBackgroundOpacity) : style.optionBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(style.selectedBorderOpacity) : Color.secondary.opacity(style.borderOpacity),
                        lineWidth: isSelected ? 1.2 : 1
                    )
            )
    }

    @ViewBuilder
    private var optionLabel: some View {
        if style.preservesLabelForegroundStyle {
            label()
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .azPickerTextFit(style.dropdownTextFitMode, alignment: style.dropdownOptionTextAlignment)
                .lineLimit(lineLimit)
        } else {
            label()
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .azPickerTextFit(style.dropdownTextFitMode, alignment: style.dropdownOptionTextAlignment)
                .lineLimit(lineLimit)
        }
    }
}

/// Dynamic Typeで欠けにくいラジオボタン型の選択UI
struct AZRadioPicker<Option: Hashable & Identifiable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    var minOptionWidth: CGFloat = 96
    var maxOptionWidth: CGFloat = 240
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 4
    /// 標準時は低めのセグメント相当、文字が大きい時は自然に高くする
    var minHeight: CGFloat = 28
    var optionSpacing: CGFloat = 4
    var groupPadding: CGFloat = 2
    var wrapsOptions: Bool = true
    /// 折り返さない時に各候補を均等幅で横いっぱいに広げる
    var fillsWidth: Bool = false
    var style: AZPickerStyle = .form
    /// ピルアニメ完了直後に呼ばれるコールバック（selection 確定前にプログレスを描画したい用途向け）
    var onTap: ((Option) -> Void)? = nil
    /// 候補ごとの文字色。nil を返す（未指定含む）と従来通り選択=アクセント／非選択=primary。
    var optionTint: ((Option) -> Color?)? = nil
    @ViewBuilder let label: (Option) -> Label

    /// 選択ピルを option 間で滑らかに移動させるための名前空間
    @Namespace private var pillNamespace
    /// ピル位置の即時更新用（重い親処理に巻き込まれず、タップと同じフレームで動き出す）
    @State private var pendingSelection: Option?

    /// 表示用：保留中があればそれ、なければバインディング値
    private var effectiveSelection: Option {
        pendingSelection ?? selection
    }

    var body: some View {
        optionLayout
            .padding(groupPadding)
            .background(
                // コンテナ：選択肢群を1つのグループとして見せる
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(style.radioPanelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(style.radioPanelShowsBorder ? 0.12 : 0),
                        lineWidth: style.radioPanelShowsBorder ? 1 : 0
                    )
            )
            .shadow(color: Color.black.opacity(max(style.shadowOpacity, 0.025)), radius: max(style.shadowRadius, 1.5), x: 0, y: max(style.shadowY, 0.8))
            .frame(maxWidth: wrapsOptions || fillsWidth ? .infinity : nil, alignment: .trailing)
            // 選択時に微かな触覚フィードバック（タップ直後に発火させたいので pendingSelection をトリガ）
            .sensoryFeedback(.selection, trigger: pendingSelection)
            // 親が selection を反映し終えたら保留状態を解除
            .onChange(of: selection) { _, newValue in
                if pendingSelection == newValue {
                    pendingSelection = nil
                }
            }
    }

    @ViewBuilder
    private var optionLayout: some View {
        if wrapsOptions {
            AZFlowLayout(spacing: optionSpacing, rowSpacing: optionSpacing) {
                optionButtons
            }
        } else {
            HStack(spacing: optionSpacing) {
                optionButtons
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .fixedSize(horizontal: !fillsWidth, vertical: false)
        }
    }

    private var optionButtons: some View {
        ForEach(options) { option in
            optionButton(option)
        }
    }

    private func optionButton(_ option: Option) -> some View {
        let isSelected = effectiveSelection == option
        return Button {
            guard effectiveSelection != option else { return }
            // ピルはスプリングで動くが、視覚的な到着タイミング（≒ response 時間）で
            // 即 selection を更新する。withAnimation completion は spring の settle まで
            // 待つため遅延が大きい
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                pendingSelection = option
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                // 連続タップ時は最新の保留選択だけを確定する
                if pendingSelection == option {
                    if let onTap {
                        // プログレスを先に開始し、数フレーム描画してから重い親処理へ進める
                        onTap(option)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            if pendingSelection == option {
                                selection = option
                            }
                        }
                    } else {
                        selection = option
                    }
                }
            }
        } label: {
            label(option)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(optionTint?(option) ?? (isSelected ? Color.accentColor : Color.primary))
                .lineLimit(fillsWidth ? 1 : nil)
                .minimumScaleFactor(fillsWidth ? 0.50 : 1)
                .allowsTightening(fillsWidth)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: !fillsWidth)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(
                    minWidth: minOptionWidth,
                    maxWidth: fillsWidth ? .infinity : maxOptionWidth,
                    minHeight: minHeight,
                    alignment: .center
                )
                .background {
                    // 選択中の項目だけにピルを置き、matchedGeometryEffect で滑らかに移動させる
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(style.selectedBackgroundOpacity))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        Color.accentColor.opacity(max(style.selectedBorderOpacity, 0.4)),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.accentColor.opacity(0.18), radius: 3, x: 0, y: 1)
                            .matchedGeometryEffect(id: "azRadioPill", in: pillNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// コントロール行を「見出し込み1行」「見出し＋操作部2段」の順に選ぶ
struct AZAdaptiveControlRow<Title: View, Control: View>: View {
    @ViewBuilder let title: () -> Title
    @ViewBuilder let control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                title()
                Spacer(minLength: 8)
                control()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                title()
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// ラジオ行を「見出し込み1行」「2段で選択肢1行」「選択肢折り返し」の順に選ぶ
struct AZAdaptiveRadioRow<Option: Hashable & Identifiable, Title: View, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    var minOptionWidth: CGFloat = 96
    var maxOptionWidth: CGFloat = 240
    var horizontalPadding: CGFloat = 12
    var optionSpacing: CGFloat = 4
    var groupPadding: CGFloat = 2
    var style: AZPickerStyle = .form
    @ViewBuilder let title: () -> Title
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                title()
                Spacer(minLength: 8)
                radioGroup(wrapsOptions: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                title()
                radioGroup(wrapsOptions: false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 3) {
                title()
                radioGroup(wrapsOptions: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func radioGroup(wrapsOptions: Bool) -> some View {
        AZRadioPicker(
            options: options,
            selection: $selection,
            minOptionWidth: minOptionWidth,
            maxOptionWidth: maxOptionWidth,
            horizontalPadding: horizontalPadding,
            optionSpacing: optionSpacing,
            groupPadding: groupPadding,
            wrapsOptions: wrapsOptions,
            style: style
        ) { option in
            label(option)
        }
    }
}

/// 選択肢を自然幅で並べ、入らない時だけ次の行へ送る
struct AZFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? subviews.reduce(CGFloat.zero) { partial, subview in
            partial + subview.sizeThatFits(.unspecified).width + spacing
        }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextX = x == 0 ? size.width : x + spacing + size.width
            if availableWidth < nextX && 0 < x {
                usedWidth = max(usedWidth, x)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x = x == 0 ? size.width : x + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }
        usedWidth = max(usedWidth, x)

        return CGSize(width: min(usedWidth, availableWidth), height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var rows: [[(index: Int, size: CGSize)]] = []
        var currentRow: [(index: Int, size: CGSize)] = []
        var currentWidth: CGFloat = 0
        var y = bounds.minY

        for index in subviews.indices {
            let subview = subviews[index]
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = currentRow.isEmpty ? size.width : currentWidth + spacing + size.width
            if bounds.width < nextWidth && currentRow.isEmpty == false {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0
            }
            currentRow.append((index, size))
            currentWidth = currentRow.count == 1 ? size.width : currentWidth + spacing + size.width
        }
        if currentRow.isEmpty == false {
            rows.append(currentRow)
        }

        for row in rows {
            let rowWidth = row.reduce(CGFloat.zero) { partial, item in
                partial + item.size.width
            } + spacing * CGFloat(max(row.count - 1, 0))
            let rowHeight = row.reduce(CGFloat.zero) { partial, item in
                max(partial, item.size.height)
            }
            var x = bounds.maxX - rowWidth
            for item in row {
                let subview = subviews[item.index]
                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}
