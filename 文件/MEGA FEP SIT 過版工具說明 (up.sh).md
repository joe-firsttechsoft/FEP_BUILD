# MEGA FEP SIT 過版工具說明 — up.sh

> **Program Author:** Eric Chen　|　**Documentation:** CH Chuang
>
> **SIT 環境腳本路徑：** `/fepap/fep-app/test/up.sh`

---

## 目錄

1. [主要流程說明](#1-主要流程說明)
2. [腳本開頭設定](#2-腳本開頭設定)
3. [變數定義](#3-變數定義)
4. [核心迴圈：遍歷服務目錄](#4-核心迴圈遍歷服務目錄)
5. [讀取版本號與備份路徑建立](#5-讀取版本號與備份路徑建立)
6. [備份運行中的程式碼](#6-備份運行中的程式碼)
7. [停止服務](#7-停止服務)
8. [更新程式碼（部署）](#8-更新程式碼部署)
9. [啟動服務](#9-啟動服務)
10. [清理臨時檔案](#10-清理臨時檔案)
11. [總結功能](#11-總結功能)
12. [原始代碼內容](#12-原始代碼內容)

---

## 1. 主要流程說明

### 1.1 運行環境與安全設定

- **主要目的：** 設定腳本執行行為，確保穩定性與錯誤追蹤
- **關鍵功能：**
  - `set -e` — 遇到任何錯誤立即停止執行，防止錯誤擴大
  - `set -o pipefail` — 確保管道指令中任何一段失敗都會被偵測到
  - 定義路徑變數（來源、目標、備份區）及日期格式

### 1.2 服務迭代處理迴圈

- **主要目的：** 遍歷更新包目錄（`TARGET_DIR`），對每個子資料夾（代表一個服務）進行處理
- **關鍵功能：**
  - 提取服務名稱，將 `-` 轉為 `_` 以匹配腳本命名慣例
  - **版本識別：** 讀取部署區 `readme.txt` 第三行取得當前版本號，作為備份資料夾名稱

### 1.3 預更新備份

- **主要目的：** 在覆蓋程式碼前，完整備份當前運行的舊版環境
- **關鍵功能：**
  - 根據版本號（或當前日期）建立備份目錄
  - 執行 `cp -r` 備份；若備份失敗則強制中斷腳本

### 1.4 服務生命週期管理

- **主要目的：** 執行標準的「停、換、啟」部署動作
- **關鍵功能：**
  - **停止：** 自動尋找並執行該服務的 `_stop.sh` 腳本
  - **更新：** 將新版程式碼從 `TARGET_DIR` 複製並覆蓋至 `DEPLOY_DIR`
  - **啟動：** 執行該服務的 `_start.sh` 腳本恢復服務運作

### 1.5 互動式環境清理

- **主要目的：** 所有服務處理完畢後，引導使用者清理臨時檔案
- **關鍵功能：**
  - 列出當前目錄下所有子資料夾
  - 要求使用者輸入 `y/N` 確認，避免誤刪
  - 執行 `rm -r` 清理解壓目錄或臨時檔

---

## 2. 腳本開頭設定

```bash
#!/bin/bash
set -e
set -o pipefail
```

| 設定 | 說明 |
|------|------|
| `#!/bin/bash` | 指定使用 Bash Shell 執行 |
| `set -e` | 任何命令以非零狀態退出，腳本立即終止 |
| `set -o pipefail` | 管道（`\|`）中任何命令失敗，整個管道命令也視為失敗 |

---

## 3. 變數定義

```bash
TARGET_DIR="/fepap/fep-app/test"   # 存放新版程式碼的暫存目錄
BACKUP_DIR="/fepap/fep-app/bk"     # 備份目錄
DEPLOY_DIR="/fepap/fep-app"        # 正在運行的程式碼目錄
today=$(date +"%Y-%m-%d")          # 今天日期（YYYY-MM-DD），備份路徑備用
UPDATE_RESULT="0"                   # 更新結果旗標（預留）
```

| 變數 | 路徑 | 用途 |
|------|------|------|
| `TARGET_DIR` | `/fepap/fep-app/test` | 新版程式碼暫存區 |
| `BACKUP_DIR` | `/fepap/fep-app/bk` | 舊版備份區 |
| `DEPLOY_DIR` | `/fepap/fep-app` | 正在運行的服務目錄 |

---

## 4. 核心迴圈：遍歷服務目錄

```bash
for dir in "$TARGET_DIR"/*/; do
  if [ -d "$dir" ]; then
    service_dir=$(basename "$dir")
    service_name=$(echo "$service_dir" | tr '-' '_')
    # ... 服務處理邏輯 ...
  fi
done
```

- `service_dir` — 取得子目錄名稱，作為**服務目錄名**（例如：`fep-api`）
- `service_name` — 將 `-` 替換為 `_`，作為**腳本名稱**的一部分（例如：`fep_api`）

---

## 5. 讀取版本號與備份路徑建立

```bash
readme_file="$DEPLOY_DIR/$service_dir/readme.txt"

if [ -f "$readme_file" ]; then
  version=$(sed -n '3p' "$readme_file" | sed 's/\[ver\]//')  # 讀取第 3 行，移除 [ver] 標籤
else
  version=''
  echo "⚠️ 找不到 $readme_file，無法取得版本號" >&2
fi

if [ -n "$version" ]; then
  backup_path="$BACKUP_DIR/$service_dir/$version"  # 以版本號命名備份目錄
else
  backup_path="$BACKUP_DIR/$service_dir/$today"    # 無版本號時以日期命名
fi

mkdir -p "$backup_path"
```

- 從 `DEPLOY_DIR` 下的 `readme.txt` **第三行**讀取版本資訊
- 建立對應的備份目錄（有版本號用版號，否則用日期）

---

## 6. 備份運行中的程式碼

```bash
echo "🛡️ 正在備份：$service_dir（版本 $version）..."

if cp -r "$DEPLOY_DIR/$service_dir" "$backup_path"; then
  echo "✅ 備份完成：$backup_path"
else
  echo "❌ 備份失敗：$service_dir" >&2
  exit 1   # 備份失敗，腳本終止，不執行更新
fi
```

- `cp -r` 遞迴複製當前服務目錄至備份路徑
- 備份失敗時立即終止，**確保在備份成功前絕不進行更新**

---

## 7. 停止服務

```bash
stop_script="$DEPLOY_DIR/$service_dir/${service_name}_stop.sh"

if [ -f "$stop_script" ]; then
  echo "🛑 停止服務：$service_dir"
  sh "$stop_script"
else
  echo "⚠️ 找不到停止腳本：$stop_script"
fi
```

- 預期腳本位於服務目錄內，命名格式：`{service_name}_stop.sh`
  - 例：`fep_api_stop.sh`

---

## 8. 更新程式碼（部署）

```bash
echo "📦 正在更新：$service_dir ..."

if cp -r "$TARGET_DIR/$service_dir" "$DEPLOY_DIR"; then
  echo "✅ 更新完成：$service_dir"
else
  echo "❌ 更新失敗：$service_dir" >&2
  exit 1
fi
```

- 將 `TARGET_DIR` 下的新版程式碼**複製覆蓋**至 `DEPLOY_DIR`
- 因目錄同名，新版本直接取代舊版本

---

## 9. 啟動服務

```bash
start_script="$DEPLOY_DIR/$service_dir/${service_name}_start.sh"

if [ -f "$start_script" ]; then
  echo "🚀 啟動服務：$service_dir"
  sh "$start_script"
else
  echo "⚠️ 找不到啟動腳本：$start_script"
fi
```

- 預期腳本位於服務目錄內，命名格式：`{service_name}_start.sh`
  - 例：`fep_api_start.sh`

---

## 10. 清理臨時檔案

```bash
echo "-----------------------------"
echo "所有更新均已完成！"
echo "正在檢查 $TARGET_DIR 中的臨時資料夾..."

if [ -n "$(ls -A "$TARGET_DIR")" ]; then
  echo "以下資料夾將被刪除："
  ls -d "$TARGET_DIR"/*/ 2>/dev/null || echo "（無子目錄）"
  echo "是否確定要刪除這些資料夾？(y/N): \c"
  read confirm

  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$TARGET_DIR"/*/
    echo "✅ 臨時資料夾已刪除。"
  else
    echo "💡 已保留資料夾，請手動確認是否需要清理。"
  fi
else
  echo "✨ 沒有需要清理的子目錄。"
fi

echo "🎉 所有處理程序結束！"
```

### 設計要點

| 機制 | 說明 |
|------|------|
| 路徑顯式化 | 使用 `"$TARGET_DIR"/*/` 確保只操作該目錄下的內容 |
| 正則確認 | `[[ "$confirm" =~ ^[Yy]$ ]]` 支援大小寫輸入 |
| 防呆機制 | 先用 `ls -A` 確認目錄有內容，避免對空目錄執行刪除邏輯 |

---

## 11. 總結功能

`up.sh` 是一個**半自動化的服務熱更新工具**，完整部署流程如下：

```
新版程式放入 TARGET_DIR
        ↓
讀取版本號，建立備份目錄
        ↓
備份舊版 (DEPLOY_DIR → BACKUP_DIR)
        ↓
停止服務 (_stop.sh)
        ↓
複製新版 (TARGET_DIR → DEPLOY_DIR)
        ↓
啟動服務 (_start.sh)
        ↓
詢問是否清理 TARGET_DIR 暫存
```

---

## 12. 原始代碼內容

```bash
#!/bin/bash
set -e
set -o pipefail

TARGET_DIR="/fepap/fep-app/test"
BACKUP_DIR="/fepap/fep-app/bk"
DEPLOY_DIR="/fepap/fep-app"
today=$(date +"%Y-%m-%d")
UPDATE_RESULT="0"

echo "📁 子目錄列表："
for dir in "$TARGET_DIR"/*/; do
  if [ -d "$dir" ]; then
    service_dir=$(basename "$dir")
    service_name=$(echo "$service_dir" | tr '-' '_')

    # 讀取版本號：readme.txt 的第 3 行
    readme_file="$DEPLOY_DIR/$service_dir/readme.txt"
    if [ -f "$readme_file" ]; then
      version=$(sed -n '3p' "$readme_file" | sed 's/\[ver\]//')
    else
      version=''
      echo "⚠️ 找不到 $readme_file，無法取得版本號" >&2
    fi

    # 建立版本號備份目錄
    if [ -n "$version" ]; then
      backup_path="$BACKUP_DIR/$service_dir/$version"
    else
      backup_path="$BACKUP_DIR/$service_dir/$today"
    fi
    mkdir -p "$backup_path"

    echo "🛡️ 正在備份：$service_dir（版本 $version）..."
    if cp -r "$DEPLOY_DIR/$service_dir" "$backup_path"; then
      echo "✅ 備份完成：$backup_path"
    else
      echo "❌ 備份失敗：$service_dir" >&2
      exit 1
    fi

    # 停止服務
    stop_script="$DEPLOY_DIR/$service_dir/${service_name}_stop.sh"
    if [ -f "$stop_script" ]; then
      echo "🛑 停止服務：$service_dir"
      sh "$stop_script"
    else
      echo "⚠️ 找不到停止腳本：$stop_script"
    fi

    # 更新程式碼
    echo "📦 正在更新：$service_dir ..."
    if cp -r "$TARGET_DIR/$service_dir" "$DEPLOY_DIR"; then
      echo "✅ 更新完成：$service_dir"
    else
      echo "❌ 更新失敗：$service_dir" >&2
      exit 1
    fi

    # 啟動服務
    start_script="$DEPLOY_DIR/$service_dir/${service_name}_start.sh"
    if [ -f "$start_script" ]; then
      echo "🚀 啟動服務：$service_dir"
      sh "$start_script"
    else
      echo "⚠️ 找不到啟動腳本：$start_script"
    fi

    echo "✅ 已完成處理：$service_dir"
    echo "-----------------------------"
  fi
done

echo "-----------------------------"
echo "所有更新均已完成！"
echo "正在檢查 $TARGET_DIR 中的臨時資料夾..."

if [ -n "$(ls -A "$TARGET_DIR")" ]; then
  echo "以下資料夾將被刪除："
  ls -d "$TARGET_DIR"/*/ 2>/dev/null || echo "（無子目錄）"
  echo "是否確定要刪除這些資料夾？(y/N): \c"
  read confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$TARGET_DIR"/*/
    echo "✅ 臨時資料夾已刪除。"
  else
    echo "💡 已保留資料夾，請手動確認是否需要清理。"
  fi
else
  echo "✨ 沒有需要清理的子目錄。"
fi

echo "🎉 所有處理程序結束！"
```
