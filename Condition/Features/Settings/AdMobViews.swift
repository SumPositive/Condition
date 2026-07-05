// AdMobViews.swift
// AdMob 広告（開発者応援）
//
// Google公式サンプルに合わせ、Requestを直接生成して読み込む

import SwiftUI
import UIKit

@preconcurrency import GoogleMobileAds

// アプリID は Info.plist の GADApplicationIdentifier にセット済み

// MARK: - 広告ユニットID

#if DEBUG || targetEnvironment(simulator)
// シートは300×250固定サイズなので、Google公式の固定バナー用テストIDを使う
private let ADMOB_BANNER_UNIT_ID = "ca-app-pub-3940256099942544/2934735716"  // テスト用固定バナー
private let ADMOB_REWARD_UNIT_ID = "ca-app-pub-3940256099942544/1712485313"  // テスト用リワード
#else
private let ADMOB_BANNER_UNIT_ID = "ca-app-pub-7576639777972199/9141270336"  // 本番用バナー
private let ADMOB_REWARD_UNIT_ID = "ca-app-pub-7576639777972199/4693657810"  // 本番用リワード
#endif

/// 一覧途中に挟むアダプティブバナー用ユニットID（公開：InlineAdBanner から参照）
/// Debug は app が Google テストアプリID になるため、本番ユニットは配下に無く使えない。
/// Debug では adaptive バナー用のテストユニットを使い、Release で本番ユニットを使う。
let INLINE_AD_BANNER_UNIT_ID: String = {
    #if DEBUG || targetEnvironment(simulator)
    return "ca-app-pub-3940256099942544/2435281174"  // テスト用アダプティブバナー
    #else
    return "ca-app-pub-7576639777972199/9141270336"  // 本番用インラインバナー
    #endif
}()

#if DEBUG
/// 広告失敗の原因とSDK応答を画面上でも判別できる形式へ整える
private func adMobDebugDescription(_ error: Error, adUnitID: String) -> String {
    let nsError = error as NSError
    let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String ?? "unknown"
    var details = [
        "app: \(appID)",
        "unit: \(adUnitID)",
        "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)",
    ]

    // 失敗時のuserInfoには各広告ネットワークの応答情報が含まれる
    if let responseInfo = nsError.userInfo.values.first(where: { $0 is ResponseInfo }) as? ResponseInfo {
        details.append("response: \(responseInfo.dictionaryRepresentation)")
    } else {
        details.append("userInfo keys: \(nsError.userInfo.keys.map(\.description).sorted())")
    }
    return details.joined(separator: "\n")
}
#endif

// MARK: - AdMobAdSheetView（広告を見て応援するシート）

/// 設定画面から開く「広告を見て応援する」シート。
/// 上にバナー、下にリワード再生ボタンを並べる構成。
struct AdMobAdSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let onRewardEarned: () -> Void

    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_REWARD_UNIT_ID)
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        let content = NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AdMobBannerView(
                        adUnitID: ADMOB_BANNER_UNIT_ID,
                        size: CGSize(width: 300, height: 250)
                    )
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )

                    rewardedSection
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(uiColor: .tertiarySystemBackground))
                        )
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("support.watchAd")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .onAppear {
                loader.onRewardEarned = { _ in
                    onRewardEarned()
                }
            }
        }

        if settings.fontScale.followsSystem {
            content
        } else {
            content.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
        }
    }

    @ViewBuilder
    private var rewardedSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.title2)
                Text("support.videoAd")
                    .font(.headline)
                Spacer()
                Label {
                    Text("support.soundWarning")
                        .font(.footnote.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            }

            Text("support.adCloseHint")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if loader.isLoading {
                ProgressView("support.loadingAd")
            } else {
                Button {
                    if let root = UIApplication.topMostViewController() {
                        loader.present(from: root)
                    }
                } label: {
                    Label("support.playAd", systemImage: loader.isReady ? "play.rectangle" : "pause.rectangle")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!loader.isReady)
            }

            if loader.errorMessage != nil {
                Text(LocalizedStringKey(loader.errorMessage ?? ""))
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                #if DEBUG
                if let detail = loader.debugErrorMessage {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                #endif
                Button("action.reload") {
                    loader.loadAd()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - AdMobBannerView（シート用 300×250 バナー）

private struct AdMobBannerView: View {
    let adUnitID: String
    let size: CGSize

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var debugErrorMessage: String?
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 8) {
            AdMobBannerRepresentable(
                adUnitID: adUnitID,
                size: size,
                onReceiveAd: {
                    isLoading = false
                    errorMessage = nil
                    debugErrorMessage = nil
                },
                onFailToReceiveAd: { error in
                    isLoading = false
                    errorMessage = "support.noBannerAdsAvailableRightNowPlease"
                    #if DEBUG
                    debugErrorMessage = adMobDebugDescription(error, adUnitID: adUnitID)
                    #endif
                },
                reloadToken: reloadToken
            )
            .id(reloadToken)
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )

            if isLoading {
                ProgressView("support.loadingAd")
                    .font(.caption)
            } else if let key = errorMessage {
                VStack(spacing: 6) {
                    Text(LocalizedStringKey(key))
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Button("action.reload") {
                        reloadToken = UUID()
                        isLoading = true
                        errorMessage = nil
                        debugErrorMessage = nil
                    }
                    .buttonStyle(.bordered)
                    #if DEBUG
                    if let debugErrorMessage {
                        Text(debugErrorMessage)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    #endif
                }
            }
        }
    }
}

private struct AdMobBannerRepresentable: UIViewControllerRepresentable {
    let adUnitID: String
    let size: CGSize
    let onReceiveAd: () -> Void
    let onFailToReceiveAd: (Error) -> Void
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(onReceiveAd: onReceiveAd, onFailToReceiveAd: onFailToReceiveAd)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear

        let bannerView = BannerView(adSize: adSizeFor(cgSize: size))
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        bannerView.delegate = context.coordinator
        bannerView.translatesAutoresizingMaskIntoConstraints = false

        viewController.view.addSubview(bannerView)
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
        ])

        context.coordinator.bannerView = bannerView
        // Google公式例と同じ素のリクエストで直接読み込む
        bannerView.load(Request())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.bannerView?.rootViewController = uiViewController
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        weak var bannerView: BannerView?
        private let onReceiveAd: () -> Void
        private let onFailToReceiveAd: (Error) -> Void

        init(onReceiveAd: @escaping () -> Void, onFailToReceiveAd: @escaping (Error) -> Void) {
            self.onReceiveAd = onReceiveAd
            self.onFailToReceiveAd = onFailToReceiveAd
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onReceiveAd()
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            #if DEBUG
            // テスト広告が出ない場合にGoogle SDKの具体的な失敗理由を確認する
            print("[AdMob] banner load failed: \(adMobDebugDescription(error, adUnitID: bannerView.adUnitID ?? "unknown"))")
            #endif
            onFailToReceiveAd(error)
        }
    }
}

// MARK: - RewardedAdLoader

@MainActor
final class RewardedAdLoader: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var debugErrorMessage: String?

    var onRewardEarned: ((AdReward) -> Void)?
    private let adUnitID: String
    nonisolated(unsafe) private var rewardedAd: RewardedAd?

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init()
        loadAd()
    }

    /// リワード広告を読み込む
    func loadAd() {
        guard !isLoading else { return }
        isLoading = true
        isReady = false
        errorMessage = nil
        debugErrorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let ad = try await RewardedAd.load(
                    with: adUnitID,
                    request: Request()
                )
                rewardedAd = ad
                ad.fullScreenContentDelegate = self
                self.isLoading = false
                self.isReady = true
            } catch {
                #if DEBUG
                // リワード広告のロード失敗理由をデバッグコンソールへ残す
                print("[AdMob] rewarded load failed: \(adMobDebugDescription(error, adUnitID: adUnitID))")
                #endif
                isLoading = false
                errorMessage = "support.noAdsAvailableRightNowPlease"
                #if DEBUG
                debugErrorMessage = adMobDebugDescription(error, adUnitID: adUnitID)
                #endif
                rewardedAd = nil
            }
        }
    }

    /// 読み込み済み広告を表示する
    func present(from root: UIViewController) {
        guard let rewardedAd else { return }
        let ad = rewardedAd
        isReady = false
        ad.present(from: root) { [weak self] in
            guard let self else { return }
            self.onRewardEarned?(ad.adReward)
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            self.rewardedAd = nil
            self.loadAd()
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            self.errorMessage = "support.noAdsAvailableRightNowPlease"
            self.rewardedAd = nil
            self.loadAd()
        }
    }
}

// MARK: - AdMob 初期化状態

/// MobileAds.start() 完了（＝広告リクエスト可能）を SwiftUI へ伝える共有フラグ。
/// start() 前・同意解決前にバナーが load するとテストデバイス設定も反映されず
/// "No ad to show" になるため、この値が true になってからロードする。
@MainActor
@Observable
final class AdReadyState {
    static let shared = AdReadyState()
    private(set) var isReady = false
    func markReady() { isReady = true }
    private init() {}
}

// MARK: - InlineAdBanner（一覧途中に挟むアダプティブバナー）

/// 記録一覧の各月セクションヘッダーなど、自然な区切り位置に挟むアダプティブバナー。
/// 横幅に追従する adaptive サイズで要求するので、テスト広告も含め在庫が安定する。
struct InlineAdBanner: View {
    /// バナーの高さ。AdMob の standard banner サイズ（320×50）に合わせる
    var height: CGFloat = 50

    @State private var ready = AdReadyState.shared

    var body: some View {
        // SDK 初期化完了後にだけ実体を生成し、start() 前のリクエストを防ぐ
        Group {
            if ready.isReady {
                InlineAdBannerRepresentable(adUnitID: INLINE_AD_BANNER_UNIT_ID)
            } else {
                Color.clear
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

private struct InlineAdBannerRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        // adSize は幅が確定してから設定する（makeUIView 時点では 0 のことがある）
        let bannerView = BannerView()
        bannerView.adUnitID = adUnitID
        bannerView.delegate = context.coordinator
        loadIfReady(bannerView, coordinator: context.coordinator)
        return bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        loadIfReady(uiView, coordinator: context.coordinator)
    }

    private func loadIfReady(_ bannerView: BannerView, coordinator: Coordinator) {
        guard !coordinator.didRequest else { return }
        guard let root = inlineAdRootViewController() else { return }
        // 横幅に追従する adaptive サイズで要求する（0幅リクエストは避ける）
        let width = inlineAdWindowWidth() ?? UIScreen.main.bounds.width
        guard width > 0 else { return }
        bannerView.adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        // rootViewControllerが取得できてから一度だけ広告リクエストを送る
        bannerView.rootViewController = root
        coordinator.didRequest = true
        // Google公式例と同じ素のリクエストで直接読み込む
        bannerView.load(Request())
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        /// リクエスト送信済みフラグ。1バナーにつき1回だけ要求する
        /// （失敗時の再要求は無効トラフィックとみなされ得るため行わない）
        var didRequest = false

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            #if DEBUG
            // 一覧内バナーのロード失敗理由をデバッグコンソールへ残す
            print("[AdMob] inline banner load failed: \(adMobDebugDescription(error, adUnitID: bannerView.adUnitID ?? "unknown"))")
            #endif
        }
    }
}

/// keyWindow の実幅を返す（0 幅の adaptive リクエストで弾かれるのを防ぐ）
@MainActor
private func inlineAdWindowWidth() -> CGFloat? {
    let width = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }?
        .bounds.width
    return (width ?? 0) > 0 ? width : nil
}

/// keyWindow の root view controller を返す（InlineAdBanner 専用ヘルパー）
@MainActor
private func inlineAdRootViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }?
        .rootViewController
}

// MARK: - UIApplication extension

extension UIApplication {
    /// 表示中の最前面 ViewController を返す
    static func topMostViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.rootViewController }
            .first
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topMostViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}
