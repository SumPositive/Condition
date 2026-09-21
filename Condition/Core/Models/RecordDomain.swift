// RecordDomain.swift
// 記録一覧の絞り込みと、測定／症状をまとめて時系列に並べるための行の型

import Foundation

/// 記録一覧の絞り込み。既定は「すべて」で、測定と症状を混ぜて時系列に見せる
enum RecordDomain: Int, CaseIterable, Identifiable {
    case all         = 0
    case measurement = 1
    case symptom     = 2

    var id: Int { rawValue }

    var labelKey: String {
        switch self {
        case .all:         return "filter.domain.all"
        case .measurement: return "filter.domain.measurement"
        case .symptom:     return "filter.domain.symptom"
        }
    }

    var icon: String {
        switch self {
        case .all:         return "list.bullet"
        case .measurement: return "heart.text.square"
        case .symptom:     return "bandage"
        }
    }

    var includesMeasurement: Bool { self != .symptom }
    var includesSymptom: Bool     { self != .measurement }
}

/// 一覧の1行。測定と症状を1つの時系列へ混ぜるためのラッパー
enum RecordListRow: Identifiable {
    case measurement(BodyRecord)
    case symptom(SymptomRecord)

    var id: String {
        switch self {
        case .measurement(let record): return "m:\(record.persistentModelID.hashValue)"
        case .symptom(let record):     return "s:\(record.persistentModelID.hashValue)"
        }
    }

    /// 並べ替えとセクション分けに使う日時
    var sortDate: Date {
        switch self {
        case .measurement(let record): return record.dateTime
        case .symptom(let record):     return record.startAt
        }
    }

    var yearMonth: Int {
        switch self {
        case .measurement(let record): return record.yearMonth
        case .symptom(let record):     return record.yearMonth
        }
    }
}
