# Condition 開発方針

## Xcodeプロジェクト管理

- `Condition.xcodeproj` を正としてXcodeで直接管理する
- XcodeGenは使用しない
- `project.yml` は参照専用として扱う
- 明示的な依頼がない限り `xcodegen generate` を実行しない
- ファイル追加、ターゲット設定、Build Settings、Package DependenciesはXcodeプロジェクトへ直接反映する
