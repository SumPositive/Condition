// DateOpt.swift
// 測定時の状況区分（旧 MocEntity.h の DateOpt enum 相当）

import Foundation
import SwiftUI

enum DateOpt: Int, CaseIterable, Codable, Identifiable {
    case wake        = 0  // 起床時
    case rest        = 1  // 安静時
    case down        = 2  // 就寝前
    case sleep       = 3  // 就寝時
    case preExercise = 4  // 運動前
    case postExercise = 5 // 運動後

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .wake:         return "category.wake"
        case .rest:         return "category.rest"
        case .down:         return "category.beforeBed"
        case .sleep:        return "category.bedtime"
        case .preExercise:  return "category.preExercise"
        case .postExercise: return "category.postExercise"
        }
    }

    var icon: String {
        switch self {
        case .wake:         return "sun.horizon.fill"
        case .rest:         return "heart.fill"
        case .down:         return "moon.fill"
        case .sleep:        return "moon.zzz.fill"
        case .preExercise:  return "figure.run"
        case .postExercise: return "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .wake:         return .green
        case .rest:         return .blue
        case .down:         return .orange
        case .sleep:        return .purple
        case .preExercise:  return .teal
        case .postExercise: return .red
        }
    }

    var shortLabel: String {
        switch self {
        case .wake:         return "category.wake.short"
        case .rest:         return "category.rest.short"
        case .down:         return "category.beforeBed.short"
        case .sleep:        return "category.bedtime.short"
        case .preExercise:  return "category.preExercise.short"
        case .postExercise: return "category.postExercise.short"
        }
    }
}

// MARK: - データ入力元

enum RecordDataSource: Int {
    case appInput    = 0  // このアプリで入力された記録です
    case appModified = 1  // このアプリで入力後に変更された記録です
    case hkImport    = 2  // ヘルスケアから読み込まれた記録です
    case hkModified  = 3  // ヘルスケアから読み込まれた後に変更された記録です

    var icon: String {
        switch self {
        case .appInput:    return "app"
        case .appModified: return "app.fill"
        case .hkImport:    return "heart"
        case .hkModified:  return "heart.fill"
        }
    }

    var color: Color {
        return .secondary
    }

    var label: String {
        switch self {
        case .appInput:    return "text.enteredInThisApp"
        case .appModified: return "text.enteredInThisAppAndLater"
        case .hkImport:    return "health.thisRecordWasImportedFromHealthkit"
        case .hkModified:  return "health.thisRecordWasModifiedAfterBeing"
        }
    }
}
