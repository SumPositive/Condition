// SettingsKeys.swift
// UserDefaults キー定数（旧 Global.h の KVS_* 定数群）
// 既存ユーザーの設定を引き継ぐためキー名は旧コードと完全一致させること

import Foundation

enum SettingsKeys {
    // MARK: - グラフ設定
    static let settGraphs       = "KVS_SettGraphs"      // グラフパネル順序 (Data: [Int])
    static let settFieldHidden  = "KVS_SettFieldHidden" // 非表示フィールド rawValue 配列 ([Int])
    static let settGraphOneWid  = "KVS_SettGraphOneWid" // 1レコード幅
    static let settGraphBpMean  = "KVS_SettGraphBpMean" // 平均血圧表示
    static let settGraphBpPress = "KVS_SettGraphBpPress"// 脈圧表示
    static let settGraphBMITall = "KVS_SettGraphBMITall"// 身長(cm) for BMI
    static let settGraphBMI          = "KVS_SettGraphBMI"           // BMIグラフ表示
    static let settGraphWeightMA     = "KVS_SettGraphWeightMA"       // 体重移動平均
    static let settGraphWeightChange = "KVS_SettGraphWeightChange"   // 体重変化量
    static let settGraphBpLineMode    = "KVS_SettGraphBpLineMode"     // 血圧グラフ線モード
    static let settGraphBpHiddenDateOpts = "KVS_SettGraphBpHiddenDateOpts" // 血圧グラフで非表示にする区分 ([Int])
    static let settDialStyle         = "KVS_SettDialStyle"           // ダイアルスタイル (DialStyle.rawValue)
    static let settDialStyleForcedVersion = "KVS_DialStyleForcedVersion" // ダイアルスタイル強制移行版
    static let settDialTuning        = "KVS_SettDialTuning"          // ダイアル操作感度 (JSONデータ)
    static let settDialTuningMildMigrationVersion = "KVS_DialTuningMildMigrationVersion" // ダイアル操作感度の控えめ移行版

    // MARK: - 統計設定
    static let settStatType            = "KVS_SettStatType"           // 統計タイプ (0=Hi-Lo, 1=24H)
    static let settStatDays            = "KVS_SettStatDays"           // 集計日数
    static let settStatAvgShow         = "KVS_SettStatAvgShow"        // 平均±標準偏差表示
    static let settStatTimeLine        = "KVS_SettStatTimeLine"       // 時系列線表示
    static let settStat24HLine         = "KVS_SettStat24H_Line"       // 24H線表示
    static let settStatSections        = "KVS_SettStatSections"       // 統計セクション順序 ([Int])
    static let settStatHiddenSections  = "KVS_SettStatHiddenSections" // 非表示統計セクション ([Int])
    static let settStatBpDistributionHiddenDateOpts = "KVS_SettStatBpDistributionHiddenDateOpts" // 血圧分布で非表示にする区分 ([Int])
    static let settGraphDisplayOrder   = "KVS_SettGraphDisplayOrder"  // グラフ専用パネル順序 ([Int])
    static let settGraphHiddenPanels   = "KVS_SettGraphHiddenPanels"  // グラフ専用非表示パネル ([Int])
    static let settGraphHeightOverrides = "KVS_SettGraphHeightOverrides" // グラフ別追加高さ (JSON {kindRaw: extraHeight CGFloat})
    static let settStatHeightOverrides  = "KVS_SettStatHeightOverrides"  // 統計図別追加高さ (JSON {sectionRaw: extraHeight CGFloat})

    // MARK: - 機能切替
    static let bGoal            = "KVS_bGoal"           // 目標値機能
    // MARK: - 日付オプション時刻（前後2時間で自動判定）
    static let dateOptWakeHour  = "KVS_DateOptWake_HOUR"
    static let dateOptRestHour  = "KVS_DateOptRest_HOUR"
    static let dateOptDownHour  = "KVS_DateOptDown_HOUR"
    static let dateOptSleepHour = "KVS_DateOptSleep_HOUR"
    /// 時刻→区分マトリックス ([Int] 24要素, -1=未割当=.restにフォールバック)
    static let settDateOptHourMap = "KVS_SettDateOptHourMap"
    static let settDateOptAppearances = "KVS_SettDateOptAppearances" // 区分の名称・アイコン・色 (JSONデータ)

    // MARK: - 目標値
    static let goalBpHi      = "Goal_nBpHi_mmHg"
    static let goalBpLo      = "Goal_nBpLo_mmHg"
    static let goalPulse     = "Goal_nPulse_bpm"
    static let goalWeight    = "Goal_nWeight_10Kg"
    static let goalTemp      = "Goal_nTemp_10c"
    static let goalBodyFat   = "Goal_nBodyFat_10p"
    static let goalSkMuscle  = "Goal_nSkMuscle_10p"
    static let goalBpPp      = "Goal_nBpPp_mmHg"
    static let goalBMI       = "Goal_nBMI_10"

    // MARK: - 購入状態
    static let unlockProductID = "com.azukid.AzBodyNote.Unlock"

    static let migratableKeys: [String] = [
        settGraphs,
        settFieldHidden,
        settGraphOneWid,
        settGraphBpMean,
        settGraphBpPress,
        settGraphBMITall,
        settGraphBMI,
        settGraphWeightMA,
        settGraphWeightChange,
        settGraphBpLineMode,
        settGraphBpHiddenDateOpts,
        settDialStyle,
        settDialStyleForcedVersion,
        settDialTuning,
        settDialTuningMildMigrationVersion,
        settStatType,
        settStatDays,
        settStatAvgShow,
        settStatTimeLine,
        settStat24HLine,
        settStatSections,
        settStatHiddenSections,
        settStatBpDistributionHiddenDateOpts,
        settGraphDisplayOrder,
        settGraphHiddenPanels,
        bGoal,
        dateOptWakeHour,
        dateOptRestHour,
        dateOptDownHour,
        dateOptSleepHour,
        settDateOptHourMap,
        settDateOptAppearances,
        goalBpHi,
        goalBpLo,
        goalPulse,
        goalWeight,
        goalTemp,
        goalBodyFat,
        goalSkMuscle,
        goalBpPp,
        goalBMI,
        unlockProductID,
    ]
}

enum UDefKeys {
    // MARK: - UserDefaults（デバイス個別設定）
    static let migrationDone = "MigrationV2Done"    // CoreData→SwiftData移行完了フラグ

    // MARK: - HealthKit（デバイス個別設定）
    static let hkEnabled        = "UDEF_HKEnabled"
    static let hkDirection      = "UDEF_HKDirection"       // HKSyncDirection.rawValue
    static let hkDisabledByDemo = "UDEF_HKDisabledByDemo"  // Demo生成後は再有効化不可
    static let hkLastAutoImportAt = "UDEF_HKLastAutoImportAt" // 自動同期の最終実行日時
    static let appearanceMode   = "UDEF_AppearanceMode"    // 外観モード rawValue
    static let userLevel        = "UDEF_UserLevel"          // ユーザレベル rawValue
    static let fontScale        = "UDEF_FontScale"          // 文字サイズ rawValue
    static let settingsMigratedFromKVS = "UDEF_SettingsMigratedFromKVS" // 旧KVS設定の移行済みフラグ
    static let openNewRecordOnForeground = "UDEF_OpenNewRecordOnForeground" // フォアグランド復帰時に新しい記録を開く
    static let mergeWindowMinutes        = "UDEF_MergeWindowMinutes"        // 記録をまとめる時間（分）0=しない
    static let mergeDefaultAction        = "UDEF_MergeDefaultAction"        // 衝突解決の初期選択 ConflictAction.rawValue
    static let estimateDateOpt           = "UDEF_EstimateDateOpt"           // 区分を蓄積記録から推定して初期表示する
}
