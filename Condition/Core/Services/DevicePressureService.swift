// DevicePressureService.swift
// 端末の気圧計から現地気圧を取る
//
// 観測所の気圧（多くは海面気圧）とは別物なので、同じ系列に混ぜない。
// 階や標高が変われば値も変わるため、24時間変化量の補完にも使わない。

import Foundation
import CoreMotion

@MainActor
enum DevicePressureService {

    enum PressureError: LocalizedError, Equatable {
        case unavailable
        case failed

        var errorDescription: String? {
            switch self {
            case .unavailable: return String(localized: "symptom.weather.error.noBarometer")
            case .failed:      return String(localized: "symptom.weather.error.barometerFailed")
            }
        }
    }

    static var isAvailable: Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    /// 現地気圧を x10 hPa で返す。必要な値を得たらすぐ停止する
    static func currentPressure_10hpa() async throws -> Int {
        guard isAvailable else { throw PressureError.unavailable }
        let altimeter = CMAltimeter()
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
                guard !finished else { return }
                finished = true
                altimeter.stopRelativeAltitudeUpdates()
                if let data {
                    // CMAltitudeData.pressure の単位は kPa。hPa は10倍
                    let hpa10 = Int((data.pressure.doubleValue * 100).rounded())
                    continuation.resume(returning: hpa10)
                } else {
                    continuation.resume(throwing: error.map { _ in PressureError.failed } ?? PressureError.failed)
                }
            }
        }
    }
}
