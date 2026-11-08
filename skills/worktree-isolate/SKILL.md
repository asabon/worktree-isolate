---
name: worktree-isolate
description: AI エージェントのセッションごとに git worktree を作成して作業環境を隔離し、セッション自動特定・PR作成・レビュー指摘対応・マージ後クリーンアップまでを支援するスキル。
---

# worktree-isolate Skill

このスキルは、メインリポジトリのワーキングツリーを汚さずに、セッション（タスク）ごとに独立した `git worktree` 環境を作成・再開・PR作成・クリーンアップするための一連の手順を定義します。
Antigravity 等の AI セッション ID（Conversation ID）と紐付けることで、セッション切り替え時にも迷わず自分の作業環境を自動特定できます。

## 適用タイミング
- ユーザーから機能追加、バグ修正、リファクタリングなどの作業を依頼されたとき
- 既存セッションを再開したとき（以前の worktree を自動特定）
- 既存の PR に対するレビュー指摘や追加修正を行うとき
- マージ済みの作業環境を整理（クリーンアップ）するとき

---

## 基本原則
1. **セッション開始時に作業環境を確認する**: 新規タスクか継続作業かを判定する。
2. **作業場所をユーザーと確認する**: 既存の worktree がなく、ファイル変更を伴う新規タスクを開始する際は、勝手に作らず「worktree を作成して隔離するか、メインツリーで直接作業するか」をユーザーに確認する。
3. **メインブランチで直接コードを変更しない（隔離時）**: worktree を利用する場合、リポジトリルート（`main`）のファイルは変更せず、隔離環境（`.worktrees/...`）で作業を行う。
4. **勝手にマージしない**: タスク完了時は PR 作成までを行い、ユーザーの確認を待つ。
5. **PR 作成後も worktree は保持する**: レビュー指摘に備えて作業ディレクトリは残し、ユーザーに PR URL とパスを通知する。
6. **マージ後にクリーンアップする**: 指摘対応が終わり、PR がマージされた後に環境を削除する。

---

## コアスクリプトの実行パス

本スキルに同梱されている実行スクリプト `wt.ps1` を使用します。環境に応じて以下のいずれかのパスで実行してください：

```powershell
# 1. グローバルスキルとしてインストールされている場合（標準）
$WT_CMD = "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1"

# 2. 本リポジトリの開発中にローカルから直接実行する場合
$WT_CMD = ".\skills\worktree-isolate\scripts\wt.ps1"
```

---

## ライフサイクルと実行手順

### 1. セッション開始時の環境確認とユーザー確認

セッションが開始されたら、まず現在のセッション ID（Conversation ID）に紐づく既存の作業ツリーがあるか確認します。

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" current -SessionId "<conversation-id>"
```

- **既存の worktree が見つかった場合**:
  出力されたパスへ移動し、作業をそのまま継続します。
- **見つからなかった場合**:
  - **ファイル変更を伴わない場合（調査・質問・検索など）**: メインツリーのままで回答します。
  - **コード・ファイルの変更を伴う場合**: ユーザーに以下のように確認します：
    > 「このタスクは専用の worktree を作成して作業環境を隔離しますか？それともメインツリーで直接作業しますか？」
    > （推奨: worktree を作成して隔離）

### 2. 新規隔離環境の作成（Create）

ユーザーが worktree 隔離を選択した場合、人間が見て分かりやすいブランチ名を命名し、`-SessionId` を指定して `create` を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" create -Branch "<type>/<descriptive-name>" -SessionId "<conversation-id>"
```
- 命名例: `feat/user-auth`, `fix/login-button-style`, `refactor/api-client`
- スクリプトは対象リポジトリ直下の `.worktrees/<sanitized-name>` に独立した作業ツリーを作成し、セッション ID と紐付けます。
- **重要**: 作成後、出力された worktree パスに移動（コマンド実行時の作業ディレクトリ変更）して作業を開始してください。

### 3. 作業実行

作成された worktree ディレクトリ内で通常通りファイル編集、テスト、コミットを行います。

```powershell
# worktree 内で作業・コミット
git add .
git commit -m "feat: implement user authentication flow"
```

### 4. PR 作成（作業完了の報告）

実装とテストが完了したら、PR を作成します。

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" pr -Title "<PRタイトル>" -Body "<PR概要・変更点>"
```
- リモートへのプッシュおよび GitHub PR の作成が行われます。
- **PR 作成後、worktree は削除されずに保持されます**。
- ユーザーへ「PRを作成しました（URL）」「レビュー指摘対応のために環境を保持しています」と報告してください。

### 5. レビュー指摘対応・セッション復帰（Resume）

既存のセッションまたは指定ブランチを再開する場合：

```powershell
# セッションIDから再開する場合
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" resume -SessionId "<conversation-id>"

# ブランチ名を直接指定して再開する場合
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" resume -Branch "<type>/<descriptive-name>"
```

### 6. クリーンアップ（マージ後の後片付け）

PR がマージされた後、不要になった worktree を削除します。

```powershell
# マージ済みの worktree を一括削除
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" cleanup -Merged

# または特定のブランチの worktree を個別削除
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" cleanup -Branch "<type>/<descriptive-name>"
```

### 7. 一覧確認

現在アクティブな worktree と、紐づくセッション、PR ステータス（Open / Merged）を確認したい場合：

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" list
```
