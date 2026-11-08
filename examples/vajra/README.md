# vajra × worktree-isolate 連携ガイド

**「お願い（散文ルール）」から「絶対に曲がらないレール（Rails）」へ。**

`vajra` のワークフロー管理・ライフサイクルフックと `worktree-isolate` を組み合わせることで、**AI エージェントがメインブランチを誤って直接編集することを物理的に遮断（PreToolUse deny）し、git worktree による安全な隔離作業を強制** できます。

---

## 連携の仕組み

```mermaid
flowchart TD
    User(["ユーザーの依頼<br/>「この機能を追加して」"]) --> Agent["AI エージェント"]

    subgraph Rails ["⚡ vajra（Rails / ガードエンジン）"]
        Hook[".agents/hooks.json<br/>PreToolUse フック"]
        PB["Playbook: isolated-task<br/>writes: ['.worktrees/**']"]
    end

    subgraph WT ["🌿 worktree-isolate（隔離実行エンジン）"]
        Script["wt.ps1<br/>create / resume / pr / cleanup"]
        Env[".worktrees/feat-xxx/<br/>専用作業ツリー"]
    end

    Agent -- "1. メインツリーを編集しようとする" --> Hook
    Hook -- "❌ Blocked: writes は .worktrees/** のみ許可" --> Agent
    Agent -- "2. wt.ps1 create を実行" --> Script
    Script --> Env
    Agent -- "3. .worktrees/ 内で作業" --> Env
    Hook -- "✅ Allowed: 隔離環境内の編集は許可" --> Agent
```

1. **メインツリー直接編集のブロック**:
   - Playbook の `writes: [".worktrees/**"]` 定義により、AI がメインツリーのファイルを `edit_file` / `write_file` しようとすると、vajra の `PreToolUse` フックが即座に拒絶（`{ decision: "deny" }`）します。
2. **安全な隔離環境への誘導**:
   - 拒絶されたエージェントは、`worktree-isolate` の `wt.ps1 create` を呼び出して専用の Worktree を作成し、その中で安全に作業を進めます。
3. **不可逆コマンドの防止**:
   - `guards: ["git push origin main", "git merge"]` により、メインブランチへの直接 push や不正なマージをフックで未然に防ぎます。

---

## 導入手順

### 1. グローバルスキルの準備
`vajra` と `worktree-isolate` の両方を Antigravity のグローバルスキルに配置します：

```powershell
# worktree-isolate のデプロイ
cd /path/to/worktree-isolate
.\scripts\deploy.ps1

# vajra のデプロイ
cd /path/to/vajra
.\scripts\deploy.ps1
```

### 2. プロジェクトへの Playbook の配置
対象プロジェクトの vajra ワークフローディレクトリ（例: `.agents/skills/your-flow/playbooks/`）に、本ディレクトリの Playbook を配置します：
- `isolated-task.md`: 隔離作業用プレイブック
- `cleanup-task.md`: マージ後クリーンアップ用プレイブック

### 3. フックのインストール
対象プロジェクトのルートで以下を実行し、Antigravity フック（`.agents/hooks.json`）を生成します：

```bash
node <your-flow>/scripts/flow.mjs install --harness antigravity
```

これで、対象プロジェクトにおけるエージェントの作業環境が自動的にレールで保護されます。
