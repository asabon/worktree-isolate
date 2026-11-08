---
name: publish-release
description: Publish a release for worktree-isolate. Tags main branch, publishes the GitHub Release, and automatically deploys the released version to Antigravity global skills directory.
---

# リリース公開スキル (`publish-release`)

ユーザーから「リリース PR をマージしました」「公開してください」と指示された際に実行する手順です。
リリースタグを作成・push し、GitHub Release を公開し、Antigravity のグローバルスキル領域へ最新のリリース版を自動デプロイします。

---

## 📋 実行手順

### 1. `main` ブランチの最新化 & トピックブランチの整理

```powershell
git switch main
git pull origin main
git fetch --prune
# 不要になったリリースブランチがあれば削除
git branch -D chore/release-vX.Y.Z 2>$null
```

---

### 2. リリースタグの作成 & push

1. `package.json` からバージョン番号を取得：
   ```powershell
   $version = (Get-Content package.json -Raw | ConvertFrom-Json).version
   $tag = "v$version"
   ```

2. タグを作成してリモートへ push：
   ```powershell
   git tag $tag
   git push origin $tag
   ```

---

### 3. GitHub Release の公開

Draft Release を正式な Release として公開に切り替えます：

```powershell
# Draft Release の ID を取得して公開フラグを更新
$releaseId = gh api repos/:owner/:repo/releases --jq ".[] | select(.tag_name == '$tag') | .id"
if ($releaseId) {
    gh api -X PATCH "repos/:owner/:repo/releases/$releaseId" -f draft=false
    Write-Host "Published GitHub Release $tag successfully!" -ForegroundColor Green
} else {
    # ドラフトが見つからない場合は直接作成
    gh release create $tag --title $tag --notes "Release $tag"
}
```

---

### 4. グローバルスキル領域への最新版デプロイ

リリースされた正式なバージョンを、PC 全体の Antigravity グローバルスキル領域へデプロイします：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
```

- デプロイ結果のステータスを確認：
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 -Status
  ```

---

### 5. 完了報告

ユーザーへ以下を報告します：
- リリースタグ: `vX.Y.Z`
- GitHub Release URL: `https://github.com/:owner/:repo/releases/tag/vX.Y.Z`
- グローバルスキルへの最新版デプロイ完了の旨

