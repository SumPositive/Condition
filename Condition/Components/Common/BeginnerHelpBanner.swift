//
//  初心者ヘルプ表示
//  初心者向けヒント、ヘルプアイコン、詳細シートをまとめる
//
import SwiftUI

struct BeginnerHelpBanner: View {
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize

    let hintKey: LocalizedStringKey?
    let messageKey: LocalizedStringKey
    let compact: Bool
    @State private var showsHelpSheet = false
    @State private var sheetContentHeight: CGFloat = 220

    /// ユーザレベル（@Observable なので body で参照すると自動追跡）
    private var settings: AppSettings { AppSettings.shared }

    private var showsIconOnlyInExpert: Bool {
        // 達人でも詳細だけ確認できるよう、ヒント文なしのアイコンは残す
        hintKey == nil
    }

    init(_ messageKey: LocalizedStringKey, storageKey: String, compact: Bool = false) {
        self.hintKey = nil
        self.messageKey = messageKey
        self.compact = compact
    }

    init(hintKey: LocalizedStringKey, messageKey: LocalizedStringKey, storageKey: String, compact: Bool = false) {
        self.hintKey = hintKey
        self.messageKey = messageKey
        self.compact = compact
    }

    var body: some View {
        if settings.userLevel == .beginner || showsIconOnlyInExpert {
            Group {
                if (compact || settings.userLevel == .expert) && hintKey == nil {
                    // ヒント文がない場合は、見出し行やセル行に収まりやすいアイコンだけにする
                    helpButton
                } else {
                    ViewThatFits(in: .horizontal) {
                        horizontalContent
                        verticalContent
                    }
                    // グラフ・統計の本体上限に引きずられず、ヒント自身で文字サイズを決める
                    .dynamicTypeSize(helpDynamicTypeSize)
                    .padding(.horizontal, compact ? 0 : 16)
                    .padding(.vertical, compact ? 0 : 4)
                }
            }
            .sheet(isPresented: $showsHelpSheet) {
                helpSheet
                    // シートは親の文字サイズ環境を引き継がない場合があるため、上限付きで明示する
                    .dynamicTypeSize(helpSheetDynamicTypeSize)
                    // 本文に合わせた高さを基本にし、長文は大きいシートへ逃がす
                    .presentationDetents([.height(helpSheetHeight), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color(.systemBackground))
            }
        }
    }

    private var horizontalContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let hintKey {
                hintText(hintKey)
            }
            helpButton
            Spacer(minLength: 0)
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let hintKey {
                hintText(hintKey)
            }
            helpButton
        }
    }

    private func hintText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var helpButton: some View {
        Button {
            showsHelpSheet = true
        } label: {
            // クレメモと同じく、ヘルプ導線は疑問符アイコンで示す
            Image(systemName: "questionmark.circle")
                .font(helpButtonFont)
                .foregroundStyle(Color.accentColor)
                .opacity(settings.userLevel == .expert ? 0.72 : 1)
                .padding(helpButtonPadding)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("button.help"))
    }

    private var helpButtonFont: Font {
        // 達人モードのアイコン単独表示は少し控えめにする
        settings.userLevel == .expert ? .footnote.weight(.semibold) : .callout.weight(.semibold)
    }

    private var helpButtonPadding: CGFloat {
        settings.userLevel == .expert ? 5 : 8
    }

    private var helpSheetHeight: CGFloat {
        let preferredHeight = sheetContentHeight + 84
        return min(max(preferredHeight, 180), 620)
    }

    private var helpSheetDynamicTypeSize: DynamicTypeSize {
        helpDynamicTypeSize
    }

    private var helpDynamicTypeSize: DynamicTypeSize {
        let baseSize = settings.fontScale.followsSystem
            ? systemDynamicTypeSize
            : settings.fontScale.dynamicTypeSize
        return cappedHelpDynamicTypeSize(baseSize)
    }

    private func cappedHelpDynamicTypeSize(_ size: DynamicTypeSize) -> DynamicTypeSize {
        // ヘルプシートは読みやすさと崩れにくさを両立するため「大」相当を上限にする
        switch size {
        case .xSmall: return .xSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .xLarge
        case .xxLarge: return .xxLarge
        default: return .xxxLarge
        }
    }

    private var helpSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    // 本文との間隔を制御するため、アイコンはシート本文側に置く
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }

                Text(messageKey)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                sheetContentHeight = height
            }
        }
        .scrollIndicators(.hidden)
    }
}
