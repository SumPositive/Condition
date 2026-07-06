# App Store メタデータの更新手順（体調メモ / Vitalin）

説明文（description）・キーワード（keywords）・アプリ名（name）・サブタイトル（subtitle）・
リリースノート（release_notes）を **4言語** まとめて App Store Connect に反映するための
fastlane 設定です。プロモーションテキスト（promotional_text）は「なし」として空にしています。

- 対象アプリ: `com.azukid.AzBodyNote`（App ID `472914799`）
- 更新される項目: `description` / `keywords` / `name` / `subtitle` / `release_notes` /
  `promotional_text`（空＝クリア）
  （スクショ・価格・バイナリは触りません）

対応ロケール（App Store Connect のコード）:
`ja` / `en-US` / `ko` / `zh-Hant`

各テキストは `fastlane/metadata/<locale>/<項目>.txt` にあります。編集すればそのまま反映対象になります。

---

## 1. 準備（初回のみ）

### 1-1. fastlane（Homebrew 版）
この Mac では Homebrew 版 fastlane を使います（システム Ruby 2.6 は古く不可）。
`bundle exec` ではなく `fastlane <lane>` を直接呼びます。
```bash
brew install fastlane   # 未導入なら
which fastlane           # /opt/homebrew/bin/fastlane を確認
```

### 1-2. App Store Connect API キー（.p8）を発行
App Store Connect → **ユーザーとアクセス** → **統合（Integrations）** → **App Store Connect API**
→ **キーを生成**（ロールは `App Manager` 以上。Developer だと 403 になる）

発行時に以下を控える／保存する:
- **Key ID**（例: `ABC123DEFG`）
- **Issuer ID**（UUID）
- **AuthKey_XXXX.p8**（ダウンロードは1回だけ。再取得不可）

`.p8` は `fastlane/` 直下に置くと `.gitignore` 済みで安全です:
```bash
mv ~/Downloads/AuthKey_ABC123DEFG.p8 fastlane/
```

> ⚠️ `.p8` は秘密鍵です。Git にコミットしない・第三者に渡さないこと。

### 1-3. 認証情報を .env に設定
```bash
cp fastlane/.env.example fastlane/.env
# .env を開いて ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH を実際の値に書き換える
```
`.env` は `.gitignore` 済み。Condition ディレクトリ内で fastlane を実行すると自動で読み込まれます（export 不要）。

---

## 2. 実行

### 2-1. まず内容確認（送信しない）
```bash
cd /Users/sumpositive/GitLocal/Condition
fastlane preview_metadata
```
`Preview.html` が生成され、送信前に y/n 確認で止まります（force: false）。

### 2-2. 反映（審査には出さない）
```bash
fastlane upload_metadata
```
`submit_for_review: false` なので App Store Connect に**保存されるだけ**で、審査には出ません。
内容を確認してから、App Store Connect 上で手動で審査に出してください。

---

## 注意

- **release_notes は配信済み（Ready for Sale）バージョンだと編集ロックされ更新不可**。
  その場合は次バージョンを App Store Connect 側で用意してから反映する。
  description / keywords / name / subtitle は配信済みでも更新可。
- **keywords は上限 100 字**（カンマ区切り、スペースは字数節約のため原則省略）。
  現状の各言語は 100 字以内に収めてある。
- name は上限 30 字、subtitle も上限 30 字。
- promotional_text は空（＝クリア）。プロモーションを付けたくなったら各 `promotional_text.txt`
  に記入する（上限 170 字）。
