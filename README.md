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

## 設定テンプレート

[.sbview.conf.sample](.sbview.conf.sample) は、`sbview.ps1` の設定項目に対応した、認証情報を含まないテンプレートです。`sbview.ps1` は `main` に公開済みです。

1. テンプレートを `.sbview.conf` という名前でリポジトリのルートまたはリポジトリ外へコピーし、UTF-8 のまま保存します。リポジトリ内の `.sbview.conf` はローカル実行・テスト専用で、Git の追跡対象外です。
2. 変更する設定の行頭から `# ` を外し、`KEY=VALUE` 形式で指定します。コメントのままの項目は設定を上書きしません。
3. 認証情報は環境変数に入れ、設定ファイルの `TOKEN_ENV` と `SECRET_ENV` に環境変数名を指定します。例として `TOKEN_ENV=SWITCHBOT_TOKEN` と `SECRET_ENV=SWITCHBOT_SECRET` を使えます。設定ファイルの `TOKEN` と `SECRET` はコメントのままにします。
4. 必要に応じて `-ConfigPath` で設定ファイルのパスを指定して実行します。`-ShowConfig` を併用すると、API に接続せずに適用された設定を確認できます。

実際のトークンやシークレットを含む `.sbview.conf` はコミットしないでください。公開前には必ずステージ済みの差分を確認してください。

## 実装・検証状況

- 初期実装の `sbview.ps1` は `main` に反映済みです。
- PowerShell 7 での構文確認と `-ShowConfig` の起動確認は完了しています。
- SwitchBot API を使用した取得処理と各出力形式の検証は進行中です。
- `PARALLEL` は設定として受け付けますが、現在の実装は警告を記録して逐次実行します。

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

## Configuration template

[.sbview.conf.sample](.sbview.conf.sample) is a credential-free template matching the settings supported by `sbview.ps1`. The script has been published on `main`.

1. Copy the template as `.sbview.conf` either to the repository root or outside the repository, keeping it encoded in UTF-8. A `.sbview.conf` file inside the repository is for local execution and testing only and is excluded from Git tracking.
2. Remove the leading `# ` from each setting you want to change and use `KEY=VALUE` syntax. Commented settings leave the effective configuration intact.
3. Set credentials in environment variables and specify their names in `TOKEN_ENV` and `SECRET_ENV`. For example, use `TOKEN_ENV=SWITCHBOT_TOKEN` and `SECRET_ENV=SWITCHBOT_SECRET`. Leave `TOKEN` and `SECRET` commented out in the configuration file.
4. If necessary, run the script with `-ConfigPath` pointing to the configuration file. Add `-ShowConfig` to inspect the effective settings without contacting the API.

Never commit a `.sbview.conf` file containing an actual token or secret. Always inspect staged changes before publishing them.

## Implementation and validation status

- The initial `sbview.ps1` implementation is available on `main`.
- PowerShell 7 syntax validation and the `-ShowConfig` startup check have passed.
- Validation of SwitchBot API retrieval and each output format is in progress.
- `PARALLEL` is accepted as a setting, but the current implementation records a warning and runs requests sequentially.

## Development and updates

Keep this README synchronized with agreed specifications and implementation progress. See [AGENTS.md](AGENTS.md) for commit and remote-update conventions.
