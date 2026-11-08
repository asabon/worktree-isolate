# Changelog

すべての注目すべき変更はこのファイルに記録されます。
フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に基づき、
バージョン管理は [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

---

## [v0.1.0] - 2026-11-08

### 🚀 新機能 / Features
- **セッションごとの Git Worktree 隔離**: AI エージェントの作業環境をメインブランチから隔離し、リポジトリ直下の `.worktrees/<branch-name>` 配下で安全に並行作業を行う仕組みを実装。
- **セッション自動追跡**: AI の Conversation ID と worktree を紐付け管理（`.worktrees/.sessions.json`）。セッション切り替え時でも `current` コマンドで作業環境を即座に自動特定。
- **レビュー指摘対応 (Resume)**: PR 作成後も worktree 環境を保持し、指摘が入った際は `resume` で即座に修正作業を再開可能。
- **安全なクリーンアップ**: PR マージ後にマージ済みの環境を一括削除する `cleanup -Merged` を提供。
- **作業前確認フロー**: 新規タスク開始時、エージェントが勝手に作業せず、ユーザーに「worktree を作成して隔離するか、メインツリーで作業するか」を確認するガイドラインを整備。
- **グローバルデプロイ機能 (`deploy.ps1`)**: スキル本体を Antigravity のグローバルスキル領域（`~/.gemini/config/skills/worktree-isolate`）にデプロイし、PC 内の全プロジェクトから利用可能にするスクリプトを提供。

