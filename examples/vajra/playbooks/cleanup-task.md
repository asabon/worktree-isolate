---
id: cleanup-task
title: Cleanup Isolated Environment
phase: extract
lifecycle: any
kind: gate
promotes: any
checks: []
irreversible:
  - "powershell -ExecutionPolicy Bypass -File \"$WT\" cleanup -Merged"
exits:
  - to: isolated-task
    when: cleanup is completed and ready for the next task
---

# Cleanup Isolated Environment

## Purpose

PR がマージされた後に、不要になった `.worktrees/<branch>` 環境を安全に一括クリーンアップします。

## Steps

1. 対象 PR が `main` / `master` にマージ済みであることを確認する。
   - `gh pr view <number> --json state` または `powershell -File "$WT" list`
2. [human-gate] ユーザーに「マージ済みの worktree 環境をクリーンアップしますか？」と確認する。
3. [irreversible] 承認後、マージ済み環境を一括削除する：
   - `powershell -ExecutionPolicy Bypass -File "$WT" cleanup -Merged`

## Done when

- マージ済みの worktree ディレクトリおよびセッション紐付けが正常に削除されていること。

## Reply with

- クリーンアップ完了の報告と、削除されたブランチ／ディレクトリの一覧。
