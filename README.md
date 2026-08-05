# FEP 包版工具

跨平台（Windows / macOS / Linux）的 FEP 自動化包版腳本，整合 Release Note 更新、Maven 建置與產出物整理，以互動式選單引導操作。

---

## 目錄結構

```
FEP包版/
├── release/
│   ├── run.ps1                   # 主流程腳本（8 步驟互動式）
│   ├── fetch_release_script.py   # 從 SharePoint 下載 release note script
│   ├── UpdateReleaseNote.py      # 將 script 寫入 fep-release-note 原始碼
│   └── myenv/                    # Python venv（每台機器各自建立，不入版）
├── docker-build/
│   ├── Dockerfile                # 建置用 Docker image（Java 21 + Maven 3.9.6）
│   ├── docker-compose.yml        # 掛載 repo / output / .m2
│   ├── .env.macos                # macOS 環境設定（本機路徑，不入版）
│   ├── .env.macos.example        # macOS 範本
│   ├── .env.windows              # Windows 環境設定（本機路徑，不入版）
│   └── .env.windows.example      # Windows 範本
└── 文件/                          # 過版作業說明文件
```

---

## 事前準備

### 必要條件

| 項目 | 說明 |
|------|------|
| PowerShell | Windows：PowerShell 7+；macOS：`brew install powershell` |
| Docker Desktop | Docker build 模式必須；Native build 模式可選 |
| Python 3 | SharePoint 讀取功能（步驟 3）需要 |
| Git | 原始碼管理 |
| Java 21 + Maven | 僅 Native build 模式需要（Windows）|

### 首次設定

**1. 複製 `.env` 設定檔**

```bash
# macOS
cp docker-build/.env.macos.example docker-build/.env.macos

# Windows
copy docker-build\.env.windows.example docker-build\.env.windows
```

依本機實際路徑修改 `.env` 內容（FEP repo 路徑、輸出路徑等）。

**2. 建立 Python 虛擬環境**

```bash
cd release

# macOS / Linux
python3 -m venv myenv
./myenv/bin/python3 -m pip install requests pandas openpyxl

# Windows
python -m venv myenv
.\myenv\Scripts\python.exe -m pip install requests pandas openpyxl
```

> `myenv/` 不能跨平台搬用，每台機器需各自建立。

---

## 使用方式

```powershell
# 互動式選單（推薦）
cd release
.\run.ps1

# 直接指定 branch（略過選單）
.\run.ps1 -BranchType 1-3_SIT   # FEP_1-3_SIT
.\run.ps1 -BranchType 1-3_UAT   # FEP_1-3_UAT
.\run.ps1 -BranchType 2-1_SIT   # FEP_2-1
```

---

## 流程說明（8 步驟）

```
[1/8] git reset             → 清空未 commit 變更（顯示 diff 後可選擇是否執行，避免下一步 checkout 失敗）
[2/8] git checkout / pull   → 切換到目標 branch，並更新最新程式碼（pull 可略過）
[3/8] SharePoint → txt      → 從 SharePoint Excel 下載 release note script（UAT 略過）
[4/8] 更新 release note     → 將 script 寫入原始碼（UAT 略過）
[5/8] git commit            → commit release note 變更（UAT 略過）
[6/8] 清空輸出資料夾        → 準備存放產出物
[7/8] Maven 建置            → Docker 或 Native build（見下方）
[8/8] 解壓縮 & 提示 Config  → 解開 bin tar.gz，提醒套用 config
```

每個步驟可個別略過（輸入 `S`），失敗時可選擇繼續或中止。

---

## 建置模式

### Docker build（預設，所有平台）

在 Docker container 內執行 Maven，無需本機安裝 Java / Maven。

```
Image : eclipse-temurin:21-jdk-jammy
Maven : 3.9.6（container 內建）
```

**Windows 注意**：Docker 掛載 Windows 路徑時會經過 WSL2 橋接，I/O 較慢。  
Maven cache（`.m2`）改用 Docker named volume `fep-m2-cache`，住在 Linux 層避免橋接開銷。

首次使用會詢問是否將本機 `C:\Users\<你>\\.m2` 複製至 volume（約 1~2 分鐘），  
之後每次 build 不需重新下載依賴（約 2.5 GB）。

### Native build（Windows 限定）

直接呼叫本機 `mvn`，**無 WSL2 I/O 開銷，速度顯著較快**。  
步驟 7 在 Windows 下會提示選擇 `[N] Native` 或 `[D] Docker`（預設 N）。

設定本機 Java / Maven 路徑（`.env.windows`）：

```ini
# 未設定則依賴系統 PATH
# JAVA_HOME=C:\Program Files\...   # 已有正確系統環境變數則保持註解
MAVEN_HOME=C:\tools\apache-maven-3.9.6
```

---

## BUILD_MODE 選項

| 模式 | 說明 | 產出 |
|------|------|------|
| `+web` | 全部服務 + WAR（SIT 過版最常用）| JAR + WAR |
| `-Pwar` | JAR + WAR（fep-war profile）| JAR + WAR |
| `-web` | 僅 fep-web.war | WAR |
| `-enclib` | 僅 enclib 模組 | — |
| `-safeaa` | 僅 safeaa core | — |
| （空白）| 完整建置，僅 JAR | JAR |

SIT 模式會依 release note 偵測模組，自動建議**部分 build** 縮短建置時間；  
UAT 模式固定全 build，手動選擇 `BUILD_MODE`。

---

## 支援的 Branch

| 選項 | Branch 名稱 | 適用 |
|------|-------------|------|
| `1-3_SIT` | `FEP_1-3_SIT` | SIT 過版 |
| `1-3_UAT` | `FEP_1-3_UAT` | UAT 過版 |
| `2-1_SIT` | `FEP_2-1` | SIT 過版（2-1 版本）|

---

## 常見問題

**Q: 找不到虛擬環境 Python？**  
依「首次設定」第 2 步建立 `myenv/`，每台機器需各自建立，不能從其他機器複製。

**Q: Docker build 在 Windows 非常慢？**  
選擇 `[N] Native build`，直接呼叫本機 mvn，速度與 macOS 相當。  
若仍需 Docker，確認 `.env.windows` 中 `M2_PATH=fep-m2-cache`（named volume），並完成 cache 初始化。

**Q: JAVA_HOME 報錯？**  
`.env.windows` 的 `JAVA_HOME` 會覆蓋系統環境變數。  
若系統已設定正確的 Java 路徑，請將 `.env.windows` 中的 `JAVA_HOME=...` 這行**注解掉**。

**Q: volume name 變成 `docker-build_fep-m2-cache`？**  
`docker-compose.yml` 已設定 `name: fep-m2-cache`，確認使用最新版 compose 檔案即可。

---

## 相關工具

- [`~/Repo/mgbfep_pipeline/FEP_CI.ps1`](https://github.com) — CI pipeline 腳本，用於 TFS / Azure DevOps 自動化建置（無互動、無 Docker、支援離線 Maven）
