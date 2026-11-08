---
id: isolated-task
title: Isolated Task (git worktree)
phase: expand
lifecycle: any
kind: work
writes:
  - ".worktrees/**"
guards:
  - "git push origin main"
  - "git push origin master"
  - "git merge"
checks:
  - ${test}
  - ${lint}
exits:
  - to: isolated-task
    when: another task or review feedback needs to be worked on
  - to: cleanup-task
    when: the task PR is merged and the worktree is ready for cleanup
---

# Isolated Task (git worktree)

## Purpose

メインリポジトリのワーキングツリーを汚さずに、`git worktree` による専用の隔離環境（`.worktrees/<branch>`）でタスクを安全に実装・検証・PR作成まで行います。
vajra の Rails（フック）により、`.worktrees/**` 外（メインツリー）へのファイル編集は物理的にブロックされます。

## Steps

1. セッションに紐づく既存の作業環境があるか確認する。
   - `powershell -ExecutionPolicy Bypass -File "$WT" current -SessionId "<conversation-id>"`
2. 既存の専用環境がない場合、作業環境を作成する。
   - [human-gate] ユーザーに「専用の worktree を作成して作業環境を隔離しますか？」と確認する。
   - 承認後、ブランチ名を指定して作成：
     `powershell -ExecutionPolicy Bypass -File "$WT" create -Branch "<type>/<name>" -SessionId "<conversation-id>"`
3. 作成された `.worktrees/<branch>` ディレクトリに移動し、実装とテストを行う。
   - メインツリーのファイル変更は vajra のフックが拒絶するため、必ず worktree 内で作業する。
4. `${test}` と `${lint}` を実行して品質を確認する。
5. 作業完了後、Pull Request を作成する。
   - `powershell -ExecutionPolicy Bypass -File "$WT" pr -Title "<title>" -Body "<description>"`
   - PR 作成後もレビュー指摘対応に備えて worktree は保持する。

## Done when

- テストとリントが通過し、PR が作成され、ユーザーへ PR の URL と worktree パスが報告されていること。

## Reply with

- 作成した PR の URL、主な変更点、および「レビュー指摘対応のために環境を保持しています」という報告。
