# Condition / 体調メモ 開発メモ

この `README.md` は、開発者向けの設計メモです。

**最新バージョン**: 2.9.1（準備中）

**User Guide**  
[English](https://docs.azukid.com/en/sumpo/Condition/condition.html) / [日本語](https://docs.azukid.com/jp/sumpo/Condition/condition.html) / [한국어](https://docs.azukid.com/ko/sumpo/Condition/condition.html) / [繁體中文](https://docs.azukid.com/zh-Hant/sumpo/Condition/condition.html)

![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![App Store](https://img.shields.io/badge/App%20Store-Download-blue)](https://apps.apple.com/app/id472914799)

## 概要

Condition は、血圧、心拍数、体温、体重、体脂肪率、骨格筋率などを記録して、日々の変化を確認するためのアプリです。2.9.0 からは、頭痛・肩こりなどの症状を、発症時の環境や直前の状況と一緒に記録して分析する「症状メモ」を備えます。

2012 年に公開した旧版を、2026 年に SwiftUI / SwiftData ベースで再構築しました。旧 Core Data 版の記録は、初回起動時に SwiftData へ自動移行します。

App Store の公開名は言語ごとに異なります（日本語: 体調メモ、英語: Vitalin、韓国語: 바이탈로그、繁体字中国語: 體徵記錄）。開発コード・リポジトリ・データストア名は `Condition` を正とします。

## 機能

- 血圧（収縮期 / 拡張期）、心拍数、体温、体重、体脂肪率、骨格筋率の記録
- 複数回測定 — 1 件の記録に複数回の測定値を保存・編集し、平均値を保存
- 血圧の測定部位（左右の腕・手首）を「L・R」で指定 — 記録一覧に表示、統計に左右差パネル
- 測定タイミングの自動分類 — 起床時、安静時、就寝前、就寝時、運動前、運動後
- 区分（測定タイミング）の並べ替え、アイコン・名称・色のカスタマイズ、記録一覧の区分フィルター
- 起動時に開く画面の選択 — 何もしない／新しい記録／記録一覧／分析1〜3
- [AZDial](https://github.com/SumPositive/AZDial) によるダイアル入力 — ハプティック付きのスクロールホイール操作
- Apple ヘルスケア連携 — 書き込みのみ、読み込みのみ、双方向を選択可能
- 症状メモ — 症状・発症／終息日時・程度・直前の状況・対処・メモを記録（測定と同じ一覧に時系列で表示）
- 環境の記録 — 気温・湿度・気圧・24時間気圧差（国内は気象庁アメダスから取得）、室温・室内湿度、端末の気圧計。症状・測定の両方で記録可能
- 分析1〜3 — グラフ・統計・症状の図表を3ページへ自由に配置（期間は 1週間〜1年をページごとに切り替え）
- グラフ — 血圧・脈圧・心拍数・体温・体重・体重変化量・体脂肪率・骨格筋率・BMI、補助グラフ（平均血圧、体重移動平均など）
- 統計 — 血圧分布・JSH 基準比率・測定タイミング相関・血圧の左右差・体重×血圧相関散布図など
- 症状の分析 — 発症カレンダー・発症の周期性・発症と環境・発症と直前の状況
- 記録一覧の絞り込み — すべて／測定（区分）／症状（症状名）
- PDF、CSV、JSON での書き出し（記録一覧の絞り込みに従う）、全記録の JSON バックアップ
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
│   ├── Models/       — BodyRecord、SymptomRecord、SymptomCatalog、EnvironmentSnapshot、AnalysisLayout、DateOpt
│   ├── DataStore/    — SwiftData 設定、旧 Core Data からの移行
│   ├── Services/     — HealthKitService、RecordsJSONIO、JMAWeatherService、DevicePressureService、PDFPanelExporter
│   └── Settings/     — AppSettings、設定キー、TipStore
├── Features/
│   ├── RecordList/   — 記録一覧、エクスポート
│   ├── RecordEdit/   — 記録入力、編集、ダイアル入力
│   ├── SymptomEdit/  — 症状の記録、症状・直前の状況・対処のタグ選択
│   ├── Environment/  — 環境（気象・室内・端末気圧）の入力シート
│   ├── Graph/        — 分析ページ（AnalysisPageView）、グラフ表示、PDF 出力
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
| 2.7.2 | 2026-07-12 | テンキー入力の自動確定（値が確定すると次の項目へ自動遷移）、アプリアイコンを刷新（ハート＋水面の波紋） |
| 2.8.0 | 2026-07-19 | 複数回測定値の保存・編集、血圧の測定部位（左右）を「L・R」で指定（記録一覧・統計に左右差パネル）、設定「起動時に開く」で起動時の画面を選択、ダイアル／ステッパーの増減幅を最小単位に統一 |
| 2.8.1 | 2026-07-28 | 統計「左右差」を左右ペアの測定値だけで集計するよう修正、新しい記録シートを開いたまま終了した場合の日時・区分更新、Apple ヘルスケア双方向連携の削除同期を改善、潜在的な不具合を修正 |
| 2.8.2 | 2026-08-11 | 新しい記録（表形式）にメモセクション（測定場所・機器／メモ1／メモ2／注意フラグ）を追加、ばらつき（±SD）が赤いときの主因となる測定値を赤字表示、保存時に全列が空の行を詰める、`AZMemoEditor` のフォーカス解除を修正 |
| 2.8.3 | 2026-09-13 | 測定場所・機器の入力に候補一覧（プリセット＋入力履歴）を追加、記録タブの再タップで新しい記録の追加シートを表示、設定の選択肢を `AZPicker` のプルダウンリストに統一、iPad レイアウトを調整、広告をヘッダー部バナーのみに整理、`AZMemoEditor` 入力中のキーボード閉じを修正 |
| 2.9.0 | 2026-10-04 | 症状メモ（発症〜終息の日時、気温・気圧などの環境、直前の状況・対処を記録して分析）、測定にも環境を記録（国内は自動取得）、グラフと統計を3つの分析タブに統合（図表の自由配置・タブ名変更・期間の同期 ON/OFF、既存利用者は OFF で開始）、区分の既定を 起床時・安静時・就寝前・不調時・運動前 に見直し（既存利用者は旧既定を固定）、起動時に開く を 何もしない／測定を追加／症状を追加／記録一覧 に整理、起動の高速化（広告の初期化を起動シート表示後へ）、バックアップにアプリ設定を追加、起動画面にアイコン、iOS 18 以降に変更、メモ入力で改行すると確定してしまう不具合を修正 |
| 2.9.1 | 準備中 | 端末の暦が和暦などでも日付が正しく表示されるよう、記録・集計・症状カレンダー・書き出しの暦を西暦に固定（`AppDateCalendar`、`DatePicker` にも西暦を指定）、症状カレンダーと日付入力の週開始曜日を端末の「週の始まりの曜日」に合わせる、日時表示を端末の言語・地域に従いつつ月/日を見やすく（`ValueFormatter`）。設計は `DESIGN.md` の「1.1 日付と端末の暦設定」 |

## ライセンス

本リポジトリのソースコードは参照目的で公開しています。
著作権は SumPositive に帰属します。
無断での複製、改変、再配布、商用利用を禁止します。

---

## 開発者メモ

### 症状メモ設計（2.9.0）

**データ**
- `SymptomRecord`（SwiftData）は 1 レコード 1 症状。症状・直前の状況・対処は表示名ではなく ID で保存する（4 言語で集計キーが割れないように）
- 直前の状況・対処は複数持てるので、ID 配列を JSON 文字列（`sTriggerIDs` / `sMedicineIDs`）で持ち、`triggerIDs` / `medicineIDs` でアクセスする。1 件あたり各 10 個まで
- 症状の状態は3種類。継続中は `bOngoing = true`・`endAt = nil`、終息日時ありは `bOngoing = false`・`endAt` あり、終息日時不明は `bOngoing = false`・`endAt = nil` で表す
- 環境は `EnvironmentSnapshot` で測定記録と共通。0℃・0%・変化量 0 は有効値なので、値ではなく入力有無フラグ（`bTempSet` など）で判定する

**タグ（症状・直前の状況・対処）**
- 内蔵辞書 `SymptomCatalog` / `TriggerCatalog` / `MedicineCatalog`（症状・対処は10件、直前の状況は11件）は読み取り専用。利用者が選んだものだけがタグリスト（UserDefaults に JSON、`KVS_SettSymptomTags` / `KVS_SettTriggerTags` / `KVS_SettMedicineTags`）に入る
- ユーザー追加タグの ID は `u:<UUID>`。削除は非表示のみ（過去の記録が名前を参照するため）。並びは最終使用日時の降順（MRU）
- 種類ごとの分岐は `SymptomTagKind` の拡張（`tagList` / `displayName(of:)` / 辞書の引き先）に集約
- 辞書を変えたら `SymptomTagMigration.catalogVersion` を上げる。起動時に一度だけ、名前の引き先が無いタグの片付けと、辞書と同名の自作タグの統合を行う
- 直前の状況の「思い当たらない」は先頭の固定プリセットタグ。単独選択・名前変更不可・青色表示とし、空欄は未選択として扱う

**分析**
- 図表 ID は `AnalysisPanelID`（名前空間付き文字列で永続化）。追加した図表は `AnalysisLayout.normalize()` が既定ページの末尾へ補う
- 発症件数は発症日時で数える（`SymptomAnalysisRange.containsStart`）。日をまたいで終息しても 2 件にしない。数えるのは軽い以上（`1 < nSeverity`）で、程度「なし」と外部取り込みの「未指定」は数えない（発症カレンダーの円には最大程度として残す）
- 発症カレンダーは上部の期間に関係なく年・月・日でたどる
- 周期性は単一症状の発症間隔の中央値とばらつきから推定（4 件以上）

**書き出し・バックアップ**
- 記録一覧の書き出し（PDF・CSV・JSON）は一覧の絞り込み（種別・区分・症状）に従う。CSV は測定と症状を別の表にする
- 設定の「全記録を書き出す」（`RecordsJSONIO`、schemaVersion 2）は症状・タグリストを含む。直前の状況は任意項目の追加なので版は上げていない

**スクリーンショット**
- `SnapshotSeed` が症状 22 件（直前の状況・対処・環境つき、環境は地名なしの手入力扱い）を投入する。分析3は上部と下へ送った位置の 2 カット

### 睡眠（起床時の補助データ）設計

**データ**
- `BodyRecord.dSleepStart`（nil = 未入力）と `nSleep_min`（0 = 未入力、-1 = 不眠、630 = 10時間超）。どちらも既定値付きの追加なので軽量マイグレーションで済む
- 入力・保存は区分 `cat01`（既定名「起床時」）に固定（`SleepEntry.dateOpt`）。保存時に区分が `cat01` 以外なら睡眠を消す
- `cat01` の名称は変更できる。設定の区分編集で、名称欄の下に「区分1（起床時）には、睡眠データを記録して分析ができます」と表示する
- 入力はプルダウンで30分刻み。入眠時刻は記録日時の18時間前〜記録日時（未入力時は8時間前を中央に表示）、睡眠時間は 10時間超・10時間〜30分・不眠（未入力時は6時間を中央に表示）
- ヘルスケアから取得した値は30分刻みにせず、そのまま保存する。プルダウンには取得値を選択肢として足して表示する（`SleepEntry.normalized` は範囲外を外すだけ）

**ヘルスケアから取得**
- 入力シート（`SleepEditSheet`）の「睡眠データを取得する」だけが読み取る。同期設定とは別に、押したときに `sleepAnalysis` の読み取り許可を求める。ヘルスケアへは書き込まない
- 範囲は記録日時の 18 時間前〜記録日時。範囲に重なるサンプルを取り、範囲外は切り詰める
- 自動取得（`AppSettings.sleepAutoFetch`、既定 OFF、端末ごとの設定でバックアップ対象外）が ON なら、区分1の新しい記録を開いたとき・区分1で日時を変えたとき・区分1に変えたときに取得する。見つからないときは何も出さず入力中の値を残す。取得だけの睡眠は新しい記録の「入力あり」に数えない
- 睡眠（段階不明・コア・深い・レム）の区間を合わせて二重計上を防ぎ、60 分以内の中断はまとめて 1 回の睡眠とする。最も長いものを採用（同じ長さなら新しい方）。`awake` は数えない
- 睡眠の区間が無いとき（iPhone のみなど）は `inBed` で代用
- 読み取り拒否と 0 件は区別できないので、見つからないときは許可の確認も促す
- 判定は `SleepSessionLogic`（HealthKit 非依存）にまとめ、`SleepSessionTests` で検証

**分析**
- 統計「血圧 × 入眠時刻」「血圧 × 睡眠時間」（`StatSection` 12・13）。`cat01` で睡眠と血圧の両方がある記録だけを使う。r は収縮期で計算
- 入眠時刻は正午より前を 24 時以降として扱い、日付をまたいでも横軸が連続するようにする

**書き出し**
- バックアップ JSON は `sleep: { start, minutes }`、無いときは null（キー無しの旧形式は既存値を保持）。schemaVersion は上げていない
- 記録一覧の CSV は、対象に睡眠の入力があるときだけ「入眠時刻」「睡眠時間」列を足す（睡眠時間は画面と同じ表記）。一覧の JSON は不眠を `sleepMinutes: 0`、10時間超を `sleepOver10Hours: true` で出す
- バックアップ JSON の minutes は保存値のまま（-1・630 も）書き、取り込みで元に戻す

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
