param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("SIT", "UAT")]
    [string]$BranchType
)

# =============================================
# 環境設定
# =============================================
$ScriptDir = $PSScriptRoot
$RepoPath  = if ($IsWindows) {
    "C:\Users\$env:USERNAME\Repo\idea_clone\mgbfep"
} else {
    "/Users/teferi/Repo/idea_clone/mgbfep"
}
$DockerBuildDir = if ($IsWindows) {
    "C:\Users\$env:USERNAME\Repo\FEP包版\docker-build"
} else {
    "/Users/teferi/Repo/FEP包版/docker-build"
}

$Python = if ($IsWindows) {
    Join-Path $ScriptDir "myenv\Scripts\python.exe"
} else {
    Join-Path $ScriptDir "myenv/bin/python3"
}

$env:RELEASE_NOTE_INPUT = Join-Path $ScriptDir "ReleaseNoteUpdateData.txt"
$env:RELEASE_NOTE_PATH  = Join-Path $RepoPath "source" "fep-release-note"

$GitBranch = switch ($BranchType) {
    "SIT" { "FEP_1-2_SIT" }
    "UAT" { "FEP_1-2_UAT" }
}

# 提前讀取 .env（供 GIT_PULL 警告與包版參數使用）
$EnvFile = Join-Path $DockerBuildDir ".env"
$EnvVars = @{}
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $key, $val = $_ -split '=', 2
        $EnvVars[$key.Trim()] = $val.Trim()
    }
}
$OutputPath = $EnvVars["HOST_OUTPUT_PATH"]

Write-Host "================================================"
Write-Host " FEP Release Note 更新 & 包版工具"
Write-Host " Branch : $GitBranch"
Write-Host "================================================"

Set-Location $RepoPath

# =============================================
# [1/8] git checkout（僅在非目標 branch 時執行）
# =============================================
Write-Host ""
$currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
if ($currentBranch -ne $GitBranch) {
    Write-Host "[1/8] git checkout $GitBranch（目前：$currentBranch）"
    git checkout $GitBranch
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "[1/8] 已在 $GitBranch，略過 checkout"
}

# =============================================
# [2/8] git reset --hard + git pull（pull 可 skip）
# =============================================
Write-Host ""
Write-Host "[2/8] git reset --hard HEAD"
git reset --hard HEAD

Write-Host ""
Write-Host "------------------------------------------------"
$pullChoice = Read-Host " git pull  [S] 略過 / [Enter] 執行"
if ($pullChoice -ieq "S") {
    Write-Host " ⏭️  略過 git pull"
    if ($EnvVars["GIT_PULL"] -ine "true") {
        Write-Host " ⚠️  警告：略過 pull 且 container GIT_PULL 非 true，docker build 可能使用舊版程式碼" -ForegroundColor Yellow
    }
} else {
    Write-Host " git pull origin $GitBranch"
    git pull origin $GitBranch
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# =============================================
# [3/8] SharePoint 讀取 → txt（可 skip）
# =============================================
Write-Host ""
Write-Host "------------------------------------------------"
$step3Choice = Read-Host "[3/8] SharePoint 讀取 → txt  [S] 略過 / [Enter] 執行"
if ($step3Choice -ieq "S") {
    if (-not (Test-Path $env:RELEASE_NOTE_INPUT)) {
        Write-Host " ❌ 錯誤：略過下載但 txt 不存在：$($env:RELEASE_NOTE_INPUT)"
        exit 1
    }
    Write-Host " ⏭️  略過，使用現有 txt"
} else {
    & $Python (Join-Path $ScriptDir "fetch_release_script.py") $BranchType
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# 確認 txt 內容（僅在有下載時需確認）
if ($step3Choice -ine "S") {
    Invoke-Item $env:RELEASE_NOTE_INPUT
    Write-Host ""
    Write-Host "------------------------------------------------"
    Write-Host " 📄 請確認 txt 內容是否正確"
    Write-Host " 檔案：$($env:RELEASE_NOTE_INPUT)"
    Write-Host "------------------------------------------------"
    Read-Host " 確認無誤後按 Enter 繼續，或按 Ctrl+C 中止"
}

# =============================================
# [4/8] txt → release note（可 skip，skip 則自動 skip [5]）
# =============================================
$skipCommit = $false
Write-Host ""
Write-Host "------------------------------------------------"
$step4Choice = Read-Host "[4/8] 更新 release note  [S] 略過（連帶略過 git commit）/ [Enter] 執行"
if ($step4Choice -ieq "S") {
    $skipCommit = $true
    Write-Host " ⏭️  略過更新 release note，自動略過 [5/8] git commit"
} else {
    & $Python (Join-Path $ScriptDir "UpdateReleaseNote.py")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host ""
    Write-Host "------------------------------------------------"
    Write-Host " 請確認以下 release note 變更是否正確"
    Write-Host "------------------------------------------------"
    git diff source/fep-release-note/
    Write-Host "------------------------------------------------"
    Read-Host " 確認無誤後按 Enter 繼續，或按 Ctrl+C 中止"
}

# =============================================
# [5/8] git commit release note（[4] skip 則自動 skip，否則可 skip）
# =============================================
Write-Host ""
if ($skipCommit) {
    Write-Host "[5/8] git commit → [4/8] 已略過，自動略過"
} else {
    Write-Host "------------------------------------------------"
    $step5Choice = Read-Host "[5/8] git commit release note  [S] 略過 / [Enter] 執行"
    if ($step5Choice -ieq "S") {
        Write-Host " ⏭️  略過 git commit"
    } else {
        git add (Join-Path "source" "fep-release-note")
        git commit -m "更新版號"

        Write-Host ""
        Write-Host "------------------------------------------------"
        Write-Host " 請確認 commit 內容是否正確"
        Write-Host "------------------------------------------------"
        git show --stat HEAD
        Write-Host "------------------------------------------------"
        Read-Host " 確認無誤後按 Enter 繼續，或按 Ctrl+C 中止"
    }
}

# =============================================
# Helper functions
# =============================================
function Get-MavenModules {
    param([string]$TxtPath)
    if (-not (Test-Path $TxtPath)) { return @() }
    $content = Get-Content $TxtPath -Raw

    $releaseNames = [regex]::Matches($content, '"([^"]+)\{') | ForEach-Object {
        $_.Groups[1].Value -split "`n" | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    }

    $prefixMap = [ordered]@{
        "fep-batch-task"     = "fep-batch-task"
        "fep-batch-cmdline"  = "fep-batch-cmdline"
        "fep-enckey-cmdline" = "fep-enckey-cmdline"
        "fep-batch"          = "fep-batch"
        "fep-server"         = "fep-server"
        "fep-gateway"        = "fep-gateway"
        "fep-service"        = "fep-service"
        "fep-notify"         = "fep-notify"
        "fep-web"            = "fep-web"
    }

    $result = @()
    foreach ($name in $releaseNames) {
        foreach ($prefix in $prefixMap.Keys) {
            if ($name -eq $prefix -or $name.StartsWith("$prefix-")) {
                if ($prefixMap[$prefix] -notin $result) { $result += $prefixMap[$prefix] }
                break
            }
        }
    }
    return $result
}

function Select-BuildMode {
    param([string]$Current)

    $options = @(
        @{ Key="1"; Mode="+web";    Desc="全部服務 + WAR（SIT 過版最常用）" },
        @{ Key="2"; Mode="-Pwar";   Desc="JAR + WAR（fep-war profile）" },
        @{ Key="3"; Mode="-web";    Desc="僅 fep-web.war" },
        @{ Key="4"; Mode="-enclib"; Desc="僅 enclib 模組" },
        @{ Key="5"; Mode="-safeaa"; Desc="僅 safeaa core" },
        @{ Key="6"; Mode="";        Desc="完整建置（僅 JAR，不含 WAR）" }
    )

    Write-Host " BUILD_MODE（目前 .env：$(if ($Current) { $Current } else { '（空白）' })）"
    Write-Host ""
    foreach ($opt in $options) {
        $marker = if ($opt.Mode -eq $Current) { "►" } else { " " }
        Write-Host " $marker [$($opt.Key)] $($opt.Mode.PadRight(10)) $($opt.Desc)"
    }
    Write-Host ""
    $choice = Read-Host " 輸入選項編號更改，或直接按 Enter 維持現有設定（Ctrl+C 中止）"

    if ($choice -match '^[1-6]$') {
        $sel = $options | Where-Object { $_.Key -eq $choice }
        Write-Host " ✅ BUILD_MODE：$(if ($sel.Mode) { $sel.Mode } else { '（空白）' })  →  $($sel.Desc)"
        return $sel.Mode
    }
    Write-Host " ✅ 維持現有 BUILD_MODE：$(if ($Current) { $Current } else { '（空白）' })"
    return $Current
}

# =============================================
# [6/8] build folder 清空（可 skip，skip 則自動 skip [7] docker build）
# =============================================
$skipBuild = $false
Write-Host ""
Write-Host "------------------------------------------------"
Write-Host " 輸出路徑：$OutputPath"
Write-Host "------------------------------------------------"
$step6Choice = Read-Host "[6/8] 清空輸出資料夾  [S] 略過（連帶略過 docker build）/ [Enter] 執行"
if ($step6Choice -ieq "S") {
    $skipBuild = $true
    Write-Host " ⏭️  略過清空資料夾，自動略過 [7/8] docker build"
    $tarCount = (Get-ChildItem $OutputPath -Filter "*.tar.gz" -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($tarCount -eq 0) {
        Write-Host " ⚠️  警告：輸出資料夾目前無 tar.gz，[8/8] 解壓縮步驟可能無檔可處理" -ForegroundColor Yellow
    }
} else {
    if (Test-Path $OutputPath) {
        Write-Host " 清空輸出資料夾：$OutputPath"
        Get-ChildItem $OutputPath | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================
# [7/8] Docker build（[6] skip 則自動 skip）
# =============================================
if ($skipBuild) {
    Write-Host ""
    Write-Host "[7/8] docker build → [6/8] 已略過，自動略過"
} else {
    $AutoModules  = Get-MavenModules -TxtPath $env:RELEASE_NOTE_INPUT
    $BuildMode    = $EnvVars["BUILD_MODE"]
    $BuildModules = ""

    $isCmdlineOnly = ($AutoModules | Where-Object { $_ -notmatch "cmdline" }).Count -eq 0 -and $AutoModules.Count -gt 0

    Write-Host ""
    Write-Host "[7/8] Docker 包版"
    Write-Host "------------------------------------------------"
    Write-Host " Branch   : $GitBranch（由本 script 指定，覆蓋 .env）"
    Write-Host " GIT_PULL : $($EnvVars['GIT_PULL'])"
    Write-Host " 輸出路徑 : $OutputPath"
    Write-Host ""

    if ($isCmdlineOnly) {
        Write-Host " 📋 release note 僅含 cmdline 模組，不需要包版" -ForegroundColor Yellow
        Read-Host " 按 Enter 結束，或按 Ctrl+C 中止"
        exit 0
    }

    Write-Host " [A] 全 build（手動選擇 BUILD_MODE）"
    if ($AutoModules.Count -gt 0) {
        Write-Host " [B] 依 release note 部分 build"
        Write-Host "     偵測到的 Maven 模組：$($AutoModules -join ', ')"
    } else {
        Write-Host " [B] 依 release note 部分 build  ⚠️  未偵測到可對應模組，無法選擇"
    }
    Write-Host "------------------------------------------------"
    $buildChoice = Read-Host " 請選擇 [A/B]（預設 B）"
    if ($buildChoice -match '^\s*$') { $buildChoice = "B" }

    Write-Host ""
    if ($buildChoice -ieq "B" -and $AutoModules.Count -gt 0) {
        $BuildModules = $AutoModules -join ","
        Write-Host " ✅ 部分 build 模組：$BuildModules"
    } else {
        $BuildMode = Select-BuildMode -Current $BuildMode
    }

    $env:BUILD_MODE    = $BuildMode
    $env:BUILD_MODULES = $BuildModules
    $env:BRANCH        = $GitBranch

    Set-Location $DockerBuildDir
    docker compose run --rm fep-builder
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Set-Location $RepoPath
}

# =============================================
# [8/8] 搬移並解壓
# =============================================
Write-Host ""
Write-Host "------------------------------------------------"
Write-Host " 📦 [8/8] 搬移並解壓"
Write-Host "------------------------------------------------"

$TarFiles = Get-ChildItem $OutputPath -Filter "*.tar.gz" -ErrorAction SilentlyContinue | Sort-Object Name
if ($TarFiles -and $TarFiles.Count -gt 0) {
    Write-Host " 可解壓縮的 tar.gz 檔案："
    for ($idx = 0; $idx -lt $TarFiles.Count; $idx++) {
        Write-Host "  [$($idx + 1)] $($TarFiles[$idx].Name)"
    }
    Write-Host "  [A] 全部解壓縮"
    Write-Host "  [N] 略過解壓縮"
    Write-Host ""
    $selection = Read-Host " 請輸入編號（逗號分隔，如 1,3），或輸入 A / N（預設 A）"

    $toExtract = @()
    if ($selection -ieq "N") {
        Write-Host " ⏭️  略過解壓縮"
    } elseif ($selection -match '^\s*$' -or $selection -ieq "A") {
        $toExtract = $TarFiles
    } else {
        foreach ($token in ($selection -split ',')) {
            $n = $token.Trim()
            if ($n -match '^\d+$') {
                $i = [int]$n - 1
                if ($i -ge 0 -and $i -lt $TarFiles.Count) { $toExtract += $TarFiles[$i] }
            }
        }
    }

    # 清理上次解壓縮留下的目錄
    Get-ChildItem $OutputPath | Where-Object {
        $_.PSIsContainer -and $_.Name -ne "fep-app"
    } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    foreach ($tar in $toExtract) {
        Write-Host ""
        Write-Host " 解壓縮：$($tar.Name)"
        tar -xzf $tar.FullName -C $OutputPath

        $FepAppDir = Join-Path $OutputPath "fep-app"
        if (Test-Path $FepAppDir) {
            $innerDir = Get-ChildItem $FepAppDir -Directory | Select-Object -First 1
            if ($innerDir) {
                $dest = Join-Path $OutputPath $innerDir.Name
                if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
                Copy-Item -Path $innerDir.FullName -Destination $dest -Recurse -Force
                Remove-Item $innerDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host " ✅ 移出：$($innerDir.Name)"
            }
            Remove-Item $FepAppDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host " ⚠️  未找到 .tar.gz 檔案（WAR only 或部分 build），略過解壓縮"
}

Write-Host ""
Write-Host " 📂 產出物列表："
Get-ChildItem $OutputPath | ForEach-Object { Write-Host "   $($_.Name)" }

Invoke-Item $OutputPath
Write-Host ""
Write-Host "------------------------------------------------"
Write-Host " ⚠️  請確認產出物是否正確"
Write-Host " 📁 輸出路徑：$OutputPath"
Write-Host "------------------------------------------------"
Read-Host " 確認無誤後按 Enter 繼續，或按 Ctrl+C 中止"

# =============================================
# Config 提醒
# =============================================
$ConfigFolder = switch ($BranchType) {
    "SIT" { Join-Path $RepoPath "source" "SIT套config" }
    "UAT" { Join-Path $RepoPath "source" "UAT套config" }
}

Write-Host ""
if (Test-Path $ConfigFolder) {
    Invoke-Item $ConfigFolder
} else {
    Write-Host " ⚠️  Config 資料夾不存在：$ConfigFolder"
}
Write-Host "================================================"
Write-Host " ⚠️  請記得套用 $BranchType Config"
Write-Host " 📁 Config 路徑：$ConfigFolder"
Write-Host "================================================"
Read-Host " 確認 Config 無誤後按 Enter 結束"

Write-Host ""
Write-Host "================================================"
Write-Host " ✅ 完成"
Write-Host "================================================"
