# Agent instructions / エージェント運用指示

## 日本語

このリポジトリは SwitchBot 設定取得ツール「sbview」の開発・管理に使用する。

### GitHub 運用
- 保存先は公開リポジトリ `miriorg/sbView`、通常の反映先は `main` とする。
- このプロジェクトでソースコード、設定、ドキュメントなどを変更した際は、変更内容を確認し、適切な作業単位でコミットする。
- コミットメッセージは AI エージェントが変更内容に応じて日本語で作成する。
- コミット後は、利用可能な GitHub 操作機能を用いて同じ作業の中でリモートへプッシュする。GitHub API で直接コミットする場合は、その操作自体がリモートへの反映となる。
- コミットおよびリモート反映の成否と、可能ならコミット SHA を利用者に報告する。
- ユーザーが別のブランチやワークフローを明示した場合は、その指示を優先する。
- 認証情報、API トークン、秘密鍵、個人情報などの機密情報を公開リポジトリにコミットしない。公開前に差分を確認する。
- ツールや権限の制約で反映できない場合は、成功したと主張せず、未反映の状態と理由を報告する。
- このファイルは、チャットの長期記憶に依存せず、後続のエージェントが運用方針を参照できるように維持する。

### ドキュメント
- 原則として日本語で記述する。
- README、プルリクエストの説明など、GitHub 上の対外的な文書は日本語の後に同内容の英語を併記する。

## English

This repository is used to develop and maintain the SwitchBot configuration retrieval tool, "sbview".

### GitHub workflow
- Use the public repository `miriorg/sbView`; normally apply changes to `main`.
- After modifying source code, configuration, or documentation, review the changes and commit them in logical units.
- The AI agent writes descriptive commit messages in Japanese.
- Push commits to the remote in the same work session using available GitHub capabilities. A direct commit via the GitHub API already updates the remote.
- Report whether the commit and remote update succeeded, including the commit SHA when available.
- Follow explicit user instructions when a different branch or workflow is requested.
- Never commit secrets, API tokens, private keys, or personal information to this public repository. Review changes before publishing.
- If tools or permissions prevent an update, report the failure accurately rather than claiming success.
- Maintain this file as durable project instructions independent of chat memory.

### Documentation
- Write primarily in Japanese.
- For outward-facing GitHub documents, including README files and pull request descriptions, include an English equivalent after the Japanese text.
