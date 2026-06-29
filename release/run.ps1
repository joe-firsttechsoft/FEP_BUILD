param(
    [ValidateSet("1-3_SIT", "1-3_UAT")]
    [string]$BranchType
)

# 若未傳入參數，以互動選單詢問
if (-not $BranchType) {
    Write-Host ""
    Write-Host " 請選擇 Branch："
    Write-Host " [1] FEP_1-3_SIT"
    Write-Host " [2] FEP_1-3_UAT"
    $branchInput = Read-Host " 請輸入 [1/2]（預設 1）"
    $BranchType = switch ($branchInput.Trim()) {
        "1"  { "1-3_SIT" }
        ""   { "1-3_SIT" }
        "2"  { "1-3_UAT" }
        default { Write-Host " ❌ 無效選項：$branchInput" -ForegroundColor Red; exit 1 }
    }
}

# =============================================
# 環境設定
# =============================================
$ScriptDir = $PSScriptRoot
# 跨平台取得目前使用者名稱（$env:USERNAME 僅 Windows 有，macOS/Linux 需用 $env:USER）
$UserName = [System.Environment]::UserName
$RepoPath  = if ($IsWindows) {
    "C:\Users\$UserName\Repo\idea_clone\mgbfep"
} else {
    "/Users/$UserName/Repo/idea_clone/mgbfep"
}
# docker-build 是本 repo（release/ 的上一層）的同層資料夾，
# 用相對路徑推算，避免不同機器上 repo 資料夾名稱不一致（例如 Windows 上叫 FEP_BUILD）導致路徑找不到
$DockerBuildDir = Join-Path (Split-Path $ScriptDir -Parent) "docker-build"

$Python = if ($IsWindows) {
    Join-Path $ScriptDir "myenv\Scripts\python.exe"
} else {
    Join-Path $ScriptDir "myenv/bin/python3"
}

if (-not (Test-Path $Python)) {
    Write-Host " ❌ 找不到虛擬環境 Python：$Python" -ForegroundColor Red
    Write-Host " 此機器尚未建立 myenv（venv 不能跨平台搬用，每台機器需自行建立），請執行：" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   cd `"$ScriptDir`""
    if ($IsWindows) {
        Write-Host "   python -m venv myenv"
        Write-Host "   .\myenv\Scripts\python.exe -m pip install requests pandas openpyxl"
    } else {
        Write-Host "   python3 -m venv myenv"
        Write-Host "   ./myenv/bin/python3 -m pip install requests pandas openpyxl"
    }
    Write-Host ""
    exit 1
}

$env:RELEASE_NOTE_INPUT = Join-Path $ScriptDir "ReleaseNoteUpdateData.txt"
$env:RELEASE_NOTE_PATH  = Join-Path $RepoPath "source" "fep-release-note"

# 避免 macOS 在 exFAT 外接碟上建立 ._ resource fork 檔案（Windows/Linux 忽略此變數）
$env:COPYFILE_DISABLE = "1"

$GitBranch = switch ($BranchType) {
    "1-3_SIT" { "FEP_1-3_SIT" }
    "1-3_UAT" { "FEP_1-3_UAT" }
}

# 依平台選擇對應的 .env（路徑格式不同，Windows/macOS 分開維護）
$EnvFileName = if ($IsWindows) { ".env.windows" } else { ".env.macos" }
$EnvFile = Join-Path $DockerBuildDir $EnvFileName
if (-not (Test-Path $EnvFile)) {
    Write-Host " ❌ 找不到 $EnvFileName：$EnvFile" -ForegroundColor Red
    Write-Host " 請從 $EnvFileName.example 複製一份，依本機路徑修改後使用" -ForegroundColor Yellow
    exit 1
}
$EnvVars = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
    $key, $val = $_ -split '=', 2
    $EnvVars[$key.Trim()] = $val.Trim()
}
$OutputPath = $EnvVars["HOST_OUTPUT_PATH"]
if (-not $OutputPath) {
    Write-Host " ❌ .env 中未設定 HOST_OUTPUT_PATH：$EnvFile" -ForegroundColor Red
    exit 1
}

Write-Host "================================================"
Write-Host " FEP Release Note 更新 & 包版工具"
Write-Host " Branch : $GitBranch"
Write-Host "================================================"

# 記錄原始目錄，腳本結束（含中途 exit）時切回去，避免切換到專案資料夾
$OriginalLocation = Get-Location

try {

Set-Location $RepoPath

# =============================================
# Helper：步驟失敗時詢問是否繼續或中止
# =============================================
function Test-StepResult {
    param(
        [string]$StepName,
        [int]$Code = $LASTEXITCODE
    )
    if ($Code -ne 0) {
        Write-Host ""
        Write-Host " ❌ $StepName 執行失敗（exit code: $Code）" -ForegroundColor Red
        $cont = Read-Host " [Enter] 繼續後續步驟 / [Q] 中止"
        if ($cont -imatch '^[Qq]') { exit $Code }
    }
}

# =============================================
# [1/8] git checkout（僅在非目標 branch 時執行）
# =============================================
Write-Host ""
$currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
if ($currentBranch -ne $GitBranch) {
    Write-Host "[1/8] git checkout $GitBranch（目前：$currentBranch）"
    git checkout $GitBranch
    Test-StepResult "git checkout $GitBranch"
} else {
    Write-Host "[1/8] 已在 $GitBranch，略過 checkout"
}

# =============================================
# [2/8] git reset --hard + git pull（可個別 skip）
# =============================================
Write-Host ""
Write-Host "[2/8] git reset / pull"
Write-Host "------------------------------------------------"

# 顯示未 commit 的差異
$diffStat = git diff --stat HEAD 2>$null
$statusOut = git status --short 2>$null
if ($diffStat -or $statusOut) {
    Write-Host " 📋 目前未 commit 的變更："
    if ($statusOut) { $statusOut | ForEach-Object { Write-Host "   $_" } }
    if ($diffStat)  { $diffStat  | ForEach-Object { Write-Host "   $_" } }
} else {
    Write-Host " ✅ 目前無未 commit 的變更"
}

Write-Host "------------------------------------------------"
$resetPullChoice = Read-Host " git reset --hard + pull  [S] 略過 / [Enter] 執行"

if ($resetPullChoice -ieq "S") {
    Write-Host " ⏭️  略過 git reset + pull"
    if ($EnvVars["GIT_PULL"] -ine "true") {
        Write-Host " ⚠️  警告：略過 pull 且 container GIT_PULL 非 true，docker build 可能使用舊版程式碼" -ForegroundColor Yellow
    }
} else {
    Write-Host " git reset --hard HEAD"
    git reset --hard HEAD
    Write-Host " git pull origin $GitBranch"
    git pull origin $GitBranch
    Test-StepResult "git pull origin $GitBranch"
}

# 初始化（UAT 模式略過 [3-5/8]，確保後續步驟變數已定義）
$step3Choice = "S"
$skipCommit  = $true

if ($BranchType -eq "1-3_UAT") {
    Write-Host ""
    Write-Host "[3-5/8] UAT 模式 → 略過 SharePoint 讀取 / release note 更新 / git commit"
} else {
    # =============================================
    # [3/8] SharePoint 讀取 → txt（可 skip）
    # =============================================
    Write-Host ""
    Write-Host "------------------------------------------------"
    $step3Choice = Read-Host "[3/8] SharePoint 讀取 → txt  [S] 略過 / [Enter] 執行"
    if ($step3Choice -ieq "S") {
        if (-not (Test-Path $env:RELEASE_NOTE_INPUT)) {
            Write-Host " ❌ 錯誤：略過下載但 txt 不存在：$($env:RELEASE_NOTE_INPUT)" -ForegroundColor Red
            $cont = Read-Host " [Enter] 繼續後續步驟 / [Q] 中止"
            if ($cont -imatch '^[Qq]') { exit 1 }
        }
        Write-Host " ⏭️  略過，使用現有 txt"
    } else {
        & $Python (Join-Path $ScriptDir "fetch_release_script.py") $BranchType
        Test-StepResult "SharePoint 讀取（fetch_release_script.py）"
    }

    # 確認 txt 內容（僅在有下載時需確認）
    if ($step3Choice -ine "S") {
        Write-Host ""
        Write-Host "------------------------------------------------"
        Write-Host " 📄 txt 內容（本次下載）：$($env:RELEASE_NOTE_INPUT)"
        Write-Host "------------------------------------------------"
        Get-Content $env:RELEASE_NOTE_INPUT | ForEach-Object { Write-Host "   $_" }
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
        Test-StepResult "更新 release note（UpdateReleaseNote.py）"

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
$AutoModules = @()  # 初始化，避免 skip [7] 時 step 8 引用未定義變數
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
        Get-ChildItem $OutputPath -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
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

    if ($BranchType -eq "1-3_UAT") {
        # UAT：直接全 build，選 BUILD_MODE
        Write-Host " UAT 模式：全 build"
        $BuildMode = Select-BuildMode -Current $BuildMode
    } else {
        if ($isCmdlineOnly) {
            Write-Host " 📋 release note 僅含 cmdline 模組，不需要包版" -ForegroundColor Yellow
            Read-Host " 按 Enter 結束，或按 Ctrl+C 中止"
            exit 0
        }

        $txtSource = if ($step3Choice -ieq "S") { "⚠️  使用既有 txt（非本次下載）" } else { "本次下載" }
        Write-Host " [A] 全 build（手動選擇 BUILD_MODE）"
        if ($AutoModules.Count -gt 0) {
            Write-Host " [B] 依 release note 部分 build  【來源：$txtSource】"
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
    }

    $env:BUILD_MODE    = $BuildMode
    $env:BUILD_MODULES = $BuildModules
    $env:BRANCH        = $GitBranch

    Set-Location $DockerBuildDir
    docker compose --env-file $EnvFileName run --rm fep-builder
    Test-StepResult "Docker build"
    Set-Location $RepoPath
}

# =============================================
# [8/8] 搬移並解壓
# =============================================
Write-Host ""
Write-Host "------------------------------------------------"
Write-Host " 📦 [8/8] 搬移並解壓"
Write-Host "------------------------------------------------"

$AllBinTarFiles = Get-ChildItem $OutputPath -Filter "*bin*.tar.gz" -ErrorAction SilentlyContinue | Sort-Object Name

# 僅在本次有重新下載 release note 時才依模組篩選；略過下載則一律顯示全部
if ($AutoModules.Count -gt 0 -and $step3Choice -ine "S") {
    $BinTarFiles = $AllBinTarFiles | Where-Object {
        $name = $_.Name
        $AutoModules | Where-Object { $name -like "$_*" }
    }
    if ($BinTarFiles.Count -lt $AllBinTarFiles.Count) {
        Write-Host " 依 release note 篩選後的 bin 套件（共 $($AllBinTarFiles.Count) 個，篩選後 $($BinTarFiles.Count) 個）："
    } else {
        Write-Host " bin 套件："
    }
} else {
    $BinTarFiles = $AllBinTarFiles
    Write-Host " bin 套件（顯示全部）："
}

if ($BinTarFiles -and $BinTarFiles.Count -gt 0) {
    $BinTarFiles | ForEach-Object { Write-Host "   $($_.Name)" }

    # 解壓前清除 output 目錄（含子資料夾）內所有 ._ 檔案
    $dotUnderscoreFiles = Get-ChildItem $OutputPath -Filter "._*" -Recurse -Force -ErrorAction SilentlyContinue
    if ($dotUnderscoreFiles) {
        $dotUnderscoreFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host " 🧹 已清除 $($dotUnderscoreFiles.Count) 個 ._ 檔案"
    }

    Write-Host ""
    $extractChoice = Read-Host " 是否將 bin 套件解壓到 bin 子目錄？[Y/N]（預設 Y）"

    if ($extractChoice -ine "N") {
        $BinOutputPath = Join-Path $OutputPath "bin"
        if (Test-Path $BinOutputPath) {
            Get-ChildItem $BinOutputPath -Force -Recurse |
                Sort-Object FullName -Descending |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Remove-Item $BinOutputPath -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $BinOutputPath | Out-Null

        foreach ($tar in $BinTarFiles) {
            Write-Host " 解壓縮：$($tar.Name)"
            tar -xzf $tar.FullName -C $BinOutputPath
        }

        # 清除 macOS 在 exFAT 上產生的 ._ resource fork 檔案
        Get-ChildItem $BinOutputPath -Filter "._*" -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host " 🧹 已清除 ._ 隱藏檔案"
    } else {
        Write-Host " ⏭️  略過解壓縮"
    }
} else {
    Write-Host " ⚠️  未找到 bin tar.gz 檔案，略過解壓縮"
}

$BinOutputPath = Join-Path $OutputPath "bin"
$OpenPath = if (Test-Path $BinOutputPath) { $BinOutputPath } else { $OutputPath }

Write-Host ""
Write-Host " 📂 產出物列表："
Get-ChildItem $OpenPath | ForEach-Object { Write-Host "   $($_.Name)" }

Invoke-Item $OpenPath
Write-Host ""
Write-Host "------------------------------------------------"
Write-Host " ⚠️  請確認產出物是否正確"
Write-Host " 📁 輸出路徑：$OpenPath"
Write-Host "------------------------------------------------"
Read-Host " 確認無誤後按 Enter 繼續，或按 Ctrl+C 中止"

# =============================================
# Config 提醒
# =============================================
$ConfigFolder = switch ($BranchType) {
    "1-3_SIT" { Join-Path $RepoPath "source" "SIT套config" }
    "1-3_UAT" { Join-Path $RepoPath "source" "UAT套config" }
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

} finally {
    Set-Location $OriginalLocation
}
