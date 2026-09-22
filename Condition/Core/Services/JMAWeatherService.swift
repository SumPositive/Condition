// JMAWeatherService.swift
// 気象庁アメダスの公開JSONから、記録した日時・場所に近い観測値を取る
//
// 実測して確かめた制約（2026-09-22）:
//  - 観測所は1286か所。気温914・湿度840に対し、気圧を観測するのは154か所しかない
//    → 気温湿度と気圧で観測所を分けて選び、気圧側は観測所名と距離を必ず画面に出す
//  - 地点別JSONは3時間区切り（00/03/06/09/12/15/18/21）。1ファイルに10分刻みで3時間ぶん
//  - 過去分の保持は約9日。それ以前は404になるので、失敗ではなく欠測として扱う
//
// 気象庁の利用条件に従い、出典表示と控えめなアクセス頻度を守る。

import Foundation
import CoreLocation
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "JMAWeather")

// MARK: - 観測所

struct JMAStation: Identifiable, Equatable, Sendable {
    let id: String          // 観測所番号
    let name: String        // 漢字名
    let latitude: Double
    let longitude: Double
    let hasTemp: Bool
    let hasHumidity: Bool
    let hasPressure: Bool

    /// 2点間のおおよその距離（km）。観測所選びに使うだけなので簡易式で足りる
    func distanceKm(to coordinate: CLLocationCoordinate2D) -> Double {
        let latKm = (latitude - coordinate.latitude) * 111.0
        let lonKm = (longitude - coordinate.longitude)
            * 111.0 * cos(coordinate.latitude * .pi / 180)
        return (latKm * latKm + lonKm * lonKm).squareRoot()
    }
}

// MARK: - 取得結果

struct JMAObservation: Equatable, Sendable {
    /// 気温・湿度を取った観測所
    var stationID: String = ""
    var stationName: String = ""
    var temp_10c: Int? = nil
    var humidity_p: Int? = nil

    /// 気圧を取った観測所（気温側と違うことがある）
    var pressureStationID: String = ""
    var pressureStationName: String = ""
    var pressureDistanceKm: Double? = nil
    var pressure_10hpa: Int? = nil
    var pressureDelta24h_10hpa: Int? = nil

    /// 観測値の時刻（10分刻みで最も近いもの）
    var observedAt: Date? = nil
    /// 気温・湿度を取った地点別JSONのURL（値の根拠をたどれるように残す）
    var sourceURL: String = ""

    var hasAnyValue: Bool {
        temp_10c != nil || humidity_p != nil || pressure_10hpa != nil
    }
}

enum JMAWeatherError: LocalizedError, Equatable {
    case outOfRange          // 保持期間（約9日）より前
    case outsideJapan        // 最寄りの観測所が遠すぎる（＝国外）
    case noNearbyStation
    case notAvailable        // 応答はあるが該当時刻の観測値がない

    var errorDescription: String? {
        switch self {
        case .outOfRange:      return String(localized: "symptom.weather.error.outOfRange")
        case .outsideJapan:    return String(localized: "symptom.weather.error.outsideJapan")
        case .noNearbyStation: return String(localized: "symptom.weather.error.noStation")
        case .notAvailable:    return String(localized: "symptom.weather.error.notAvailable")
        }
    }
}

// MARK: - サービス

actor JMAWeatherService {

    static let shared = JMAWeatherService()

    /// 気圧観測所がこれより遠ければ別地点すぎるので使わない
    static let maxPressureStationDistanceKm: Double = 100
    /// 気温・湿度の観測所がこれより遠ければ日本国外とみなす。
    /// 上限が無いと、海外にいるとき数千km先の観測所を引いて空振りし続ける
    static let maxStationDistanceKm: Double = 150
    /// サイト用JSONの保持期間（実測9日。余裕を見て8日で切る）
    static let availableDays = 8

    private let session: URLSession
    private var stationsCache: [JMAStation]?
    /// 同じ観測所・同じ3時間ブロックの応答は使い回す（アクセス頻度を抑える）
    private var pointCache: [String: [String: [String: JMAValue]]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: 公開API

    /// 指定の日時・座標に最も近い観測値を取る
    func observation(
        at date: Date,
        coordinate: CLLocationCoordinate2D
    ) async throws -> JMAObservation {
        guard Self.isWithinAvailableRange(date) else { throw JMAWeatherError.outOfRange }

        let stations = try await loadStations()
        guard let main = nearest(in: stations, to: coordinate, requiring: \.hasTemp),
              main.distanceKm(to: coordinate) <= Self.maxStationDistanceKm else {
            // 日本国外ではここに来る（気象庁のアメダスは国内のみ）
            throw JMAWeatherError.outsideJapan
        }

        var result = JMAObservation()
        result.stationID = main.id
        result.stationName = main.name

        result.sourceURL = Self.pointURL(station: main.id, at: date).absoluteString
        if let sample = try? await value(station: main.id, at: date) {
            result.observedAt = sample.date
            result.temp_10c = sample.values["temp"]?.scaledInt(scale: 1)
            result.humidity_p = sample.values["humidity"]?.intValue
        }

        // 気圧は観測所が少ないので、気圧を持つ最寄りから別に取る
        if let pressureStation = nearest(in: stations, to: coordinate, requiring: \.hasPressure) {
            let distance = pressureStation.distanceKm(to: coordinate)
            if distance <= Self.maxPressureStationDistanceKm,
               let sample = try? await value(station: pressureStation.id, at: date),
               let pressure = sample.values["pressure"]?.scaledInt(scale: 1) {
                result.pressureStationID = pressureStation.id
                result.pressureStationName = pressureStation.name
                result.pressureDistanceKm = distance
                result.pressure_10hpa = pressure
                // 24時間前も同じ観測所で取れたときだけ差を出す
                if let previous = try? await value(
                    station: pressureStation.id,
                    at: date.addingTimeInterval(-24 * 3600)
                ), let before = previous.values["pressure"]?.scaledInt(scale: 1) {
                    result.pressureDelta24h_10hpa = pressure - before
                }
            }
        }

        guard result.hasAnyValue else { throw JMAWeatherError.notAvailable }
        return result
    }

    /// 保持期間内か（未来は当日扱いで許可し、応答が無ければ欠測になる）
    nonisolated static func isWithinAvailableRange(_ date: Date, now: Date = Date()) -> Bool {
        let limit = Calendar.current.date(byAdding: .day, value: -availableDays, to: now) ?? now
        return date >= limit
    }

    // MARK: 観測所一覧

    private func loadStations() async throws -> [JMAStation] {
        if let stationsCache { return stationsCache }
        let url = URL(string: "https://www.jma.go.jp/bosai/amedas/const/amedastable.json")!
        let (data, _) = try await session.data(from: url)
        let raw = try JSONDecoder().decode([String: RawStation].self, from: data)
        let stations = raw.compactMap { id, value -> JMAStation? in
            guard value.lat.count == 2, value.lon.count == 2 else { return nil }
            // elems は要素ごとの有無を表す8桁の文字列。
            // 実データ1286件と観測値の有無を突き合わせて確認した桁位置（一致率99.8%）:
            //   index 0 = 気温 / 4 = 湿度 / 7 = 気圧
            let elems = Array(value.elems ?? "")
            func has(_ index: Int) -> Bool {
                elems.indices.contains(index) && elems[index] != "0"
            }
            return JMAStation(
                id: id,
                name: value.kjName,
                latitude: value.lat[0] + value.lat[1] / 60,
                longitude: value.lon[0] + value.lon[1] / 60,
                hasTemp: has(0),
                hasHumidity: has(4),
                hasPressure: has(7)
            )
        }
        stationsCache = stations
        logger.info("アメダス観測所を読み込み: \(stations.count)件")
        return stations
    }

    private func nearest(
        in stations: [JMAStation],
        to coordinate: CLLocationCoordinate2D,
        requiring keyPath: KeyPath<JMAStation, Bool>
    ) -> JMAStation? {
        stations
            .filter { $0[keyPath: keyPath] }
            .min { $0.distanceKm(to: coordinate) < $1.distanceKm(to: coordinate) }
    }

    // MARK: 地点別観測値

    private struct Sample {
        let date: Date
        let values: [String: JMAValue]
    }

    /// 指定時刻に最も近い10分値を取る
    private func value(station: String, at date: Date) async throws -> Sample {
        let block = try await pointData(station: station, at: date)
        let target = Self.timestampKey(for: date)
        // 同じブロック内で、指定時刻以前の最も新しい観測を選ぶ
        let candidate = block.keys.filter { $0 <= target }.max() ?? block.keys.min()
        guard let key = candidate, let values = block[key],
              let observedAt = Self.date(fromTimestamp: key) else {
            throw JMAWeatherError.notAvailable
        }
        return Sample(date: observedAt, values: values)
    }

    private func pointData(
        station: String,
        at date: Date
    ) async throws -> [String: [String: JMAValue]] {
        let path = Self.pointPath(for: date)
        let cacheKey = "\(station)/\(path)"
        if let cached = pointCache[cacheKey] { return cached }

        let url = Self.pointURL(station: station, at: date)
        let (data, response) = try await session.data(from: url)
        // 保持期間外は404。異常ではないので欠測として扱う
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw JMAWeatherError.outOfRange
        }
        let decoded = try JSONDecoder().decode([String: [String: JMAValue]].self, from: data)
        pointCache[cacheKey] = decoded
        return decoded
    }

    /// 地点別観測値のURL
    static func pointURL(station: String, at date: Date) -> URL {
        URL(string: "https://www.jma.go.jp/bosai/amedas/data/point/\(station)/\(pointPath(for: date)).json")!
    }

    // MARK: 時刻の組み立て

    private static let jst = TimeZone(identifier: "Asia/Tokyo") ?? .current

    private static var calendarJST: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        return calendar
    }

    /// `yyyyMMdd_HH`。HH は 00/03/06/09/12/15/18/21 のいずれかに切り下げる
    static func pointPath(for date: Date) -> String {
        let calendar = calendarJST
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let hourBlock = ((comps.hour ?? 0) / 3) * 3
        return String(
            format: "%04d%02d%02d_%02d",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0, hourBlock
        )
    }

    /// JSONのキー形式 `yyyyMMddHHmmss`
    static func timestampKey(for date: Date) -> String {
        let comps = calendarJST.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        return String(
            format: "%04d%02d%02d%02d%02d00",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0,
            comps.hour ?? 0, comps.minute ?? 0
        )
    }

    static func date(fromTimestamp key: String) -> Date? {
        guard key.count == 14 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            let start = key.index(key.startIndex, offsetBy: range.lowerBound)
            let end = key.index(key.startIndex, offsetBy: range.upperBound)
            return Int(key[start..<end])
        }
        var comps = DateComponents()
        comps.year = number(0..<4)
        comps.month = number(4..<6)
        comps.day = number(6..<8)
        comps.hour = number(8..<10)
        comps.minute = number(10..<12)
        comps.timeZone = jst
        return calendarJST.date(from: comps)
    }
}

// MARK: - JSON の形

/// アメダスJSONの観測値は `[値, 品質フラグ]`。フラグ0以外は欠測・利用不可なので使わない。
///
/// ただし同じレコードには配列でないキーも混ざる（`observationNumber` や `prefNumber` は数値、
/// `gustTime` はオブジェクト）。全キーを配列前提でデコードするとレコードごと失敗して
/// 観測値が1つも取れなくなるので、配列以外は「値なし」として受け流す。
struct JMAValue: Decodable, Equatable, Sendable {
    let value: Double?
    let quality: Int

    var isUsable: Bool { value != nil && quality == 0 }

    var intValue: Int? {
        guard isUsable, let value else { return nil }
        return Int(value.rounded())
    }

    func scaledInt(scale: Int) -> Int? {
        guard isUsable, let value else { return nil }
        return Int((value * pow(10, Double(scale))).rounded())
    }

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else {
            // 配列ではないキー（観測所番号・時刻オブジェクトなど）
            value = nil
            quality = -1
            return
        }
        value = try? container.decodeIfPresent(Double.self)
        quality = (try? container.decode(Int.self)) ?? 0
    }
}

private struct RawStation: Decodable {
    let kjName: String
    let lat: [Double]
    let lon: [Double]
    let elems: String?
}
