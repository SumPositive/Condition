// EnvironmentSnapshot.swift
// 測定記録と症状記録で共用する「環境」の値
//
// SwiftData のモデルとは切り離した素の値の器にしておく。
// こうしておけば環境シートは BodyRecord / SymptomRecord のどちらからも同じ形で開ける。

import Foundation

/// 記録時の環境（天候・室内・端末気圧）のスナップショット
struct EnvironmentSnapshot: Codable, Equatable, Sendable {

    // MARK: - 天候（屋外）
    /// 0 = 未取得。入力有無は個別フラグで持つ
    var temp_10c: Int = 0
    var humidity_p: Int = 0
    var pressure_10hpa: Int = 0
    var pressureDelta24h_10hpa: Int = 0
    /// 0℃・0%・変化量0は有効値なので、値ではなくフラグで欠測と区別する
    var isTempSet: Bool = false
    var isHumiditySet: Bool = false
    var isPressureDelta24hSet: Bool = false
    var weatherSymbol: String = ""
    var place: String = ""
    var source: SymptomWeatherSource = .none

    // MARK: - 観測所
    var stationID: String = ""
    var pressureStationID: String = ""
    var pressureStationDistance_10km: Int = 0
    /// 取得した気象庁データの出典URL
    var sourceURL: String = ""
    /// 観測値の時刻。アメダスは10分ごとなので記録時刻とは少しずれる
    var observedAt: Date? = nil

    // MARK: - 端末の気圧計（現地気圧。観測所の海面気圧とは別物）
    var devicePressure_10hpa: Int = 0

    // MARK: - 室内（外気を上書きせず並存させる）
    var indoorTemp_10c: Int = 0
    var indoorHumidity_p: Int = 0
    var isIndoorTempSet: Bool = false
    var isIndoorHumiditySet: Bool = false

    // MARK: - 項目ごとの手動変更フラグ
    var isTempEdited: Bool = false
    var isHumidityEdited: Bool = false
    var isPressureEdited: Bool = false

    var hasAnyValue: Bool {
        source.isPresent || isTempSet || isHumiditySet || pressure_10hpa != 0 || isPressureDelta24hSet
            || devicePressure_10hpa != 0 || isIndoorTempSet || isIndoorHumiditySet
    }

    /// 取り込んだ値を症状の weather と同じ範囲・文字列長へ収める。
    /// 外部作成や破損した JSON の極端な値をそのまま保存しないため
    func normalized() -> EnvironmentSnapshot {
        var result = self
        result.temp_10c = Self.clamped(temp_10c, SymptomLimits.tempRange_10c)
        result.humidity_p = Self.clamped(humidity_p, SymptomLimits.humidityRange_p)
        // 気圧は 0 が未取得なので、範囲の下限へ引き上げない
        result.pressure_10hpa = pressure_10hpa == 0
            ? 0 : Self.clamped(pressure_10hpa, SymptomLimits.pressureRange_10hpa)
        result.pressureDelta24h_10hpa = Self.clamped(
            pressureDelta24h_10hpa, SymptomLimits.pressureDeltaRange_10hpa
        )
        result.devicePressure_10hpa = devicePressure_10hpa == 0
            ? 0 : Self.clamped(devicePressure_10hpa, SymptomLimits.pressureRange_10hpa)
        result.pressureStationDistance_10km = Self.clamped(
            pressureStationDistance_10km, SymptomLimits.pressureStationDistanceRange_10km
        )
        result.indoorTemp_10c = Self.clamped(indoorTemp_10c, SymptomLimits.tempRange_10c)
        result.indoorHumidity_p = Self.clamped(indoorHumidity_p, SymptomLimits.humidityRange_p)
        result.place = String(place.prefix(SymptomLimits.weatherPlaceMaxLength))
        result.weatherSymbol = String(weatherSymbol.prefix(SymptomLimits.weatherSymbolMaxLength))
        result.stationID = String(stationID.prefix(SymptomLimits.stationIDMaxLength))
        result.pressureStationID = String(pressureStationID.prefix(SymptomLimits.stationIDMaxLength))
        result.sourceURL = String(sourceURL.prefix(SymptomLimits.weatherSourceURLMaxLength))
        return result
    }

    private static func clamped(_ value: Int, _ range: (min: Int, max: Int)) -> Int {
        min(max(value, range.min), range.max)
    }
}

// MARK: - SymptomRecord との相互変換

extension SymptomRecord {

    /// 環境シートへ渡す値
    var environmentSnapshot: EnvironmentSnapshot {
        EnvironmentSnapshot(
            temp_10c: nTemp_10c,
            humidity_p: nHumidity_p,
            pressure_10hpa: nPressure_10hpa,
            pressureDelta24h_10hpa: nPressureDelta24h_10hpa,
            isTempSet: bTempSet,
            isHumiditySet: bHumiditySet,
            isPressureDelta24hSet: bPressureDelta24hSet,
            weatherSymbol: sWeatherSymbol,
            place: sWeatherPlace,
            source: weatherSource,
            stationID: sWeatherStationID,
            pressureStationID: sPressureStationID,
            pressureStationDistance_10km: nPressureStationDistance_10km,
            sourceURL: sWeatherSourceURL,
            observedAt: dWeatherObservedAt,
            devicePressure_10hpa: nDevicePressure_10hpa,
            indoorTemp_10c: nIndoorTemp_10c,
            indoorHumidity_p: nIndoorHumidity_p,
            isIndoorTempSet: bIndoorTempSet,
            isIndoorHumiditySet: bIndoorHumiditySet,
            isTempEdited: bTempEdited,
            isHumidityEdited: bHumidityEdited,
            isPressureEdited: bPressureEdited
        )
    }

    /// 環境シートの結果を書き戻す
    func apply(_ snapshot: EnvironmentSnapshot) {
        nTemp_10c = snapshot.temp_10c
        nHumidity_p = snapshot.humidity_p
        nPressure_10hpa = snapshot.pressure_10hpa
        nPressureDelta24h_10hpa = snapshot.pressureDelta24h_10hpa
        bTempSet = snapshot.isTempSet
        bHumiditySet = snapshot.isHumiditySet
        bPressureDelta24hSet = snapshot.isPressureDelta24hSet
        sWeatherSymbol = snapshot.weatherSymbol
        sWeatherPlace = snapshot.place
        weatherSource = snapshot.source
        sWeatherStationID = snapshot.stationID
        sPressureStationID = snapshot.pressureStationID
        nPressureStationDistance_10km = snapshot.pressureStationDistance_10km
        sWeatherSourceURL = snapshot.sourceURL
        dWeatherObservedAt = snapshot.observedAt
        nDevicePressure_10hpa = snapshot.devicePressure_10hpa
        nIndoorTemp_10c = snapshot.indoorTemp_10c
        nIndoorHumidity_p = snapshot.indoorHumidity_p
        bIndoorTempSet = snapshot.isIndoorTempSet
        bIndoorHumiditySet = snapshot.isIndoorHumiditySet
        bTempEdited = snapshot.isTempEdited
        bHumidityEdited = snapshot.isHumidityEdited
        bPressureEdited = snapshot.isPressureEdited
    }
}

// MARK: - 測定記録の環境保存

extension BodyRecord {
    /// 共通シートの全項目をまとめて保存し、旧記録は未設定として読む
    var environmentSnapshot: EnvironmentSnapshot {
        get {
            guard let data = sEnvironment.data(using: .utf8),
                  let value = try? JSONDecoder().decode(EnvironmentSnapshot.self, from: data)
            else { return EnvironmentSnapshot() }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else { return }
            sEnvironment = value
        }
    }
}
