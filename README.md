# worktree-isolate

AI エージェントのセッションごとに `git worktree` を用いて作業環境を安全に隔離し、レビュー指摘への迅速な対応やマージ後のクリーンアップまでを支援する Skill です。

> [!NOTE]
> **現在の対応環境**: 本バージョンは **Windows + Google Antigravity** に最適化されています。（macOS/Linux や Claude Code 等への対応は順次拡張予定です）

## 対応環境・前提条件

- **OS**: Windows (PowerShell 5.1 / PowerShell 7+)
- **AI ツール**: Google Antigravity (Antigravity IDE / Antigravity 2.0)
- **必要なツール**: 
  - Git
  - GitHub CLI (`gh`) ※PR 自動作成機能を利用する場合

## 特徴

- **スキル単体で自己完結**: コアスクリプト（`wt.ps1`）をスキルフォルダ内に内包しているため、他プロジェクトやグローバル環境への持ち運びが容易。
- **グローバルデプロイ対応**: `deploy.ps1` により、PC 内のすべてのプロジェクトで Antigravity エージェントが本スキルを利用可能。
- **安全な隔離**: リポジトリ直下の `.worktrees/<branch-name>`（`.gitignore` 対象）に worktree を作成するため、Antigravity のワークスペーススコープ内で安全に動作。
- **セッション自動追跡**: AI の Conversation ID と worktree を紐付け管理。セッション切り替え時でも自分の環境を即座に自動特定（`current` / `resume`）。
- **レビュー指摘への対応 (Resume)**: PR 作成後も環境を保持し、指摘が入った際は即座にその環境で作業を再開可能。
- **安全なクリーンアップ**: PR がマージされた後にマージ済みの環境を一括削除（`cleanup -Merged`）。

## ディレクトリ構成

```text
e:\work\worktree-isolate\               # 【スキル開発リポジトリ】
├── .gitignore                          # "/.worktrees/" を除外設定
├── AGENTS.md                           # 本リポジトリ開発用エージェント指示書
├── README.md                           # 本ドキュメント
├── scripts\
│   └── deploy.ps1                      # Antigravity グローバルスキルへのデプロイスクリプト
└── skills\
    └── worktree-isolate\               # 【配布・デプロイされるスキル本体】
        ├── SKILL.md                    # Antigravity 用 Skill 定義
        └── scripts\
            └── wt.ps1                  # コア実行スクリプト（セッション追跡・worktree操作）
```

---

## グローバルスキルへのデプロイ方法

本スキルを Antigravity のグローバルスキル領域（`~/.gemini/config/skills/worktree-isolate`）に配置することで、PC 上の **すべての Git リポジトリ** でエージェントが本スキルを使えるようになります。

```powershell
# 1. 最新のコミット状態をデプロイ
.\scripts\deploy.ps1

# 2. 開発中の未コミット変更（WIP）も含めて即座に反映・検証したい場合
.\scripts\deploy.ps1 -Wip

# 3. デプロイ状態（バージョン、コミットハッシュ、日時）を確認
.\scripts\deploy.ps1 -Status

# 4. シミュレーション（Dry-run）
.\scripts\deploy.ps1 -DryRun
```

---

## ワークフローと使い方

### ワークフローの概要

1. **環境確認**: セッション開始時に `current -SessionId <id>` で既存環境の有無を確認。
2. **作業場所の選択**: 既存環境がなくコード変更を伴う場合は、ユーザーに worktree 隔離かメインツリー作業かを確認。
3. **作業とPR**: worktree 内で作業し、完了時に `pr` で PR 作成（worktree は保持）。
4. **お掃除**: PR マージ後に `cleanup -Merged` で安全に一括削除。

### スクリプトのコマンド一覧

グローバルインストール後のスクリプトパス:  
`$WT = "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1"`

```powershell
# 1. セッションに紐づく作業ツリーの確認
powershell -File $WT current -SessionId "<conversation-id>"

# 2. 新しい作業環境を作成（セッションID紐付け）
powershell -File $WT create -Branch "feat/my-new-feature" -SessionId "<conversation-id>"

# 3. 現在の Worktree 一覧を表示
powershell -File $WT list

# 4. 作業再開（レビュー指摘対応など）
powershell -File $WT resume -SessionId "<conversation-id>"
# または
powershell -File $WT resume -Branch "feat/my-new-feature"

# 5. PR 作成（GitHub CLI 連携）※ worktree ディレクトリ内で実行
powershell -File $WT pr -Title "feat: add my new feature" -Body "詳細な説明"

# 6. クリーンアップ
powershell -File $WT cleanup -Merged
# または個別削除
powershell -File $WT cleanup -Branch "feat/my-new-feature"
```

## 今後の拡張予定
- macOS / Linux 向けの Bash スクリプト（`scripts/wt.sh`）の追加
- Claude Code / Cursor などの他エージェント向けプリセット設定
