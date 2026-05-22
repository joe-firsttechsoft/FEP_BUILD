# MEGA FEP 包版說明 — MGBFEPbuild.sh

> **Program Author:** Eric Chen　|　**Documentation:** CH Chuang

---

## 目錄

1. [主要流程說明](#1-主要流程說明)
2. [參數定義與初始化](#2-參數定義與初始化)
3. [Git 倉庫管理](#3-git-倉庫管理)
4. [多模式 Maven 建置](#4-多模式-maven-建置)
5. [產出物整理](#5-產出物整理)
6. [自動化解壓縮與結構優化](#6-自動化解壓縮與結構優化)
7. [過版程式取得](#7-過版程式取得)
8. [原始代碼內容](#8-原始代碼內容)
9. [手動包版](#9-手動包版)
10. [其他事項](#10-其他事項)

---

## 包版環境

| 項目 | 版本 / 資訊 |
|------|------------|
| **Maven** | Apache Maven 3.9.6 (`bc0240f3c744dd6b6ec2920b3cd08dcc295161ae`) |
| **Maven Home** | `/usr/share/maven` |
| **Java** | 21.0.7，vendor: IBM Corporation |
| **JVM Runtime** | `/usr/lib/jvm/java-21-openjdk-ibm` |
| **Locale** | `zh_TW`，encoding: UTF-8 |
| **OS** | Linux Ubuntu，6.14.0-36-generic，amd64 |

---

## 1. 主要流程說明

腳本依序執行以下階段：

1. **參數定義與初始化** — 定義預設行為，解析使用者傳入的參數
2. **Git 倉庫管理** — 確保本地原始碼與遠端倉庫同步、處於乾淨狀態
3. **多模式 Maven 建置** — 根據選擇的模式執行對應的編譯指令
4. **產出物整理** — 將編譯完成的檔案彙整至 `bin` 資料夾
5. **自動化解壓縮與結構優化** — 處理壓縮檔並修正目錄層級
6. **後處理與通知** — 開啟檔案管理員顯示最終產出成果

---

## 2. 參數定義與初始化

### 2.1 選項說明

| 選項 | 說明 | 變數影響與 shift |
|------|------|----------------|
| `-fm` | 執行 `$FileManager` 所指向的程式，然後立即終止（exit 1） | 無 shift |
| `-help` | 執行 `usage()` 印出使用說明，然後立即終止 | 無 shift |
| `-np` | 設定 `GIT_PULL=false`，略過 Git Pull | shift 1 |
| `-r` | 設定 `GIT_RESET=true`，執行 Git Reset | shift 1 |
| `-lr <path>` | 設定 `REPO_PATH` 為指定路徑（**必填**） | shift 2 |
| `-b <branch>` | 設定 `BRANCH` 為指定分支名稱（**必填**） | shift 2 |
| `-Pwar` / `-web` / `-enclib` / `+web` / `-safeaa` | 設定 `BUILD_MODE` | shift 1 |
| `-f <file1,file2,...>` | 解析逗號分隔的檔案清單，加入 `UNZIP_FILES` 陣列 | shift 2 |
| `*` | 未知參數 → 輸出錯誤並 exit 1 | — |

### 2.2 `-f` 選項的特殊處理

```bash
-f)
  IFS=',' read -ra FILES <<< "$2"   # 以逗號為分隔符解析字串
  for f in "${FILES[@]}"; do
    UNZIP_FILES+=("$f")             # 將每個檔案名加入陣列
  done
  shift 2
  ;;
```

- `IFS=','` — 暫時將內部欄位分隔符設定為逗號
- `read -ra FILES` — 將輸入字串讀入陣列 `FILES`
- `<<< "$2"` — 將 `-f` 後面的值（如 `"fileA,fileB"`）作為輸入

### 2.3 總結

此段程式碼在腳本初期快速**識別、處理、消耗**所有命令列參數。透過 `shift` 指令在迴圈中不斷向前推進，確保每個參數都被正確處理。

---

## 3. Git 倉庫管理

進入 Maven 建置前，確保本地 Repository 處於正確且最新的狀態。

### 3.1 切換目錄與錯誤檢查

```bash
echo "切換至 repo 路徑：$REPO_PATH"
cd "$REPO_PATH" || { echo "錯誤：無法進入路徑 $REPO_PATH"; exit 1; }
```

- `||` 短路邏輯：`cd` 失敗時立即終止腳本，防止後續指令在錯誤路徑下執行

### 3.2 強制重置（Git Reset）

```bash
if [ "$GIT_RESET" = true ]; then
  echo "執行 git reset --hard"
  git reset --hard HEAD
fi
```

- 使用者指定 `-r` 時執行
- `git reset --hard HEAD` 將所有未提交修改強制刪除，確保環境乾淨，避免 `git pull` 衝突

### 3.3 更新程式碼（Git Pull）

```bash
if [ "$GIT_PULL" = true ]; then
  echo "取得 $BRANCH 最新版"
  git pull origin $BRANCH
else
  echo "已設定不執行 git pull"
fi
```

- 除非指定 `-np`（No Pull），否則預設從 `origin` 拉取指定分支的最新版

### 3.4 流程小結

| 步驟 | 目的 |
|------|------|
| `cd $REPO_PATH` | 確定位址，目錄不存在即中止 |
| `git reset --hard` | 清理環境，抹除本地殘留修改 |
| `git pull` | 同步最新程式碼 |

---

## 4. 多模式 Maven 建置

使用 `case` 語句根據 `$BUILD_MODE` 執行對應的建置模式。

### 4.1 模式一：`-Pwar`（建置 JAR + WAR）

```bash
-Pwar)
  cd ./source/fep
  mvn clean install -Pwar -f pom.xml
  cd $REPO_PATH/source/fep-war
  ;;
```

- `-Pwar` — 啟用名為 `war` 的 Maven Profile，打包成 `.war` 格式

### 4.2 模式二：`-web`（僅建置 fep-web WAR）

```bash
-web)
  cd ./source/fep
  mvn clean install -pl fep-web -Pwar -am -f pom.xml
  cd $REPO_PATH/source/fep-war
  MV_BIN=false
  ;;
```

- `-pl fep-web` — 僅建置指定模組 `fep-web`
- `-am` — 同時建置所有 `fep-web` 所依賴的模組

### 4.3 模式三：`-enclib`（僅建置 enclib）

```bash
-enclib)
  cd ./enclib/fep-enclib
  mvn clean install -pl enclib -am -f pom.xml
  MV_BIN=false
  ;;
```

> **注意：** 目前作法 PG 會先 commit `enclib.jar` 上傳 Git 更新，因此通常**不需要重新建置** enclib 模組。若需使用此模式，須另行 commit/push，避免 Remote 和 Local 的 `enclib.jar` 不同步。

### 4.4 模式四：`+web`（建置全部 + WAR）

```bash
+web)
  cd ./source/fep
  mvn clean install -pl fep-web -Pwar -am -f pom.xml  # 先建置 fep-web 及其依賴
  mvn clean install -f pom.xml                         # 再建置整個 fep 專案
  CP_WEB=true
  cd $REPO_PATH/source/fep-assembly
  ;;
```

- 執行兩次 `mvn` 命令：先建置特定模組，再建置整個父專案

### 4.5 模式五：`-safeaa`（建置 safeaa）

```bash
-safeaa)
  cd ./safeaa
  mvn clean install -f pom.xml
  MV_BIN=false
  ;;
```

### 4.6 模式六：`""`（預設完整建置）

```bash
"")
  cd ./source/fep
  mvn clean install -f pom.xml
  cd $REPO_PATH/source/fep-assembly
  ;;
```

- 未指定任何模式時，執行完整 fep 專案建置（僅 JAR，不含 WAR）

### 4.7 模式七：`*`（錯誤處理）

```bash
*)
  echo "錯誤：未知建置模式 $BUILD_MODE"
  exit 1
  ;;
```

### 4.8 建置模式對照表

| 模式 | 說明 | 產出 |
|------|------|------|
| `-Pwar` | JAR + WAR（fep-war profile） | JAR + WAR |
| `-web` | 只打包 fep-web | WAR only |
| `-enclib` | 只打包 enclib（不建議） | enclib.jar |
| `+web` | 全部服務 + WAR | JAR + WAR |
| `-safeaa` | 只打包 safeaa core | safeaa JAR |
| `(空白)` | 完整建置 | JAR only |

---

## 5. 產出物整理

將 Maven 建置完成的各種檔案收集至統一的 `bin` 資料夾。

### 5.1 建立並移動執行檔（MV_BIN 區塊）

```bash
if [ "$MV_BIN" = true ]; then
  mkdir -p bin
  find . -maxdepth 1 -type f -name '*bin*' -exec mv {} bin/ \;
  cd bin
fi
```

- `mkdir -p bin` — 建立 `bin` 目錄（已存在不報錯）
- `find ... -name '*bin*'` — 找出當前層所有檔名含 `bin` 的檔案並移入
- `cd bin` — 後續解壓縮操作直接在 `bin/` 下進行

> `-web`、`-enclib`、`-safeaa` 模式下 `MV_BIN=false`，不執行此區塊。

### 5.2 額外複製 Web 產出物（CP_WEB 區塊）

```bash
if [ "$CP_WEB" = true ]; then
  cp $REPO_PATH/source/fep-war/fep-web.war $REPO_PATH/source/fep-assembly/bin
fi
```

- 僅 `+web` 模式觸發（`CP_WEB=true`）
- 將 `fep-web.war` 複製到 `fep-assembly/bin/`

---

## 6. 自動化解壓縮與結構優化

處理 `-f` 參數傳入的 `.tar.gz` 壓縮檔，並執行目錄扁平化。

```bash
if [ ${#UNZIP_FILES[@]} -gt 0 ]; then
  for file in "${UNZIP_FILES[@]}"; do
    echo "解壓縮檔案：$file"
    tar -xzvf "$file"

    # 把 fep-app 裡面的資料夾往外搬
    inner_dir=$(find fep-app -mindepth 1 -maxdepth 1 -type d | head -n 1)
    mv "$inner_dir" .

    # 刪除空的 fep-app 資料夾
    rm -rf fep-app
  done
fi
```

### 扁平化流程

```
解壓前：  bin/
            └── fep-app/
                  └── 20230101_release/   ← 實際內容

解壓後：  bin/
            └── 20230101_release/         ← 搬出來
          (fep-app/ 空殼刪除)
```

| 指令 | 說明 |
|------|------|
| `tar -xzvf "$file"` | 解壓 `.tar.gz`，輸出至當前目錄 |
| `find fep-app -mindepth 1 -maxdepth 1 -type d \| head -n 1` | 找到 `fep-app/` 下第一個子目錄 |
| `mv "$inner_dir" .` | 將內部子目錄搬至當前層 |
| `rm -rf fep-app` | 刪除已清空的 `fep-app` 空殼 |

---

## 7. 過版程式取得

1. 切換到本次包版的本地 Repository
   - 例：`/home/eric/Git-projects/MGBFEP_1-2`

2. 複製 `bin/` 下解壓縮的模組資料或 WAR 檔
   - JAR 範例：`.../source/fep-assembly/bin/fep-server-atm`
   - WAR 範例：`.../source/fep-assembly/bin/fep-web.war`

3. 若需更新 config（properties）：切換至 `.../source/`，取得對應環境的 config（例如 SIT 套 config），**更新前務必比對既有 config 的差異**，避免覆蓋後造成錯誤。

4. 交付客戶前進行檔案清洗，再執行過版。

---

## 8. 原始代碼內容

```bash
#!/bin/bash
# 使用範例：
# MGBFEPbuild.sh -np -r -lr "/home/eric/Git-projects/MGBFEP_1-1" -b "FEP_1-1_SIT" +web -f fep-batch-bin.tar.gz,fep-service-bin-appmon.tar.gz
# MGBFEPbuild.sh -r -lr "/home/eric/Git-projects/MGBFEP_1-1" -b "FEP_1-1_SIT" -enclib

usage() {
  echo "參數使用方式(*爲必要參數)："
  echo "-np：略過git pull部驟"
  echo "-r：git reset hard 重設repo，清除衝突"
  echo "-lr <repo位置>：*指定本地repo的位置"
  echo "-b <分支名稱>：*指定遠端branch名稱"
  echo "包版方式參數說明(下列參數只能擇一)："
  echo "  -Pwar：打包 jar 檔外另外打包 war"
  echo "  -web：只打包web檔的war"
  echo "  -enclib：只打包enclib"
  echo "  -safeaa：只打包safeaa core"
  echo "  +web：打包全部服務並另外打包web"
  echo "  若未指定包版參數則會打包全部"
  echo "-f <檔案名稱,檔案名稱,...>：在 -f 參數後加上欲解壓縮的檔案名稱，使用逗號區分多個檔案"
  exit 1
}

FileManager="nautilus"

# 預設值
GIT_PULL=true
GIT_RESET=false
REPO_PATH="."
BRANCH="master"
BUILD_MODE=""
UNZIP_FILES=()
MV_BIN=true
CP_WEB=false

# 參數解析
while [ $# -gt 0 ]; do
  case "$1" in
    -fm)
      $FileManager
      exit 1
      ;;
    -help)
      usage
      exit 1
      ;;
    -np)
      GIT_PULL=false
      shift
      ;;
    -r)
      GIT_RESET=true
      shift
      ;;
    -lr)
      REPO_PATH="$2"
      REPO_PATH="${REPO_PATH/eric/user}"
      shift 2
      ;;
    -b)
      BRANCH="$2"
      shift 2
      ;;
    -Pwar|-web|-enclib|+web|-safeaa)
      BUILD_MODE="$1"
      shift
      ;;
    -f)
      IFS=',' read -ra FILES <<< "$2"
      for f in "${FILES[@]}"; do
        UNZIP_FILES+=("$f")
      done
      shift 2
      ;;
    *)
      echo "錯誤：未知參數 $1"
      exit 1
      ;;
  esac
done

echo "參數解析完成，開始 git 操作！"

# Git 操作區塊
echo "切換至 repo 路徑：$REPO_PATH"
cd "$REPO_PATH" || { echo "錯誤：無法進入路徑 $REPO_PATH"; exit 1; }

if [ "$GIT_RESET" = true ]; then
  echo "執行 git reset --hard"
  git reset --hard HEAD
fi

if [ "$GIT_PULL" = true ]; then
  echo "取得 $BRANCH 最新版"
  git pull origin $BRANCH
else
  echo "已設定不執行 git pull"
fi

echo "git 操作完成，開始建置"
pwd

# Maven 建置區塊
echo "開始 Maven 建置：$BUILD_MODE"
case "$BUILD_MODE" in
  -Pwar)
    cd ./source/fep
    mvn clean install -Pwar -f pom.xml
    cd $REPO_PATH/source/fep-war
    ;;
  -web)
    cd ./source/fep
    mvn clean install -pl fep-web -Pwar -am -f pom.xml
    cd $REPO_PATH/source/fep-war
    MV_BIN=false
    ;;
  -enclib)
    cd ./enclib/fep-enclib
    mvn clean install -pl enclib -am -f pom.xml
    MV_BIN=false
    ;;
  +web)
    cd ./source/fep
    mvn clean install -pl fep-web -Pwar -am -f pom.xml
    mvn clean install -f pom.xml
    CP_WEB=true
    cd $REPO_PATH/source/fep-assembly
    ;;
  -safeaa)
    cd ./safeaa
    mvn clean install -f pom.xml
    MV_BIN=false
    ;;
  "")
    cd ./source/fep
    mvn clean install -f pom.xml
    cd $REPO_PATH/source/fep-assembly
    ;;
  *)
    echo "錯誤：未知建置模式 $BUILD_MODE"
    exit 1
    ;;
esac

pwd
echo "建置完成"

# 將服務移動到 bin 資料夾
if [ "$MV_BIN" = true ]; then
  mkdir -p bin
  find . -maxdepth 1 -type f -name '*bin*' -exec mv {} bin/ \;
  cd bin
fi

# 複製 fep-web
if [ "$CP_WEB" = true ]; then
  cp $REPO_PATH/source/fep-war/fep-web.war $REPO_PATH/source/fep-assembly/bin
fi

pwd

# 解壓縮區塊
if [ ${#UNZIP_FILES[@]} -gt 0 ]; then
  for file in "${UNZIP_FILES[@]}"; do
    echo "解壓縮檔案：$file"
    tar -xzvf "$file"
    inner_dir=$(find fep-app -mindepth 1 -maxdepth 1 -type d | head -n 1)
    mv "$inner_dir" .
    rm -rf fep-app
  done
fi

$FileManager
```

---

## 9. 手動包版

> **注意所在的 Git 專案路徑和 Branch**

### 獨立模組包版（以 `fep-batch` 為例）

```bash
# 切換至模組目錄
cd source/fep/fep-batch

# 建置（-am 會連同相關依賴一同建置）
mvn clean install -am -f pom.xml
```

### 從專案根路徑包特定模組

```bash
# 切換至專案根目錄
cd source/fep

# 指定模組建置
mvn clean install -pl fep-batch -am -f pom.xml
```

### 包版產出物類型（含於 `.tar.gz` 中）

| 目錄 | 內容 | 用途 |
|------|------|------|
| `Bin/` | 模組 JAR、`application.properties`、`lib/*.jar` | 主要更版用 |
| `Cmd/` | `*.sh`、`*.bat` 執行腳本 | 參考用（各環境腳本另行取得） |
| `Config/` | `application-*.properties`、XML 設定檔 | 參考用（各環境 config 另行取得） |
| `War/` | `fep-web.war` | Web 伺服器部署用 |

### 設定檔取得位置

各環境的 `*.sh`、`properties` 設定檔位於 `source/` 路徑下：

- `SIT套config/`
- `UAT套config/`
- `正式套config/`

---

## 10. 其他事項

### `source/` 路徑下目錄結構

| 目錄 | 說明 |
|------|------|
| `fep/` | 主要 source code |
| `fep-assembly/` | 包版後**主要**放置位置（CI / 發版輸出，最終 tar.gz / 發佈檔） |
| `fep-assembly-batch-task/` | 批次程式包（可執行 JAR，排程用） |
| `fep-assembly-library/` | 共用函式庫包（供其他系統使用） |
| `fep-assembly-mybatis/` | DB 相關模組（DB schema 常與其他模組 release 不同步，故另外放置） |
| `fep-release-note/` | 各模組 release note |
| `fep-war/` | 網站 WAR 檔（web 層） |
| `SIT套config/` | SIT 環境設定檔 |
| `UAT套config/` | UAT 環境設定檔 |
| `正式套config/` | 正式環境設定檔 |
| `測試套config/` | 測試環境設定檔 |
| `開發套config/` | 開發環境設定檔 |
