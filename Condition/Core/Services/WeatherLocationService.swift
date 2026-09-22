// WeatherLocationService.swift
// 気象データ取得のための現在地取得と、市区町村レベルへの丸め
//
// 保存するのは市区町村名までにする（プライバシー・審査説明・統計用途のいずれもこれで足りる）。

import Foundation
import CoreLocation

@Observable
@MainActor
final class WeatherLocationService: NSObject {

    static let shared = WeatherLocationService()

    enum LocationError: LocalizedError, Equatable {
        case denied
        case failed

        var errorDescription: String? {
            switch self {
            case .denied: return String(localized: "symptom.weather.error.locationDenied")
            case .failed: return String(localized: "symptom.weather.error.locationFailed")
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        manager.delegate = self
        // 観測所を選ぶだけなので、最高精度は要らない（取得が速く電池にも優しい）
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    #if targetEnvironment(simulator)
    /// シミュレータの既定位置はサンフランシスコで、最寄りのアメダス観測所まで2万km以上ある。
    /// 気象庁の取得を確認できないので、開発時は神戸市の座標に固定する
    static let simulatorLocation = CLLocation(latitude: 34.6901, longitude: 135.1955)
    #endif

    /// 許可を求めてから現在地を1回だけ取る。
    /// 広告やネットワークより前にこれを呼ぶこと（拒否されたまま広告を見せない）
    func currentLocation() async throws -> CLLocation {
        #if targetEnvironment(simulator)
        return Self.simulatorLocation
        #else
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            // 直前の待ちが残っていたら取り消しておく
            self.continuation?.resume(throwing: LocationError.failed)
            self.continuation = continuation
            manager.requestLocation()
        }
        #endif
    }

    /// 市区町村レベルの地名。取れなければ空文字
    func placeName(for location: CLLocation) async -> String {
        #if targetEnvironment(simulator)
        return "神戸市"
        #else
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return ""
        }
        return placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea
            ?? ""
        #endif
    }
}

extension WeatherLocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // CLLocation は Sendable なので値として渡してよい
        guard let location = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            continuation?.resume(throwing: LocationError.failed)
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // CLLocationManager 自体は Sendable ではないので Task へ渡さない。
        // 状態だけを値で受け取り、操作は MainActor 側が持つ self.manager に対して行う
        let status = manager.authorizationStatus
        Task { @MainActor in
            handleAuthorizationChange(status)
        }
    }

    @MainActor
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // 許可された直後は requestLocation をやり直す
            if continuation != nil { manager.requestLocation() }
        case .denied, .restricted:
            continuation?.resume(throwing: LocationError.denied)
            continuation = nil
        default:
            break
        }
    }
}
