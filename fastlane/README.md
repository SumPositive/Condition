fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios preview_metadata

```sh
[bundle exec] fastlane ios preview_metadata
```

テキストメタデータの差分を確認する（force: false なので送信前に Preview.html で確認して停止）

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

テキストメタデータを App Store Connect に反映する（審査提出はしない）

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

シミュレータでスクショを撮影する（Snapfile の言語・デバイスに従う。アップロードはしない）

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

既存の ./fastlane/screenshots をそのまま App Store Connect に反映する（撮影はしない・審査提出はしない）

### ios screenshots_and_upload

```sh
[bundle exec] fastlane ios screenshots_and_upload
```

撮影 → アップロードを一気に行う（審査提出はしない）

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
