// EnvironmentEditViewModel.swift
// 環境シート（天候・室内・端末気圧）の入力状態。測定・症状で共用する

import Foundation
import SwiftUI

@Observable
@MainActor
final class EnvironmentEditViewModel {

    /// 環境を記録する対象の日時。気象庁の取得時刻と、端末気圧を測ってよいかの判定に使う
    let recordDate: Date

    // MARK: - 屋外（取得値。手で直すこともできる）
    var tempText: String      { didSet { markEdited(&tempEdited, oldValue, tempText) } }
    var humidityText: String  { didSet { markEdited(&humidityEdited, oldValue, humidityText) } }
    var pressureText: String  { didSet { markEdited(&pressureEdited, oldValue, pressureText) } }
    var place: String

    // MARK: - 室内（外気を上書きしない）
    var indoorTempText: String
    var indoorHumidityText: String

    // MARK: - 端末の気圧計
    private(set) var devicePressure_10hpa: Int

    // MARK: - 取得元・観測所
    private(set) var source: SymptomWeatherSource
    private(set) var stationID: String
    private(set) var stationName: String = ""
    private(set) var pressureStationID: String
    private(set) var pressureStationName: String = ""
    private(set) var pressureDistanceKm: Double?
    private(set) var pressureDelta24h_10hpa: Int?
    private(set) var weatherSymbol: String
    private(set) var sourceURL: String = ""

    private(set) var tempEdited: Bool
    private(set) var humidityEdited: Bool
    private(set) var pressureEdited: Bool

    // MARK: - 表示状態
    var isFetching = false
    var errorMessage: String?

    /// 取得結果を流し込んでいる間は「手で触った」と見なさない
    private var isApplyingFetched = false
    private var isLoading = true

    init(snapshot: EnvironmentSnapshot, recordDate: Date) {
        self.recordDate = recordDate
        // 0℃・0% も有効値なので、値ではなく入力有無フラグで空欄かを決める
        tempText = Self.decimalText(snapshot.temp_10c, scale: 1, isSet: snapshot.isTempSet)
        humidityText = snapshot.isHumiditySet ? "\(snapshot.humidity_p)" : ""
        // 気圧は物理的に0にならないので値で判定してよい
        pressureText = Self.decimalText(snapshot.pressure_10hpa, scale: 1, isSet: snapshot.pressure_10hpa > 0)
        place = snapshot.place
        indoorTempText = snapshot.isIndoorTempSet
            ? Self.decimalText(snapshot.indoorTemp_10c, scale: 1, isSet: true) : ""
        indoorHumidityText = snapshot.isIndoorHumiditySet ? "\(snapshot.indoorHumidity_p)" : ""
        devicePressure_10hpa = snapshot.devicePressure_10hpa
        source = snapshot.source
        stationID = snapshot.stationID
        pressureStationID = snapshot.pressureStationID
        pressureDistanceKm = snapshot.pressureStationDistance_10km > 0
            ? Double(snapshot.pressureStationDistance_10km) / 10 : nil
        // 変化量0（気圧が動かなかった）と計算不可を取り違えない
        pressureDelta24h_10hpa = snapshot.isPressureDelta24hSet
            ? snapshot.pressureDelta24h_10hpa : nil
        sourceURL = snapshot.sourceURL
        weatherSymbol = snapshot.weatherSymbol
        tempEdited = snapshot.isTempEdited
        humidityEdited = snapshot.isHumidityEdited
        pressureEdited = snapshot.isPressureEdited
        isLoading = false
    }

    private func markEdited(_ flag: inout Bool, _ oldValue: String, _ newValue: String) {
        guard !isLoading, !isApplyingFetched, oldValue != newValue else { return }
        flag = true
    }

    // MARK: - 取得

    var canFetchJMA: Bool {
        JMAWeatherService.isWithinAvailableRange(recordDate)
    }

    /// 端末気圧は「今」しか測れないので、過去日時の記録では取らせない
    var canFetchDevicePressure: Bool {
        guard DevicePressureService.isAvailable else { return false }
        return abs(recordDate.timeIntervalSinceNow) < 10 * 60
    }

    func fetchFromJMA() async {
        guard !isFetching else { return }
        isFetching = true
        errorMessage = nil
        defer { isFetching = false }

        guard canFetchJMA else {
            errorMessage = JMAWeatherError.outOfRange.errorDescription
            return
        }
        do {
            let location = try await WeatherLocationService.shared.currentLocation()
            let observation = try await JMAWeatherService.shared.observation(
                at: recordDate, coordinate: location.coordinate
            )
            let placeName = await WeatherLocationService.shared.placeName(for: location)
            apply(observation, placeName: placeName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ observation: JMAObservation, placeName: String) {
        isApplyingFetched = true
        defer { isApplyingFetched = false }

        // 手で直した項目は上書きしない
        if !tempEdited, let temp = observation.temp_10c {
            tempText = Self.decimalText(temp, scale: 1, isSet: true)
        }
        if !humidityEdited, let humidity = observation.humidity_p {
            humidityText = "\(humidity)"
        }
        if !pressureEdited, let pressure = observation.pressure_10hpa {
            pressureText = Self.decimalText(pressure, scale: 1, isSet: true)
            pressureDelta24h_10hpa = observation.pressureDelta24h_10hpa
        }
        stationID = observation.stationID
        stationName = observation.stationName
        sourceURL = observation.sourceURL
        pressureStationID = observation.pressureStationID
        pressureStationName = observation.pressureStationName
        pressureDistanceKm = observation.pressureDistanceKm
        if !placeName.isEmpty { place = placeName }
        source = .jma
    }

    func fetchDevicePressure() async {
        errorMessage = nil
        do {
            devicePressure_10hpa = try await DevicePressureService.currentPressure_10hpa()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 結果

    /// 入力内容をスナップショットに戻す
    func snapshot() -> EnvironmentSnapshot {
        var result = EnvironmentSnapshot()
        let temp = Self.scaledInt(tempText, scale: 1)
        let humidity = Int(humidityText.trimmingCharacters(in: .whitespaces))
        let pressure = Self.scaledInt(pressureText, scale: 1)
        let indoorTemp = Self.scaledInt(indoorTempText, scale: 1)
        let indoorHumidity = Int(indoorHumidityText.trimmingCharacters(in: .whitespaces))
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)

        result.temp_10c = Self.clamped(temp, SymptomLimits.tempRange_10c)
        result.isTempSet = temp != nil
        result.humidity_p = Self.clamped(humidity, SymptomLimits.humidityRange_p)
        result.isHumiditySet = humidity != nil
        result.pressure_10hpa = Self.clamped(pressure, SymptomLimits.pressureRange_10hpa)
        result.place = String(trimmedPlace.prefix(60))
        result.weatherSymbol = weatherSymbol
        result.devicePressure_10hpa = devicePressure_10hpa

        result.isIndoorTempSet = indoorTemp != nil
        result.indoorTemp_10c = Self.clamped(indoorTemp, SymptomLimits.tempRange_10c)
        result.isIndoorHumiditySet = indoorHumidity != nil
        result.indoorHumidity_p = Self.clamped(indoorHumidity, SymptomLimits.humidityRange_p)

        result.isTempEdited = tempEdited
        result.isHumidityEdited = humidityEdited
        result.isPressureEdited = pressureEdited

        // 気圧を手で直したら観測所由来の24時間変化量は意味を失う
        if pressureEdited {
            result.pressureDelta24h_10hpa = 0
            result.isPressureDelta24hSet = false
            result.pressureStationID = ""
            result.pressureStationDistance_10km = 0
            result.sourceURL = ""
        } else {
            result.pressureDelta24h_10hpa = Self.clamped(
                pressureDelta24h_10hpa, SymptomLimits.pressureDeltaRange_10hpa
            )
            result.isPressureDelta24hSet = pressureDelta24h_10hpa != nil
            result.pressureStationID = pressureStationID
            result.pressureStationDistance_10km = pressureDistanceKm
                .map { Int(($0 * 10).rounded()) } ?? 0
            result.sourceURL = sourceURL
        }
        result.stationID = (tempEdited && humidityEdited) ? "" : stationID

        let hasOutdoor = temp != nil || humidity != nil || pressure != nil || !trimmedPlace.isEmpty
        let allEdited = tempEdited && humidityEdited && pressureEdited
        if !hasOutdoor {
            result.source = .none
        } else {
            result.source = (source == .jma && !allEdited) ? .jma : .manual
        }
        return result
    }

    // MARK: - 数値の入出力

    private static func decimalText(_ value: Int, scale: Int, isSet: Bool) -> String {
        guard isSet, value != 0 else { return "" }
        return String(format: "%.\(scale)f", Double(value) / pow(10, Double(scale)))
    }

    private static func scaledInt(_ text: String, scale: Int) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return nil }
        return Int((value * pow(10, Double(scale))).rounded())
    }

    private static func clamped(_ value: Int?, _ range: (min: Int, max: Int)) -> Int {
        guard let value else { return 0 }
        return min(max(value, range.min), range.max)
    }
}
