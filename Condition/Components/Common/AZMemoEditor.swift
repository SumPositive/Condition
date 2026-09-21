import SwiftUI
import UIKit

private extension DynamicTypeSize {
    /// SwiftUIの文字サイズ設定をUIKitの文字サイズへ変換する
    var azUIContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

    /// SwiftUIの文字サイズ設定を反映したUIKitフォントを作る
    func azUIFont(forTextStyle textStyle: UIFont.TextStyle) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: azUIContentSizeCategory)
        return UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits)
    }
}

/// SPM化を見据えた、Dynamic Type対応の自動伸縮メモ入力欄
struct AZMemoEditor: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var minHeight: CGFloat = 36
    var dismissOnReturn: Bool = false
    /// この値を変えると入力を終了してキーボードを閉じる（呼び出し側からの明示的な指示）。
    /// isFocused の false でこれを代用すると、入力中の一瞬を誤検出して閉じてしまう。
    var dismissToken: Int = 0
    var onBeginEditing: (() -> Void)?
    @State private var editorHeight: CGFloat = 36

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Color(.placeholderText))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            // 実際のUITextViewで高さを測り、TextEditorの推定高さズレを避ける
            AZAutoSizingTextView(
                text: $text,
                isFocused: $isFocused,
                minHeight: minHeight,
                dismissOnReturn: dismissOnReturn,
                dismissToken: dismissToken,
                onBeginEditing: onBeginEditing,
                measuredHeight: $editorHeight
            )
            .frame(height: editorHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AZAutoSizingTextView: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let minHeight: CGFloat
    let dismissOnReturn: Bool
    let dismissToken: Int
    let onBeginEditing: (() -> Void)?
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = AZLayoutReportingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.autocorrectionType = .no
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        textView.onWidthChange = { [weak textView] in
            // 初回レイアウトで横幅が決まった後に高さを測り直す。
            // 高さ変化では呼ばない（layoutSubviews の中から測り直すと再入になり、
            // 変換中の未確定文字が解除されてしまう）。
            guard let textView else { return }
            coordinator.updateHeight(textView)
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // 日本語変換中（未確定文字がある）は UITextView の中身へ書き戻さない。
        // text や font を代入すると marked text が解除され、勝手に確定されてしまう。
        // 行が増えて高さが変わったときの再描画で、これが起きていた。
        let isComposing = textView.markedTextRange != nil
        if !isComposing {
            if textView.text != text {
                textView.text = text
            }
            // SwiftUI側のアプリ内文字サイズ設定をUITextViewにも反映する
            textView.font = context.environment.dynamicTypeSize.azUIFont(forTextStyle: .body)
        }
        context.coordinator.parent = self
        context.coordinator.updateHeight(textView)

        if isFocused.wrappedValue, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }

        // フォーカスを外すのは、呼び出し側が dismissToken を進めたときだけにする。
        // isFocused の false を見て resign すると、入力中（textViewDidBeginEditing の
        // 反映待ち）の一瞬を誤検出してキーボードが勝手に閉じてしまうため。
        if dismissToken != context.coordinator.lastDismissToken {
            context.coordinator.lastDismissToken = dismissToken
            if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        // 画面破棄時にウィンドウへ追加した監視を外す
        coordinator.removeOutsideTapRecognizer()
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: AZAutoSizingTextView
        /// 最後に処理した dismissToken。値が変わったときだけ resign する。
        var lastDismissToken: Int = 0
        /// 入力中のメモ欄
        weak var activeTextView: UITextView?
        /// メモ欄外のタップを監視する認識器
        private var outsideTapRecognizer: UITapGestureRecognizer?

        init(_ parent: AZAutoSizingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateHeight(textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if parent.dismissOnReturn && text == "\n" {
                textView.resignFirstResponder()
                parent.isFocused.wrappedValue = false
                return false
            }
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
            parent.onBeginEditing?()
            // first responder になった時点でウィンドウは確定しているので、
            // ここで設置すれば取りこぼさない
            installOutsideTapRecognizer(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = false
            removeOutsideTapRecognizer()
        }

        /// 入力中だけ所属ウィンドウで外側タップを監視する
        private func installOutsideTapRecognizer(for textView: UITextView) {
            removeOutsideTapRecognizer()
            guard let window = textView.window else { return }
            let recognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(handleOutsideTap)
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            activeTextView = textView
            outsideTapRecognizer = recognizer
            window.addGestureRecognizer(recognizer)
        }

        /// ウィンドウへ追加した外側タップ監視を解除する
        func removeOutsideTapRecognizer() {
            if let outsideTapRecognizer {
                outsideTapRecognizer.view?.removeGestureRecognizer(outsideTapRecognizer)
            }
            outsideTapRecognizer = nil
            activeTextView = nil
        }

        /// メモ欄外がタップされたら標準アニメーションで閉じる
        @objc private func handleOutsideTap() {
            activeTextView?.resignFirstResponder()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // 入力欄どうしの移動、およびメモ欄内のカーソル移動や文字選択では閉じない。
            // 候補バーなど明示的に除外した領域のタップでも閉じない。
            var touchedView = touch.view
            while let currentView = touchedView {
                if currentView is UITextField || currentView is UITextView {
                    return false
                }
                if currentView.subviews.contains(where: { $0 is AZKeyboardDismissExcludedMarker }) {
                    return false
                }
                touchedView = currentView.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // 画面本来のタップ操作を妨げない
            true
        }

        func updateHeight(_ textView: UITextView) {
            let fittingWidth = textView.bounds.width
            if fittingWidth <= 0 {
                return
            }
            // UITextView自身に必要高さを測らせて、表示と計算の行数ズレを防ぐ
            let size = textView.sizeThatFits(
                CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
            )
            let newHeight = max(parent.minHeight, ceil(size.height))
            if 0.5 < abs(parent.measuredHeight - newHeight) {
                DispatchQueue.main.async {
                    self.parent.measuredHeight = newHeight
                }
            }
        }
    }
}

/// キーボードを閉じる監視の対象外にしたい領域へ付ける目印
struct AZKeyboardDismissExclusion: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = AZKeyboardDismissExcludedMarker(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

/// 除外領域の目印。祖先をたどって見つかったら監視しない
final class AZKeyboardDismissExcludedMarker: UIView {}

extension View {
    /// この領域の操作ではキーボードを閉じない
    func azKeyboardDismissExcluded() -> some View {
        background { AZKeyboardDismissExclusion() }
    }
}

private final class AZLayoutReportingTextView: UITextView {
    /// 横幅が変わったときだけ呼ばれる
    var onWidthChange: (() -> Void)?
    private var lastLayoutWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        // 高さだけが変わった再レイアウトでは測り直さない。
        // layoutSubviews の最中に sizeThatFits を呼ぶと再入レイアウトになり、
        // 変換中の未確定文字が確定されてしまうため。
        guard 0.5 < abs(lastLayoutWidth - bounds.width) else { return }
        lastLayoutWidth = bounds.width
        onWidthChange?()
    }
}
