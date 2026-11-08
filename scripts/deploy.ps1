<#
.SYNOPSIS
    worktree-isolate スキルを Antigravity のグローバルスキルディレクトリへデプロイするスクリプト

.DESCRIPTION
    開発リポジトリ内の skills/worktree-isolate を、Antigravity のグローバルスキル領域
    (~/.gemini/config/skills/worktree-isolate) に同期・デプロイします。
    デプロイ後は、PC 内のすべてのプロジェクトでエージェントが worktree-isolate スキルを利用可能になります。

.EXAMPLE
    # 通常デプロイ（最新コミット状態をデプロイ）
    .\scripts\deploy.ps1

    # 未コミットの作業中（WIP）状態を含めてデプロイ
    .\scripts\deploy.ps1 -Wip

    # デプロイ状態の確認
    .\scripts\deploy.ps1 -Status

    # シミュレーション実行
    .\scripts\deploy.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Wip,
    [string]$Ref,
    [string]$Dest,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$SkillSourceDir = Join-Path $RepoRoot "skills" "worktree-isolate"

# デフォルトの宛先パス: ~/.gemini/config/skills/worktree-isolate
$DestDir = if ($Dest) { $Dest } else {
    Join-Path $HOME ".gemini" "config" "skills" "worktree-isolate"
}
$InfoFile = Join-Path $DestDir ".deploy-info.json"

function Get-SkillVersion([string]$dir) {
    $pkgPath = Join-Path $RepoRoot "package.json"
    if (Test-Path $pkgPath) {
        try {
            $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
            if ($pkg.version) { return $pkg.version }
        } catch {}
    }
    $skillPath = Join-Path $dir "SKILL.md"
    if (Test-Path $skillPath) {
        $content = Get-Content $skillPath -Raw
        if ($content -match '(?m)^\s*version:\s*["'']?([^"''\s]+)["'']?') {
            return $Matches[1]
        }
    }
    return "unknown"
}

# --- Status Display ---
if ($Status) {
    Write-Host "`nChecking deployed worktree-isolate skill status..." -ForegroundColor Cyan
    Write-Host "Destination: $DestDir"

    if (-not (Test-Path $DestDir)) {
        Write-Host "Status:      ❌ Not deployed (directory does not exist)" -ForegroundColor Red
        return
    }

    $skillMd = Join-Path $DestDir "SKILL.md"
    if (-not (Test-Path $skillMd)) {
        Write-Host "Status:      ⚠️ Directory exists, but SKILL.md is missing." -ForegroundColor Yellow
        return
    }

    if (Test-Path $InfoFile) {
        try {
            $info = Get-Content $InfoFile -Raw | ConvertFrom-Json
            Write-Host "Status:      ✅ Deployed" -ForegroundColor Green
            Write-Host "Version:     $($info.version)" -ForegroundColor Yellow
            Write-Host "Mode:        $(if ($info.mode -eq 'worktree') { '🛠️ Worktree (WIP changes included)' } else { '📦 Git snapshot' })"
            Write-Host "Source Ref:  $($info.ref) ($($info.commit))"
            if ($info.commitMessage) {
                Write-Host "Commit:      `"$($info.commitMessage)`""
            }
            Write-Host "Deployed At: $($info.deployedAt)"
        } catch {
            Write-Host "Status:      ⚠️ Deployed, but .deploy-info.json is corrupted." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Status:      ℹ️ Deployed (manual copy without .deploy-info.json)" -ForegroundColor DarkGray
    }
    return
}

# --- Deployment ---

$version = Get-SkillVersion -dir $SkillSourceDir

Write-Host "`n📦 Deploying worktree-isolate skill to Antigravity global directory..." -ForegroundColor Cyan
Write-Host "Version:     $version" -ForegroundColor Yellow
Write-Host "Source:      $SkillSourceDir"
Write-Host "Destination: $DestDir"
if ($DryRun) {
    Write-Host "Mode:        Dry-run (no files will be modified)" -ForegroundColor Magenta
}

if (-not (Test-Path $SkillSourceDir)) {
    throw "Source skill directory not found: $SkillSourceDir"
}

$deployInfo = @{
    version    = $version
    deployedAt = (Get-Date).ToString("o")
    mode       = if ($Wip) { "worktree" } else { "git-ref" }
}

$currentBranch = "HEAD"
$headCommit = ""
try {
    $currentBranch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    $headCommit = (git -C $RepoRoot rev-parse --short HEAD).Trim()
} catch {}

if ($Wip) {
    # Mode 1: 作業ツリー直接コピー (未コミットのWIP変更を含む)
    $deployInfo["ref"] = $currentBranch
    $deployInfo["commit"] = $headCommit
    $deployInfo["commitMessage"] = "Worktree sync based on $currentBranch ($headCommit)"

    $sourceFiles = Get-ChildItem -Path $SkillSourceDir -Recurse -File
    Write-Host "Mode:        🛠️ Worktree (WIP changes included)" -ForegroundColor Yellow
    Write-Host "Files found: $($sourceFiles.Count) file(s)"

    if (-not $DryRun) {
        if (Test-Path $DestDir) {
            Remove-Item -Path $DestDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        Copy-Item -Path (Join-Path $SkillSourceDir "*") -Destination $DestDir -Recurse -Force

        $deployInfo | ConvertTo-Json -Depth 5 | Set-Content $InfoFile -Encoding UTF8
        Write-Host "`n✅ Successfully deployed working tree to Antigravity global skills directory!" -ForegroundColor Green
        Write-Host "Path: $DestDir" -ForegroundColor Green
    } else {
        Write-Host "`nℹ️ [Dry-run] Would copy $($sourceFiles.Count) file(s) to $DestDir" -ForegroundColor Magenta
    }
} else {
    # Mode 2: Git スナップショット (コミット状態を安全にデプロイ)
    $refToUse = if ($Ref) { $Ref } else {
        if ($currentBranch -ne "HEAD") { $currentBranch } else { "HEAD" }
    }

    $commitHash = ""
    $commitMsg = ""
    try {
        $commitHash = (git -C $RepoRoot rev-parse --short $refToUse).Trim()
        $commitMsg = (git -C $RepoRoot log -1 --format=%s $refToUse).Trim()
    } catch {
        throw "Failed to resolve git ref '$refToUse': $_"
    }

    $deployInfo["ref"] = $refToUse
    $deployInfo["commit"] = $commitHash
    $deployInfo["commitMessage"] = $commitMsg

    Write-Host "Mode:        📦 Git snapshot ($refToUse @ $commitHash)" -ForegroundColor Green

    # 未コミット差分の存在通知
    $statusOutput = git -C $RepoRoot status --porcelain skills/worktree-isolate
    $uncommitted = if ($statusOutput) { ($statusOutput -join "`n").Trim() } else { "" }
    if ($uncommitted -and -not $Ref) {
        Write-Host "⚠️ Notice:    Uncommitted changes exist in skills/worktree-isolate." -ForegroundColor Yellow
        Write-Host "              Deploying last committed state ($commitHash)." -ForegroundColor Yellow
        Write-Host "              To include uncommitted changes, use: .\scripts\deploy.ps1 -Wip`n" -ForegroundColor Yellow
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wt-deploy-" + [System.Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        
        # git archive で指定 ref の skills/worktree-isolate を抽出
        cmd /c "git -C `"$RepoRoot`" archive $refToUse skills/worktree-isolate | tar -x -C `"$tmpDir`""
        
        $extractedDir = Join-Path $tmpDir "skills" "worktree-isolate"
        if (-not (Test-Path $extractedDir)) {
            throw "Extracted archive did not contain skills/worktree-isolate/"
        }

        $sourceFiles = Get-ChildItem -Path $extractedDir -Recurse -File
        Write-Host "Files found: $($sourceFiles.Count) file(s)"

        if (-not $DryRun) {
            if (Test-Path $DestDir) {
                Remove-Item -Path $DestDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
            Copy-Item -Path (Join-Path $extractedDir "*") -Destination $DestDir -Recurse -Force

            $deployInfo | ConvertTo-Json -Depth 5 | Set-Content $InfoFile -Encoding UTF8
            Write-Host "`n✅ Successfully deployed $refToUse ($commitHash) to Antigravity global skills directory!" -ForegroundColor Green
            Write-Host "Path: $DestDir" -ForegroundColor Green
        } else {
            Write-Host "`nℹ️ [Dry-run] Would copy $($sourceFiles.Count) file(s) to $DestDir" -ForegroundColor Magenta
        }
    } finally {
        if (Test-Path $tmpDir) {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

