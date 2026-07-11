# Condition / 体調メモ 開発メモ

この `README.md` は、開発者向けの設計メモです。

**最新バージョン**: 2.7.1（2026-07-08）

**User Guide**  
[English](https://docs.azukid.com/en/sumpo/Condition/condition.html) / [日本語](https://docs.azukid.com/jp/sumpo/Condition/condition.html)

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![App Store](https://img.shields.io/badge/App%20Store-Download-blue)](https://apps.apple.com/app/id472914799)

## 概要

Condition は、血圧、心拍数、体温、体重、体脂肪率、骨格筋率などを記録して、日々の変化を確認するためのアプリです。

2012 年に公開した旧版を、2026 年に SwiftUI / SwiftData ベースで再構築しました。旧 Core Data 版の記録は、初回起動時に SwiftData へ自動移行します。

App Store の公開名は言語ごとに異なります（日本語: 体調メモ、英語: Vitalin、韓国語: 바이탈로그、繁体字中国語: 體徵記錄）。開発コード・リポジトリ・データストア名は `Condition` を正とします。

## 機能

- 血圧（収縮期 / 拡張期）、心拍数、体温、体重、体脂肪率、骨格筋率の記録
- 測定タイミングの自動分類 — 起床時、安静時、就寝前、就寝時、運動前、運動後
- 区分（測定タイミング）の並べ替え、アイコン・名称・色のカスタマイズ、記録一覧の区分フィルター
- [AZDial](https://github.com/SumPositive/AZDial) によるダイアル入力 — ハプティック付きのスクロールホイール操作
- Apple ヘルスケア連携 — 書き込みのみ、読み込みのみ、双方向を選択可能
- グラフ表示 — 1週間、1ヶ月、3ヶ月、6ヶ月、1年の期間を切り替え
- 補助グラフ — 平均血圧、体重移動平均などを表示可能
- 統計分析 — 血圧分布・JSH 基準比率・測定タイミング相関・体重×血圧相関散布図など
- PDF、CSV、JSON での書き出し
- 表示項目と並び順のカスタマイズ
- 外観モード — 自動、ライト、ダーク
- ダイアル設定 — デザイン、回しやすさ、反応を調整可能
- 文字サイズ対応 — iOS の Dynamic Type 設定に連動
- 多言語対応 — 日本語、英語、韓国語、繁体字中国語

## 構成

```text
Condition/
├── Components/       — 共通 UI コンポーネント
├── Core/
│   ├── Models/       — BodyRecord、DateOpt、MeasureRange
│   ├── DataStore/    — SwiftData 設定、旧 Core Data からの移行
│   ├── Services/     — HealthKitService、PDFPanelExporter
│   └── Settings/     — AppSettings、設定キー、TipStore
├── Features/
│   ├── RecordList/   — 記録一覧、エクスポート
│   ├── RecordEdit/   — 記録入力、編集、ダイアル入力
│   ├── Graph/        — グラフ表示、PDF 出力
│   ├── Statistics/   — 統計表示、PDF 出力
│   └── Settings/     — 設定画面
└── Resources/        — アセット、ローカライズ、Info.plist
```

**主な依存関係**
- [AZDial](https://github.com/SumPositive/AZDial) — SwiftUI スクロールホイール型ダイアル
- Google Mobile Ads SDK

## 必要環境

- iOS 17.0+
- Xcode 26+
- Swift 6

## Xcodeプロジェクト管理方針

- 当面は `Condition.xcodeproj` を正としてXcodeで直接管理する
- ターゲット、Build Settings、Build Phases、Package Dependencies、ファイル追加はXcode上で変更する
- XcodeGenは現在の開発フローでは使用しない
- `xcodegen generate` などで `Condition.xcodeproj` を再生成しない
- `project.yml` は過去の生成設定を確認するための参照専用で、最新状態との一致を保証しない
- CodexやClaude Codeなどの開発支援ツールも、明示的な依頼がない限りXcodeGenを導入・実行しない

## リリース履歴

| バージョン | 公開日 | 内容 |
|---|---|---|
| 2.0.0 | 2026-04-01 | SwiftUI / SwiftData で全面再構築、HealthKit 連携を追加 |
| 2.1.0 | 2026-04-22 | 外観モード、ダイアル設定、グラフ表示設定、ローカライズ改善 |
| 2.2.0 | 2026-05-10 | 体重×血圧相関散布図、グラフ目標ラインラベル、文字サイズ対応、初心者ヘルプバナー、UI 細部改善 |
| 2.3.0 | 2026-05-19 | iOS 26.5 対応、記録をまとめる機能（連続追加時に〔両方／直前／新しい／平均〕を選択） |
| 2.4.0 | 2026-05-27 | 新しい記録に「測定を追加」（最大5回まで集計して平均表示）、「計測機器」を「測定場所・機器」に変更（プリセット：自宅／病院／ジム、履歴選択対応） |
| 2.5.0 | 2026-06-03 | 区分推定（曜日と時間帯）、区分のアイコン・名称・色をカスタマイズ可能に、区分7・区分8 を追加、測定を追加：最終回の取消、グラフ（血圧／心拍数／脈圧）と統計（血圧分布）に区分選択、初心者ヘルプ改善 |
| 2.6.0 | 2026-06-20 | Xcode 26.5、複数回測定シート（表形式の連続入力＋平均値保存）、グラフ／統計パネルのハンドルで高さ調整 |
| 2.7.0 | 2026-07-06 | 区分の並べ替え（選択一覧・グラフに反映）、グラフ（心拍数・脈圧）のヘルプ解説、記録一覧の区分フィルター（PDF 出力にも反映） |
| 2.7.1 | 2026-07-08 | 韓国語・繁体字中国語に対応、英語アプリ名を Vitalin に変更、fastlane によるメタデータ・スクリーンショットの配信を追加 |

## ライセンス

本リポジトリのソースコードは参照目的で公開しています。
著作権は SumPositive に帰属します。
無断での複製、改変、再配布、商用利用を禁止します。

---

## 開発者メモ

### 区分推定アルゴリズム

新しい記録の区分は、設定の「新しい記録の区分を推定する」が ON の場合、`DateOptEstimator` で重み付きスコアを計算して決定する。この設定は新規インストールではデフォルト ON

基本方針:

- 対象履歴は推定基準日時から過去90日以内の通常記録
- 時間帯と区分の初期値マトリックスは、履歴が少ない時の土台として使う
- 過去記録は、曜日・時刻差・新しさを掛け合わせて、その記録の区分へ加点する
- 最大スコアと次点が僅差なら、説明しやすく安定した初期値マトリックスへ戻す

スコア構成:

```text
score[matrixDefault] += 1.5

for record in recordsWithin90Days:
    score[record.dateOpt] += weekdayWeight * timeWeight * recencyWeight
```

重み:

```text
weekdayWeight:
  同じ曜日 = 1.25
  違う曜日 = 1.0

timeWeight:
  exp(-((時刻差分 / 90)^2))
  0時前後の記録にも合うように、時刻差は24時間の循環距離で計算する

recencyWeight:
  max(0.5, 1.0 - daysAgo / 180.0)
  直近ほど強く、90日前でも0.5倍は残す
```

決定ルール:

```text
topScore - secondScore < 0.3:
    matrixDefault
else:
    topScore の区分
```

記録をまとめる時間内に直前記録がある場合は、従来通り直前記録の区分を最優先する。その後に推定、最後に時間帯マトリックスの順で決定する

設定の「区分」画面では、同じ `DateOptEstimator` を使う「区分推定　最新の分布表」画面へ遷移できる。横軸は曜日、縦軸は時刻、セルにはその曜日・時刻で選ばれる区分アイコンを表示する。区分推定の初期設定マトリックスは、推定 ON/OFF に関係なく常に表示する。推定が OFF の場合は分布表ボタンを表示しない

区分の表示は `DateOptAppearance` として `UserDefaults` に保存する。日本語名は日本語だけを許可して4文字以内、英語名は英語だけを許可して8文字以内の省略名に制限する。アイコンは生活・睡眠・運動・測定を表すSF Symbols候補から選択し、色はグラフや一覧で識別しやすい固定パレットから選択する

### DataStore 設計

#### SwiftData ストアファイルの命名

SwiftData は `ModelConfiguration(name:)` に渡した名前で `<name>.store` というファイルを Application Support に作成する（`.sqlite` ではない）。

| 世代 | ストア名 | ファイル |
|---|---|---|
| v2.0（初代 SwiftData） | `"AzBodyNote"` | `AzBodyNote.store` |
| v2.1以降（現行） | `"Condition"` | `Condition.store` |

v2.0 で `ModelConfiguration("AzBodyNote")` を使っていたため、CoreData 時代の `AzBodyNote.sqlite` とは別に `AzBodyNote.store` が作成されていた。v2.1 でストア名を `"Condition"` に変更したことで、`AzBodyNote.store` → `Condition.store` へのリネームが必要になった。

#### ストア名決定ロジック（`ModelContainer+Setup.swift`）

起動時に Application Support の状態を見てストア名を決定する。`ModelContainer.shared` の初期化より前に `renameSwiftDataStoreIfNeeded()` を呼び、リネームできる場合は済ませておく。

```
(conditionExists, azBodyNoteExists, migrationDone) の組み合わせ

(true,  false, *)    → "Condition"（通常）
(false, false, *)    → "Condition"（新規インストール）
(false, true,  true) → AzBodyNote.store → Condition.store へリネーム試行
(true,  true,  true) → resolveConflict()：レコード有無で判定
default              → "Condition"（CoreData 移行前ユーザー等）
```

`resolveConflict()` では SQLite3 API で直接 `sqlite_master` を参照し、ユーザーデータテーブルにレコードがあるかを確認する。Condition が空で AzBodyNote にデータがある場合は Condition を `.empty` にアーカイブして AzBodyNote をリネームする。

---

### CoreData → SwiftData マイグレーション設計

#### 対象ユーザー

旧版（CoreData 時代、2012〜）から移行してきたユーザー。`AzBodyNote.sqlite` が Application Support または Documents に存在する。

#### フラグ

`UserDefaults` キー `"MigrationV2Done"`（`UDefKeys.migrationDone`）

- `false`（未設定）: 移行未実施または失敗
- `true`: 移行完了（`findOldStoreURL()` は検索をスキップする）

`migrationDone=true` のユーザーが持つ `AzBodyNote.sqlite` は SwiftData ストアではなくアーカイブ済みの CoreData ファイル（`.done` 拡張子）なので触らない。

#### 移行フロー（`MigrationService.swift`）

```
1. findOldStoreURL()
   └─ migrationDone=true → nil（スキップ）
   └─ migrationDone=false → AzBodyNote.sqlite を検索

2. repairWALIfNeeded()
   └─ -wal / -shm が存在しなければ空ファイルで補完（iCloud 復元対策）

3. fetchViaCoreData()  ← まず CoreData API で試みる
   └─ 失敗した場合 fetchViaSQLite() へフォールバック

4. insertRows()
   └─ 既存 SwiftData レコードの dateTime を Set で収集
   └─ 重複する dateTime はスキップ（再試行時・スキップ後入力分を保護）

5. 成功: archiveOldStore() → .sqlite を .done にリネーム
         migrationDone = true

6. 失敗: .sqlite はそのまま残す → 次回アップデートで自動再試行
```

#### SQLite 直接読み取りの列名規則

CoreData の SQLite 列名は `"Z" + attributeName.uppercased()`。

| CoreData 属性 | SQLite 列名 |
|---|---|
| `dateTime` | `ZDATETIME` |
| `nDateOpt` | `ZNDATEOPT` |
| `nBpHi_mmHg` | `ZNBPHI_MMHG` |
| `nSkMuscle_10p` | `ZNSKMUSCLE_10P` |

テーブル名: `ZE2RECORD`（entity 名 `E2record` → `"Z" + "E2RECORD"`）

#### ファイル変遷（CoreData 移行済みユーザーの典型例）

```
旧アプリ（CoreData）
  AzBodyNote.sqlite        ← CoreData 本体
  AzBodyNote.sqlite-shm
  AzBodyNote.sqlite-wal

v2.0（SwiftData 移行完了後）
  AzBodyNote.sqlite.done   ← CoreData アーカイブ（以後不変）
  AzBodyNote.store         ← SwiftData（ModelConfiguration("AzBodyNote")）
  AzBodyNote.store-shm
  AzBodyNote.store-wal
  migrationDone = true

v2.1（ストア名変更後、修正適用済み）
  AzBodyNote.sqlite.done   ← そのまま
  Condition.store          ← AzBodyNote.store をリネーム
  Condition.store-shm
  Condition.store-wal
  Condition.store.empty    ← 旧バージョンが作成した空ファイルのアーカイブ（あれば）
```

#### 「スキップして続行」の挙動

移行失敗時に「スキップして続行」を選択すると `phase = .done` になるが `migrationDone` は立てない。次回アップデートで `AzBodyNote.sqlite` が再検出され、自動的に移行が再試行される。スキップ後に入力したデータは `insertRows()` の重複チェックにより保護される。
