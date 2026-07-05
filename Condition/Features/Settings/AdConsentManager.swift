// AdConsentManager.swift
// AdMob 同意管理（UMP / User Messaging Platform）
//
// GoogleMobileAds は同意情報が未解決のままだと全ユニットで "No ad to show" を
// 返すことがある。SDK 起動前に UMP の同意情報を更新し、必要地域ではフォームを
// 提示してから広告リクエストできる状態（canRequestAds）にする。

import UIKit
import UserMessagingPlatform

enum AdConsentManager {

    /// 同意情報を更新し、必要ならフォームを提示する。
    /// 非規制地域（日本など）ではフォーム提示なしで即 canRequestAds=true になる。
    /// 完了後、広告リクエストが可能かどうかにかかわらず制御を返す。
    @MainActor
    static func gatherConsent() async {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

        #if DEBUG || targetEnvironment(simulator)
        // デバッグ時の地域は既定（Disabled）にして実際の地域判定に任せる。
        // EEA の同意フローを検証したいときだけ geography を EEA に変える。
        let debugSettings = DebugSettings()
        debugSettings.geography = .disabled
        // ここへテストデバイスIDを入れると debug geography が適用される
        debugSettings.testDeviceIdentifiers = []
        parameters.debugSettings = debugSettings
        #endif

        // 1) 同意情報を更新する
        do {
            try await requestConsentInfoUpdate(parameters: parameters)
        } catch {
            #if DEBUG
            print("[AdConsent] requestConsentInfoUpdate failed: \(error.localizedDescription)")
            #endif
            return
        }

        // 2) 必要なら同意フォームを読み込んで提示する（不要地域では何もせず返る）
        guard let root = topViewController() else { return }
        do {
            try await loadAndPresentIfRequired(from: root)
        } catch {
            #if DEBUG
            print("[AdConsent] loadAndPresentIfRequired failed: \(error.localizedDescription)")
            #endif
        }

        #if DEBUG
        print("[AdConsent] canRequestAds = \(ConsentInformation.shared.canRequestAds)")
        #endif
    }

    // MARK: - async ラッパー

    @MainActor
    private static func requestConsentInfoUpdate(parameters: RequestParameters) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor
    private static func loadAndPresentIfRequired(from viewController: UIViewController) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentForm.loadAndPresentIfRequired(from: viewController) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        UIApplication.topMostViewController()
    }
}
