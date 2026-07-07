# App Store スクリーンショットの自動撮影・アップロード（Vitalin / 体調メモ）

`fastlane snapshot` でシミュレータからスクショを自動撮影し、`deliver` でアップロードします
撮影対象は 4 タブ（記録一覧 / グラフ / 統計 / 設定）の 4 カット
まずは **ja/en-US × iPhone 17 Pro Max** で仕組みを検証し、動いたら言語・デバイスを増やす方針です

---

## ステップ 0: 用意済みファイル

Claude が以下を用意済みです:

**アプリ本体側（撮影時のサンプルデータ投入。DEBUG 限定・実ストアには触れない）**
- `Condition/Core/DataStore/SnapshotSeed.swift` … 直近 60 日分の体調記録サンプルを in-memory 投入
- `Condition/Core/DataStore/ModelContainer+Setup.swift` … snapshot 時のみ in-memory ストアへ切替（追記済み）
- `Condition/Core/DataStore/MigrationService.swift` … snapshot 時は移行をスキップし即本編へ（追記済み）

**UITest 側（新規ターゲットに取り込む素材）**
- `ConditionUITests/SnapshotHelper.swift` … fastlane 公式ヘルパー（Xcode 26 対応版）
- `ConditionUITests/ConditionUITests.swift` … 撮影用 UI テスト（4 タブを index でタップして 4 カット）

**fastlane 設定**
- `fastlane/Snapfile` … 撮影対象の言語・デバイス設定
- `fastlane/Fastfile` … レーン `screenshots` / `upload_screenshots` / `screenshots_and_upload`（既存）

> DialSplit と違い、Condition にはまだ UITest ターゲットがありません
> ステップ 1 で新規に `ConditionUITests` ターゲットを作成します

---

## ステップ 1: Xcode で UITest ターゲットを新規作成（← 手動 GUI 操作）

1. `Condition.xcodeproj` を Xcode で開く
2. **File > New > Target… > UI Testing Bundle** を選択
3. Product Name を **`ConditionUITests`**、Target to be Tested を **`Condition`** にして Finish
4. 自動生成された `ConditionUITests/ConditionUITests.swift`（雛形）を、
   用意済みの `ConditionUITests/ConditionUITests.swift` の内容で置き換える
   （このリポジトリのファイルがすでに正なので、Xcode がターゲット作成時に作った
   雛形ファイルを削除し、既存の 2 ファイルをターゲットに **Add Files** で紐付けてもよい）
5. `ConditionUITests/SnapshotHelper.swift` を **ConditionUITests ターゲットにのみ**追加する
   （Target Membership を UITest だけにチェック。アプリ本体には入れない）

> SnapshotHelper.swift はアプリ本体ターゲットには入れないこと（UITest 専用）

---

## ステップ 2: スキーム設定（テストを共有可能に）

1. Xcode の **Product > Scheme > Manage Schemes…**
2. `Condition` スキームの **Shared** にチェックが入っていることを確認
3. **Edit Scheme… > Test** タブで、`ConditionUITests` がテスト対象に含まれていることを確認

---

## ステップ 3: 撮影して確認（アップロードしない）

まず検証用に 2 言語・iPhone のみへ絞ると速いです（`Snapfile` を一時編集）:

```ruby
devices(["iPhone 17 Pro Max"])
languages(["ja","en-US"])
```

```bash
cd /Users/sumpositive/GitLocal/Condition
fastlane screenshots
```

- 初回はシミュレータのビルド＆起動で数分かかる
- 成功すると `fastlane/screenshots/` に言語別フォルダ＋PNG が出力され、一覧 HTML が開く
- `01Records` `02Graph` `03Statistics` `04Settings` の 4 枚が撮れていれば検証成功 🎉

うまくいかない場合の主な原因:
- シミュレータ名が違う → `Snapfile` の `devices([...])` を
  `xcrun simctl list devices` に出る名前に合わせる
- UITest が走らず 0 枚 → `Snapfile` の `only_testing` / `scheme` を確認
- グラフ・統計が空 → サンプルデータ未投入。`-FASTLANE_SNAPSHOT YES` は SnapshotHelper が
  自動付与するので、`SnapshotSeed.isActive` と in-memory 切替が DEBUG ビルドで効いているか確認
- クローン起動が拒否される → 実行前に
  `xcrun simctl shutdown all` +
  `sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService` でクリーンに

---

## ステップ 4: 本番展開（検証OK後）

- `Snapfile` を 4 言語（ja/en-US/ko/zh-Hant）× iPhone/iPad の本番設定に戻す
- カットを増やしたい場合は `ConditionUITests.swift` の `testTakeScreenshots` に
  画面遷移 + `snapshot("05...")` を追記。要素特定はローカライズ文言に依存しない
  `accessibilityIdentifier` を UI に付けると安定

---

## ステップ 5: アップロード（審査提出はしない）

```bash
cd /Users/sumpositive/GitLocal/Condition
fastlane upload_screenshots      # 撮影済みを反映
# または
fastlane screenshots_and_upload  # 撮影 → アップロードを一気に
```

- API キー認証（`.env` の ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH）はメタデータ更新と共通
- `skip_metadata: true` なので説明文等には触らない／スクショだけ差し替え
- `submit_for_review: false` なので審査には出ない

---

## 注意

- **必須サイズは iPhone 6.9"（iPhone 17 Pro Max）** と **iPad 13"（iPad Pro 13-inch (M5)）**
- `fastlane/screenshots/` は再生成可能な成果物（`.gitignore` 除外の運用に）
- 体調メモは通貨を扱わないため、DialSplit / CreditMemo の `-SNAPSHOT_CURRENCY_LOCALE` 渡しは不要
