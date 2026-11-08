---
name: prepare-release
description: Prepare a release for worktree-isolate. Analyzes commits and diffs since the last release tag, bumps version in package.json and skills/worktree-isolate/SKILL.md, updates CHANGELOG.md, creates a GitHub Draft Release, and opens a release PR.
---

# リリース準備スキル (`prepare-release`)

ユーザーから「リリースして」「リリース準備をして」「vX.Y.Z をリリースしたい」等の指示を受けた際に実行する手順です。
直前リリースタグからのコミット履歴・コード差分を解析してリリースノートを作成し、[`CHANGELOG.md`](../../../CHANGELOG.md) と GitHub Draft Release に反映した上で、リリース用 Pull Request を発行します。

---

## 📋 実行手順

### 1. リリース前の状態確認 & 差分解析・バージョン決定

1. **`main` ブランチの最新化を確認**:
   ```powershell
   git switch main
   git pull origin main
   ```

2. **直前タグからの差分解析**:
   ```powershell
   $prevTag = git describe --tags --abbrev=0 2>$null
   if ($prevTag) {
       git log "$prevTag..HEAD" --oneline
       git diff --stat "$prevTag..HEAD"
   } else {
       git log --oneline
       git diff --stat (git rev-list --max-parents=0 HEAD)..HEAD
   }
   ```

3. **バージョン情報の決定**:
   - ユーザーから明示的なバージョン（例: `0.2.0`）が指定されている場合はそれを使用。
   - 指定がない場合、セマンティックバージョニングに従い決定：
     - 新機能（`feat:`）がある場合: マイナーバージョン更新（例: `0.1.0` -> `0.2.0`）
     - バグ修正やドキュメントのみ（`fix:`, `chore:`, `docs:`）: パッチバージョン更新（例: `0.1.0` -> `0.1.1`）

4. **リリース用ブランチの作成**:
   ```powershell
   git switch -c "chore/release-vX.Y.Z"
   ```

---

### 2. ファイル更新 & リリースノート作成

1. **`package.json` の更新**:
   - `version` フィールドを決定したバージョン（例: `"0.2.0"`）に更新。

2. **`skills/worktree-isolate/SKILL.md` の更新**:
   - Frontmatter の `metadata.version` を新しいバージョンに更新。

3. **`CHANGELOG.md` の更新**:
   - 導入文の直下に `## [vX.Y.Z] - YYYY-MM-DD` セクションを追加。
   - `### 🚀 新機能 / Features` や `### 🐛 バグ修正・改善 / Bug Fixes & Improvements` 等のカテゴリ別に見やすく記載。

4. **GitHub Draft Release の作成**:
   - 今回分のリリースノートを一時ファイル（`scratch/release_notes.md`）に書き出す。
   - 既存のドラフトがあれば削除し、新しいドラフトを作成：
     ```powershell
     $draftIds = gh api repos/:owner/:repo/releases --jq '.[] | select(.draft == true) | .id'
     foreach ($id in $draftIds) {
         if ($id) { gh api -X DELETE "repos/:owner/:repo/releases/$id" }
     }
     gh release create "vX.Y.Z" --draft --title "vX.Y.Z" --notes-file "scratch/release_notes.md"
     Remove-Item "scratch/release_notes.md" -Force
     ```

5. **コミット & PR 作成**:
   ```powershell
   git add package.json skills/worktree-isolate/SKILL.md CHANGELOG.md
   git commit -m "chore: release vX.Y.Z"
   git push -u origin "chore/release-vX.Y.Z"
   gh pr create --title "chore: release vX.Y.Z" --body "Release vX.Y.Z preparation."
   ```

6. **ユーザーへの報告**:
   - 作成した PR の URL と、GitHub Draft Release の状態をユーザーに報告します。

