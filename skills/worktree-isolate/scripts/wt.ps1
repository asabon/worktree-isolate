<#
.SYNOPSIS
    git worktree を用いた環境隔離支援スクリプト (worktree-isolate)

.DESCRIPTION
    AI エージェントや開発者がセッションごとに独立した git worktree を作成・管理・再開・PR作成・クリーンアップするためのスクリプトです。
    Antigravity 等の AI セッション ID (Conversation ID) との自動紐付けに対応しています。

.EXAMPLE
    powershell -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" create -Branch "feat/login-flow" -SessionId "d2c398e9-..."
    powershell -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" current -SessionId "d2c398e9-..."
    powershell -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" list
    powershell -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" resume -SessionId "d2c398e9-..."
    powershell -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" pr -Title "Add login flow" -Body "Implements authentication"
    powershell -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" cleanup -Branch "feat/login-flow"
    powershell -File "$HOME\.gemini\config\skills\worktree-isolate\scripts\wt.ps1" cleanup -Merged
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("create", "list", "resume", "pr", "cleanup", "current")]
    [string]$Action,

    [Parameter(Position = 1)]
    [string]$Branch,

    [string]$SessionId,
    [string]$Base = "main",
    [string]$Title,
    [string]$Body,
    [switch]$Draft,
    [switch]$Merged,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-Path([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    return [System.IO.Path]::GetFullPath($p).TrimEnd('\', '/')
}

function Get-RepoRoot {
    $root = git rev-parse --show-toplevel 2>$null
    if (-not $root) {
        throw "Not inside a Git repository."
    }
    return Normalize-Path $root.Trim()
}

function Get-WorktreeBaseDir([string]$repoRoot) {
    return Join-Path $repoRoot ".worktrees"
}

function Ensure-GitIgnore([string]$repoRoot) {
    $gitignorePath = Join-Path $repoRoot ".gitignore"
    $entry = "/.worktrees/"

    if (Test-Path $gitignorePath) {
        $content = Get-Content $gitignorePath -Raw
        if ($content -notmatch '(?m)^\s*(\/)?\.worktrees(\/)?\s*$') {
            Add-Content -Path $gitignorePath -Value "`n# Worktree isolate directories`n$entry"
            Write-Host "Added '$entry' to .gitignore." -ForegroundColor DarkGray
        }
    } else {
        Set-Content -Path $gitignorePath -Value "# Worktree isolate directories`n$entry`n"
        Write-Host "Created .gitignore with '$entry'." -ForegroundColor DarkGray
    }
}

function Sanitize-BranchName([string]$branchName) {
    return ($branchName -replace '[\\/:\*\?"<>\|]', '-')
}

function Get-WorktreePath([string]$repoRoot, [string]$branchName) {
    $wtBase = Get-WorktreeBaseDir -repoRoot $repoRoot
    $safeName = Sanitize-BranchName -branchName $branchName
    return Join-Path $wtBase $safeName
}

# --- Session Store Management ---

function Get-SessionStorePath([string]$repoRoot) {
    $wtBase = Get-WorktreeBaseDir -repoRoot $repoRoot
    return Join-Path $wtBase ".sessions.json"
}

function Get-SessionStore([string]$repoRoot) {
    $path = Get-SessionStorePath -repoRoot $repoRoot
    if (Test-Path $path) {
        try {
            $json = Get-Content $path -Raw | ConvertFrom-Json
            $dict = @{}
            foreach ($prop in $json.PSObject.Properties) {
                $dict[$prop.Name] = $prop.Value
            }
            return $dict
        } catch {
            return @{}
        }
    }
    return @{}
}

function Save-SessionStore([string]$repoRoot, [hashtable]$store) {
    $path = Get-SessionStorePath -repoRoot $repoRoot
    $wtBase = Get-WorktreeBaseDir -repoRoot $repoRoot
    if (-not (Test-Path $wtBase)) {
        New-Item -ItemType Directory -Path $wtBase -Force | Out-Null
    }
    $store | ConvertTo-Json -Depth 5 | Set-Content $path -Encoding UTF8
}

function Register-Session([string]$repoRoot, [string]$sessionId, [string]$branch, [string]$worktreePath) {
    if (-not $sessionId) { return }
    $store = Get-SessionStore -repoRoot $repoRoot
    $store[$sessionId] = [PSCustomObject]@{
        branch       = $branch
        worktreePath = Normalize-Path $worktreePath
        updatedAt    = (Get-Date).ToString("o")
    }
    Save-SessionStore -repoRoot $repoRoot -store $store
    Write-Host "Linked session '$sessionId' to branch '$branch'." -ForegroundColor DarkGray
}

function Unregister-Session([string]$repoRoot, [string]$targetBranchOrPath) {
    $store = Get-SessionStore -repoRoot $repoRoot
    if ($store.Count -eq 0) { return }

    $targetNorm = Normalize-Path $targetBranchOrPath
    $keysToRemove = @()

    foreach ($k in $store.Keys) {
        $entry = $store[$k]
        if ($entry.branch -eq $targetBranchOrPath -or (Normalize-Path $entry.worktreePath) -eq $targetNorm) {
            $keysToRemove += $k
        }
    }

    foreach ($k in $keysToRemove) {
        $store.Remove($k)
    }

    if ($keysToRemove.Count -gt 0) {
        Save-SessionStore -repoRoot $repoRoot -store $store
    }
}

function Get-AllWorktrees {
    $raw = git worktree list --porcelain
    $trees = @()
    $current = @{}

    foreach ($line in ($raw -split "`n")) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.ContainsKey("worktree")) {
                $trees += [PSCustomObject]$current
                $current = @{}
            }
            continue
        }

        if ($line -match '^worktree (.+)$') {
            $current["worktree"] = $Matches[1]
        } elseif ($line -match '^HEAD (.+)$') {
            $current["HEAD"] = $Matches[1]
        } elseif ($line -match '^branch refs/heads/(.+)$') {
            $current["branch"] = $Matches[1]
        } elseif ($line -eq 'bare') {
            $current["bare"] = $true
        } elseif ($line -eq 'detached') {
            $current["detached"] = $true
        }
    }
    if ($current.ContainsKey("worktree")) {
        $trees += [PSCustomObject]$current
    }
    return $trees
}

# --- Actions ---

function Invoke-Current {
    if (-not $SessionId) {
        throw "SessionId is required for 'current'. Example: wt.ps1 current -SessionId <id>"
    }

    $repoRoot = Get-RepoRoot
    $store = Get-SessionStore -repoRoot $repoRoot

    if ($store.ContainsKey($SessionId)) {
        $session = $store[$SessionId]
        $wtPath = $session.worktreePath

        if (Test-Path $wtPath) {
            Write-Host "Active worktree found for session '$SessionId':" -ForegroundColor Green
            Write-Host "Branch: $($session.branch)" -ForegroundColor Yellow
            Write-Host "Path:   $wtPath" -ForegroundColor Yellow
            Write-Host "`n[Next Step for Agent]:" -ForegroundColor Cyan
            Write-Host "cd `"$wtPath`""
            return
        } else {
            Write-Warning "Registered worktree path not found on disk: $wtPath"
        }
    }

    Write-Host "No active worktree linked to session '$SessionId'." -ForegroundColor Yellow
}

function Invoke-Create {
    if (-not $Branch) {
        throw "Branch name is required for 'create'. Example: wt.ps1 create -Branch feat/sample"
    }

    $repoRoot = Get-RepoRoot
    $targetPath = Get-WorktreePath -repoRoot $repoRoot -branchName $Branch

    if (Test-Path $targetPath) {
        throw "Target directory already exists: $targetPath. Use 'resume' or choose another branch name."
    }

    # 親ディレクトリの作成と .gitignore 確認
    $wtBase = Get-WorktreeBaseDir -repoRoot $repoRoot
    if (-not (Test-Path $wtBase)) {
        New-Item -ItemType Directory -Path $wtBase -Force | Out-Null
    }
    Ensure-GitIgnore -repoRoot $repoRoot

    Write-Host "Creating worktree for branch '$Branch' from base '$Base'..." -ForegroundColor Cyan

    $branchExists = (git branch --list $Branch) -or (git branch -r --list "origin/$Branch")

    if ($branchExists) {
        git worktree add $targetPath $Branch
    } else {
        git worktree add -b $Branch $targetPath $Base
    }

    # 環境設定ファイルのコピー
    $envFiles = @(".env", ".env.local", ".env.development")
    foreach ($envFile in $envFiles) {
        $srcPath = Join-Path $repoRoot $envFile
        if (Test-Path $srcPath) {
            Copy-Item -Path $srcPath -Destination (Join-Path $targetPath $envFile)
            Write-Host "Copied $envFile to worktree." -ForegroundColor DarkGray
        }
    }

    # セッションIDの記録
    if ($SessionId) {
        Register-Session -repoRoot $repoRoot -sessionId $SessionId -branch $Branch -worktreePath $targetPath
    }

    Write-Host "`nWorktree ready at:" -ForegroundColor Green
    Write-Host $targetPath -ForegroundColor Yellow
    Write-Host "`n[Next Step for Agent/User]:" -ForegroundColor Cyan
    Write-Host "cd `"$targetPath`""
}

function Invoke-List {
    $trees = Get-AllWorktrees
    $repoRoot = Get-RepoRoot
    $store = Get-SessionStore -repoRoot $repoRoot

    Write-Host "`nActive Git Worktrees:" -ForegroundColor Cyan
    Write-Host ("-" * 80) -ForegroundColor Gray

    $hasGh = (Get-Command gh -ErrorAction SilentlyContinue) -ne $null

    foreach ($tree in $trees) {
        $treePath = Normalize-Path $tree.worktree
        $isMain = ($treePath -eq $repoRoot)
        $badge = if ($isMain) { "[MAIN]" } else { "[WORKTREE]" }
        $branchName = if ($tree.branch) { $tree.branch } else { "(detached)" }

        # セッション紐付けの確認
        $linkedSessions = @()
        foreach ($sId in $store.Keys) {
            if ((Normalize-Path $store[$sId].worktreePath) -eq $treePath) {
                $linkedSessions += ($sId.Substring(0, [Math]::Min(8, $sId.Length)) + "...")
            }
        }
        $sessionStr = if ($linkedSessions.Count -gt 0) { " (Sessions: $($linkedSessions -join ', '))" } else { "" }

        $prStatus = ""
        if ($hasGh -and $tree.branch -and -not $isMain) {
            try {
                $prInfo = gh pr view $tree.branch --json state,number,url 2>$null | ConvertFrom-Json
                if ($prInfo) {
                    $prStatus = " | PR #${($prInfo.number)}: $($prInfo.state)"
                }
            } catch {}
        }

        Write-Host ("{0,-10} {1,-25} {2}{3}{4}" -f $badge, $branchName, $tree.worktree, $sessionStr, $prStatus)
    }
    Write-Host ("-" * 80) -ForegroundColor Gray
}

function Invoke-Resume {
    $repoRoot = Get-RepoRoot

    # Branch が指定されておらず、SessionId が指定されている場合はセッション情報から復元
    if (-not $Branch -and $SessionId) {
        $store = Get-SessionStore -repoRoot $repoRoot
        if ($store.ContainsKey($SessionId)) {
            $Branch = $store[$SessionId].branch
            Write-Host "Resolved branch '$Branch' from SessionId '$SessionId'." -ForegroundColor DarkGray
        } else {
            throw "No worktree associated with session '$SessionId'. Please specify -Branch."
        }
    }

    if (-not $Branch) {
        throw "Branch name or SessionId is required for 'resume'. Example: wt.ps1 resume -Branch feat/sample"
    }

    $trees = Get-AllWorktrees
    $found = $trees | Where-Object { $_.branch -eq $Branch }

    if ($found) {
        if ($SessionId) {
            Register-Session -repoRoot $repoRoot -sessionId $SessionId -branch $Branch -worktreePath $found.worktree
        }
        Write-Host "Existing worktree found for branch '$Branch':" -ForegroundColor Green
        Write-Host $found.worktree -ForegroundColor Yellow
        Write-Host "`n[Next Step]:" -ForegroundColor Cyan
        Write-Host "cd `"$($found.worktree)`""
        return
    }

    $targetPath = Get-WorktreePath -repoRoot $repoRoot -branchName $Branch
    Write-Host "Worktree not active. Re-creating at $targetPath..." -ForegroundColor Cyan
    git worktree add $targetPath $Branch

    if ($SessionId) {
        Register-Session -repoRoot $repoRoot -sessionId $SessionId -branch $Branch -worktreePath $targetPath
    }

    Write-Host "`nWorktree re-created at:" -ForegroundColor Green
    Write-Host $targetPath -ForegroundColor Yellow
}

function Invoke-Pr {
    $currentDir = (Get-Location).Path
    $repoRoot = Get-RepoRoot

    if ($currentDir -eq $repoRoot) {
        Write-Warning "You are in the main repository root. Usually 'pr' is invoked inside a worktree."
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) is required to create a PR automatically. Please install gh or create the PR manually."
    }

    $currentBranch = (git branch --show-current).Trim()
    if (-not $currentBranch -or $currentBranch -eq "main" -or $currentBranch -eq "master") {
        throw "Cannot create PR from branch '$currentBranch'."
    }

    Write-Host "Checking git status in $currentDir (branch: $currentBranch)..." -ForegroundColor Cyan

    Write-Host "Pushing to remote origin/$currentBranch..." -ForegroundColor Cyan
    git push -u origin $currentBranch

    $ghArgs = @("pr", "create", "--head", $currentBranch)
    if ($Title) { $ghArgs += @("--title", $Title) }
    if ($Body) { $ghArgs += @("--body", $Body) }
    if ($Draft) { $ghArgs += "--draft" }
    if (-not $Title -and -not $Body) { $ghArgs += "--fill" }

    Write-Host "Executing: gh $($ghArgs -join ' ')" -ForegroundColor Cyan
    $prOutput = & gh @ghArgs

    Write-Host "`nPull Request created successfully!" -ForegroundColor Green
    Write-Host $prOutput -ForegroundColor Yellow
    Write-Host "`n[Notice] Worktree is preserved for upcoming review feedback." -ForegroundColor Cyan
    Write-Host "Location: $currentDir"
}

function Invoke-Cleanup {
    $repoRoot = Get-RepoRoot
    $trees = Get-AllWorktrees
    $hasGh = (Get-Command gh -ErrorAction SilentlyContinue) -ne $null

    if ($Merged) {
        Write-Host "Scanning for merged worktrees..." -ForegroundColor Cyan
        $cleanedCount = 0

        foreach ($tree in $trees) {
            $treePath = Normalize-Path $tree.worktree
            if ($treePath -eq $repoRoot -or -not $tree.branch) { continue }

            $isMerged = $false
            if ($hasGh) {
                try {
                    $prInfo = gh pr view $tree.branch --json state 2>$null | ConvertFrom-Json
                    if ($prInfo -and $prInfo.state -eq "MERGED") {
                        $isMerged = $true
                    }
                } catch {}
            }

            if (-not $isMerged) {
                $mergedBranches = (git branch --merged $Base) | ForEach-Object { $_.Trim().TrimStart('*').Trim() }
                if ($mergedBranches -contains $tree.branch) {
                    $isMerged = $true
                }
            }

            if ($isMerged) {
                Write-Host "Removing merged worktree: $($tree.worktree) (branch: $($tree.branch))..." -ForegroundColor Yellow
                git worktree remove $tree.worktree $(if ($Force) { "--force" } else { $null })
                Unregister-Session -repoRoot $repoRoot -targetBranchOrPath $tree.worktree
                git branch -d $tree.branch 2>$null
                $cleanedCount++
            }
        }
        Write-Host "`nCleaned up $cleanedCount merged worktree(s)." -ForegroundColor Green
        return
    }

    if (-not $Branch) {
        throw "Specify -Branch <branch-name> or -Merged to perform cleanup."
    }

    $target = $trees | Where-Object { $_.branch -eq $Branch }
    if (-not $target) {
        $targetPath = Get-WorktreePath -repoRoot $repoRoot -branchName $Branch
        if (Test-Path $targetPath) {
            Write-Host "Removing dangling worktree path: $targetPath" -ForegroundColor Yellow
            git worktree remove $targetPath $(if ($Force) { "--force" } else { $null })
            Unregister-Session -repoRoot $repoRoot -targetBranchOrPath $targetPath
            return
        }
        throw "No active worktree found for branch '$Branch'."
    }

    if ((Normalize-Path $target.worktree) -eq $repoRoot) {
        throw "Cannot remove the main repository root worktree."
    }

    Write-Host "Removing worktree at: $($target.worktree)..." -ForegroundColor Yellow
    git worktree remove $target.worktree $(if ($Force) { "--force" } else { $null })
    Unregister-Session -repoRoot $repoRoot -targetBranchOrPath $target.worktree

    try {
        git branch -d $Branch 2>$null
        Write-Host "Deleted local branch '$Branch'." -ForegroundColor DarkGray
    } catch {
        Write-Warning "Local branch '$Branch' was not deleted (might not be merged yet). Use 'git branch -D $Branch' if intended."
    }

    Write-Host "`nCleanup completed for '$Branch'." -ForegroundColor Green
}

# --- Main Dispatch ---
switch ($Action) {
    "create"  { Invoke-Create }
    "current" { Invoke-Current }
    "list"    { Invoke-List }
    "resume"  { Invoke-Resume }
    "pr"      { Invoke-Pr }
    "cleanup" { Invoke-Cleanup }
}

