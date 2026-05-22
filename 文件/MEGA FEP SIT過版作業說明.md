# MEGA FEP 專案 SIT 過版作業說明

> 以系統模組為單位進行過版作業

---

## 目錄

1. [程序概述](#1-程序概述)
2. [Web 過版](#2-web-過版)
3. [程式過版](#3-程式過版)
4. [其他事項](#4-其他事項)

---

## 1. 程序概述

### 過版程序

```
備份模組 → 停止服務 → 過版更新 → 啟動服務 → 確認服務
```

### 退版程序

```
停止服務 → 備份更回 → 啟動服務 → 確認服務
```

---

## 2. Web 過版

**環境：** FEP-Web `172.29.98.11`（user: `wasadmin`）

### 過版步驟

1. 將 `fep-web.war` 更名為非 `.war` 結尾，例如 `fep-web.war0`（避免衝突）
2. 切換至 WAR 放置路徑：`/wlp/usr/servers/fepserver1/apps`
3. 將更名後的 WAR 檔複製到 `apps/` 路徑下
4. 停止 Web 服務：
   ```bash
   /wlp/bin/server stop fepserver1
   ```
5. 確認網頁已停止回應
6. 將 `apps/` 下原有的 `fep-web.war` 備份更名（例如：`fep-web.war.1204`）
7. 重新啟動 Web 服務：
   ```bash
   /wlp/bin/server start fepserver1
   ```
8. 確認網頁是否已恢復服務

---

## 3. 程式過版

根據預定過版模組，決定要上傳的主機。

### 環境主機

| 環境 | IP | 帳號 |
|------|-----|------|
| FEP-AP | `172.29.98.11` | `fepap` |
| FEP-GW | `172.29.98.17` | `fepap` |
| FEP-ATM-GW | `172.29.98.15` | `fepap` |

### 過版步驟

1. 切換至 test 目錄：
   ```bash
   cd /fepap/fep-app/test
   ```
2. 將整個模組資料夾複製到 `test/` 路徑下：
   ```
   /fepap/fep-app/test/fep-server-atm
   ```
3. 執行 `up.sh`（自動完成：停止服務 → 備份 → 更新 → 重新啟動 → 刪除更新暫存）：
   ```bash
   ./up.sh
   ```
4. 完成後，開啟 Web 確認服務是否正常運行：
   **系統管理 → 系統及服務監控**

### 版本備份路徑

```
/fepap/fep-app/bk
```

### 退版方式

1. 至備份路徑取出欲退回的版本資料夾
2. 複製至 `test/` 路徑下
3. 將資料夾名稱（通常是版號）改回模組名稱（例如：`fep-server-atm`）
4. 再次執行 `up.sh` 完成退版

---

## 4. 其他事項

### cmdline 類型模組

此類模組屬於被調用執行，無須執行關閉或啟動，**手動備份/覆蓋**即可。

**手動過版流程：**

一般模組內會有 `start` / `stop` 的 shell script，手動更版步驟：

```
停服務(stop) → 備份 → 更版 → 起服務(start) → 確認狀態
```

---

### 設定檔變更

1. 切換至設定檔目錄：
   ```bash
   cd /fepap/fep-app/config
   ```
2. 備份指定設定檔：
   ```bash
   cp application.properties application.properties_20241204
   ```
3. 覆蓋指定設定檔
4. 重新啟動指定服務

---

### 問題查測

遇到啟動失敗（log 未產生）時，可直接下 Java 啟動指令查看輸出：

```bash
# 前景執行（可直接看到錯誤訊息）
java -jar -Dfile.encoding=UTF-8 \
  /home/fepap/fep-app2/fep-gateway-atm/fep-gateway-atm.jar

# 背景執行
nohup java -jar -Dfile.encoding=UTF-8 \
  /home/fepap/fep-app/fep-gateway-atm/fep-gateway-atm.jar \
  > /dev/null 2>&1 &
```

> 其他特殊更版狀況，另行提供更版說明。
