# sbView

SwitchBot のデバイス設定・状態情報を取得し、保存するためのツールです。

> 開発中。本書の「確定済み仕様」は設計上の合意事項であり、実装済み・動作確認済みを意味しません。

## 確定済み仕様（一部）

以下はこれまでに確定した項目のうち、確認できる範囲の記録です。

- 出力先は `-OutputPath` を基準に決定する。
- 未知の属性も動的に出力する。
- 個別デバイスの取得に失敗した場合も、デバイス情報を保持し、失敗をメタ情報とログに記録する。
- 比較機能は実装しない。
- 存在しないデバイス ID は警告を記録し、処理を継続する。
- 設定ファイルの未知のキーや不正な値はエラーとして終了する。
- タイムアウトの既定値は15秒とし、設定ファイルおよびコマンドラインから変更可能とする。
- 出力にスキーマバージョンを付与する。
- XML の不正な要素名は安全な名前に変換し、元の名前も保持する。
- XML は整形して出力する。
- `-ShowConfig` オプションを用意し、人間が読みやすいテキスト形式で設定を表示する。
- エラーは種別ごとに分類する。

これ以外の仕様についても、確定内容を確認でき次第、追記します。

## 開発・更新方針

確定した仕様と実装の進捗に応じて README を更新します。コミットとリモート反映の運用は [AGENTS.md](AGENTS.md) を参照してください。

---

# English

sbView is a tool for retrieving and saving SwitchBot device configuration and status information.

> Under development. The agreed specifications below describe design decisions, not necessarily implemented or verified features.

## Agreed specifications (partial)

The following decisions have been confirmed from the available project context:

- Resolve output locations relative to `-OutputPath`.
- Dynamically include unknown attributes in output.
- Preserve device information when an individual device retrieval fails, recording the failure in metadata and logs.
- Do not implement a comparison feature.
- Warn about nonexistent device IDs and continue processing.
- Terminate with an error for unknown configuration keys or invalid values.
- Default to a 15-second timeout, configurable via the configuration file or command line.
- Include a schema version in output.
- Convert invalid XML element names into safe names while preserving their original names.
- Produce formatted XML.
- Provide `-ShowConfig` to display configuration in human-readable text.
- Classify errors by type.

Additional agreed specifications will be documented as they are verified.

## Development and updates

Keep this README synchronized with agreed specifications and implementation progress. See [AGENTS.md](AGENTS.md) for commit and remote-update conventions.
