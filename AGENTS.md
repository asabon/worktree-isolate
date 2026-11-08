# AGENTS.md

このリポジトリで作業するすべての AI エージェントは、以下のルールに従ってください。

## ⚠️ ブランチ保護と作業原則（厳守）

- **`main` ブランチへの直接 push は禁止**されています（ブランチ保護されています）。
- **AI による勝手な `main` へのマージは禁止**です。すべてのコード変更はトピックブランチで作業し、**Pull Request（PR）を作成するところまで**を担当してください。
- PR のレビュー、承認、および `main` へのマージ操作は必ず**ユーザー自身が行います**。

---

## ワークフローのルール

1. **作業環境の確認と選択**:
   - セッション開始時はまず `powershell -ExecutionPolicy Bypass -File .\skills\worktree-isolate\scripts\wt.ps1 current -SessionId "<conversation-id>"` を実行し、既存の専用環境があるか確認してください。
   - **既存の専用環境がある場合**: その worktree パス内で作業を継続してください。
   - **既存の環境がない場合**:
     - 調査・質問対応など**ファイル変更を伴わないタスク**は、そのままメインツリーで実施してください。
     - 機能追加・修正など**コードやファイルの変更を伴うタスク**を開始する際は、勝手に作成せず、ユーザーに「専用の worktree を作成して作業環境を隔離しますか？それともメインツリーで作業しますか？」と確認してください。

2. **Worktree の作成**:
   - ユーザーが worktree での隔離を選択した場合、分かりやすいブランチ名を提案して `powershell -ExecutionPolicy Bypass -File .\skills\worktree-isolate\scripts\wt.ps1 create -Branch "<type>/<name>" -SessionId "<conversation-id>"` を実行し、その中で作業してください。

3. **レビュー指摘対応・作業再開**:
   - 既存のブランチや PR に対する修正作業を行う際は、`powershell -ExecutionPolicy Bypass -File .\skills\worktree-isolate\scripts\wt.ps1 resume -SessionId "<conversation-id>"` または `-Branch "<branch-name>"` で環境を再開してください。

4. **PR 作成と保持**:
   - 作業完了時は `powershell -ExecutionPolicy Bypass -File .\skills\worktree-isolate\scripts\wt.ps1 pr` を用いて Pull Request を作成してください。
   - PR 作成後も、ユーザーのレビューや指摘対応に備えて worktree は保持してください。
   - ユーザーへ PR の URL と概要を報告し、ユーザーによるレビュー・マージを待ってください。

5. **クリーンアップ**:
   - ユーザーから明示的に指示があった場合、または PR がユーザーによってマージされたことを確認した後に `powershell -ExecutionPolicy Bypass -File .\skills\worktree-isolate\scripts\wt.ps1 cleanup` を実行して環境を片付けてください。
