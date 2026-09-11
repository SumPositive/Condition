// AdMobViews.swift
// AdMob 広告（記録画面上部のバナーのみ）
//
// AdMob の審査に抵触しないよう、広告は記録画面上部のバナー1本だけに絞る。
// 設定画面のリワード広告・300×250バナーは廃止した。

import SwiftUI
import UIKit

@preconcurrency import GoogleMobileAds

// アプリID は Info.plist の GADApplicationIdentifier にセット済み

// MARK: - 広告ユニットID

/// 記録画面上部に出すバナー用ユニットID
/// Debug は app が Google テストアプリID になるため、本番ユニットは配下に無く使えない。
/// Debug ではテストユニットを使い、Release で本番ユニットを使う。
let INLINE_AD_BANNER_UNIT_ID: String = {
    #if DEBUG || targetEnvironment(simulator)
    return "ca-app-pub-3940256099942544/2934735716"  // テスト用バナー（320×50）
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

// MARK: - InlineAdBanner（記録画面上部のバナー帯）

/// 記録画面のナビゲーションバー直下に敷く 320×50 バナー。
/// アプリ内で表示する広告はこれ1本だけ。
struct InlineAdBanner: View {
    @State private var ready = AdReadyState.shared
    /// 縦方向の余裕。.compact は iPhone 横向きのように画面が低い状態を指す
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            #if DEBUG
            // fastlane snapshot 撮影時は広告を出さない（App Store スクショに広告を映さない）。
            // safeAreaInset のインセットが確定するよう高さ0の実体を返す
            if UserDefaults.standard.bool(forKey: "FASTLANE_SNAPSHOT") {
                Color.clear.frame(height: 0)
            } else {
                heightAwareBody
            }
            #else
            heightAwareBody
            #endif
        }
    }

    /// 画面の高さが足りないときだけ広告と帯を畳む。
    ///
    /// 判定は向きではなく verticalSizeClass で行う。.compact になるのは
    /// iPhone の横向きのように縦が詰まった状態だけで、iPad は横向きでも
    /// .regular のままなので広告はそのまま出る（Split View や Slide Over も同様）。
    private var isHeightConstrained: Bool {
        verticalSizeClass == .compact
    }

    /// 高さが足りないときは高さ0にして safeAreaInset ごと畳む。
    /// 50pt＋上下余白の帯が、低い画面では一覧を大きく圧迫するため。
    ///
    /// バナー自体は破棄せず畳むだけにする。作り直すと Coordinator の
    /// 「1バナーにつき1リクエスト」ガードも一緒に消え、回転を往復するたびに
    /// 新しいリクエストが飛んで無効トラフィックとみなされ得るため。
    private var heightAwareBody: some View {
        bannerBody
            .frame(height: isHeightConstrained ? 0 : nil)
            .opacity(isHeightConstrained ? 0 : 1)
            .clipped()
            // 畳んでいる間は広告に触れないようにする
            .allowsHitTesting(!isHeightConstrained)
            .accessibilityHidden(isHeightConstrained)
    }

    @ViewBuilder
    private var bannerBody: some View {
        // SDK 初期化完了後にだけ実体を生成し、start() 前のリクエストを防ぐ
        Group {
            if ready.isReady {
                InlineAdBannerRepresentable(adUnitID: INLINE_AD_BANNER_UNIT_ID)
            } else {
                Color.clear
            }
        }
        // 広告サイズと表示領域を一致させる
        .frame(width: 320, height: 50)
        .frame(maxWidth: .infinity)
        // 上下のタップできる要素（ナビゲーションバー・記録行）との間を空ける。
        // 誤タップを防ぐだけでなく、広告がアプリの操作面と地続きに
        // 見えないようにするためにも要る
        .padding(.vertical, 16)
        // 広告の載る面だけ地を一段沈め、アプリのUIではないと分かるようにする。
        // 角丸や左右余白を付けるとアプリのカードに見えてしまうため、
        // 画面端まで届く帯にし、下端の区切り線だけで面を分ける
        .background(adBandNoiseBackground)
        .overlay(alignment: .bottom) { adBandDivider }
    }

    /// 広告帯の下に引く区切り線。面の境界だけを示す細さに留める
    private var adBandDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(height: 0.5)
    }

    /// 広告帯の地。砂嵐（ホワイトノイズ）風の粒を敷き、
    /// アプリのなめらかな面と質感で区別できるようにする
    private var adBandNoiseBackground: some View {
        Color(uiColor: .tertiarySystemFill)
            .overlay {
                Canvas { context, size in
                    // 描き直しても同じ模様になるよう、固定の種から粒を置く
                    var rng = NoiseGenerator(seed: 0xA5A5_1234)
                    let count = Int(size.width * size.height / 12)
                    for _ in 0..<max(count, 0) {
                        let x = rng.cgFloat(in: 0...size.width)
                        let y = rng.cgFloat(in: 0...size.height)
                        let side = rng.cgFloat(in: 0.5...1.4)
                        let rect = CGRect(x: x, y: y, width: side, height: side)
                        // 明暗どちらの粒も置いて、ざらつきを均等に見せる
                        let isBright = rng.next() % 2 == 0
                        let base: Color = isBright ? .white : .black
                        context.fill(
                            Path(rect),
                            with: .color(base.opacity(rng.double(in: 0.02...0.07)))
                        )
                    }
                }
                // 粒を敷き詰めるだけなので、はみ出しと再描画を抑える
                .drawingGroup()
                .allowsHitTesting(false)
            }
            .clipped()
    }
}

/// 砂嵐の粒を毎回同じ配置にするための擬似乱数（SplitMix64）
private struct NoiseGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &self)
    }
}

private struct InlineAdBannerRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        // 画面内へ確実に収まる標準320×50バナーを使う
        let bannerView = BannerView(adSize: AdSizeBanner)
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
        // rootViewControllerが取得できてから一度だけ広告リクエストを送る
        bannerView.rootViewController = root
        coordinator.didRequest = true
        bannerView.load(Request())
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        /// リクエスト送信済みフラグ。1バナーにつき1回だけ要求する
        /// （失敗時の再要求は無効トラフィックとみなされ得るため行わない）
        var didRequest = false

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            #if DEBUG
            // バナーのロード失敗理由をデバッグコンソールへ残す
            print("[AdMob] inline banner load failed: \(adMobDebugDescription(error, adUnitID: bannerView.adUnitID ?? "unknown"))")
            #endif
        }
    }
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
