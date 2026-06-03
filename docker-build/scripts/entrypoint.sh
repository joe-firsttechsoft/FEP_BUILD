#!/bin/bash
set -euo pipefail

REPO_PATH="${REPO_PATH:-/workspace/repo}"
BRANCH="${BRANCH:-master}"
BUILD_MODE="${BUILD_MODE:-}"
BUILD_MODULES="${BUILD_MODULES:-}"  # 部分建置：逗號分隔的 Maven 模組清單（由 run.ps1 自動帶入）
GIT_PULL="${GIT_PULL:-false}"
GIT_RESET="${GIT_RESET:-false}"

CONTAINER_OUTPUT_PATH="${CONTAINER_OUTPUT_PATH:-/build/output}" # container 內掛載路徑，從 .env 傳入
HOST_OUTPUT_PATH="${HOST_OUTPUT_PATH}"                          # host 端路徑，從 .env 傳入，僅用於最終顯示

export COPYFILE_DISABLE=1  # 避免 macOS 在 exFAT 上建立 ._ resource fork 檔案

# 預設收集旗標
COLLECT_JAR=true
COLLECT_WAR=false

# Maven assembly 直接輸出到 container output 目錄，省略複製步驟
ASSEMBLY_PROPS="-Dassembly-output-path=$CONTAINER_OUTPUT_PATH -Dassembly-batch-task-output-path=$CONTAINER_OUTPUT_PATH"

echo "================================================"
echo " FEP Build Container"
echo "================================================"
echo " Repo    : $REPO_PATH"
echo " Branch  : $BRANCH"
echo " Mode    : ${BUILD_MODULES:+partial($BUILD_MODULES)}${BUILD_MODULES:-${BUILD_MODE:-(default, 完整建置)}}"
echo " Git Pull: $GIT_PULL | Git Reset: $GIT_RESET"
echo "================================================"

# --- 切換到 repo 目錄 ---
cd "$REPO_PATH" || { echo "錯誤：無法進入 $REPO_PATH"; exit 1; }

# --- Git 操作 ---
if [ "$GIT_RESET" = "true" ]; then
    echo "[Git] 執行 git reset --hard HEAD"
    git reset --hard HEAD
fi

if [ "$GIT_PULL" = "true" ]; then
    echo "[Git] 拉取 $BRANCH 最新版"
    git pull origin "$BRANCH"
else
    echo "[Git] 已略過 git pull（GIT_PULL=false）"
fi

# --- 清空輸出目錄（在 build 前，因為 assembly 直接輸出至此） ---
echo ""
echo "[Output] 清空輸出目錄 $CONTAINER_OUTPUT_PATH"
mkdir -p "$CONTAINER_OUTPUT_PATH"
rm -rf "$CONTAINER_OUTPUT_PATH"/* 2>/dev/null || true

# --- Maven 建置 ---
echo ""

if [ -n "$BUILD_MODULES" ]; then
    # ── 部分建置：只 build release note 指定的模組 ──────────────────
    echo "[Maven] 部分建置，模組：$BUILD_MODULES"
    cd "$REPO_PATH/source/fep"
    mvn clean install -pl "$BUILD_MODULES" -am $ASSEMBLY_PROPS -f pom.xml

    # 若模組包含 fep-web，額外建 WAR
    if echo "$BUILD_MODULES" | grep -q "fep-web"; then
        mvn clean install -pl fep-web -Pwar -am $ASSEMBLY_PROPS -f pom.xml
        COLLECT_WAR=true
    fi
else
    # ── 全 build：依 BUILD_MODE 執行 ────────────────────────────────
    echo "[Maven] 開始建置，模式：${BUILD_MODE:-(default)}"
case "$BUILD_MODE" in
    -Pwar)
        # 建置 JAR + WAR（fep-war profile）
        cd "$REPO_PATH/source/fep"
        mvn clean install -Pwar $ASSEMBLY_PROPS -f pom.xml
        COLLECT_WAR=true
        ;;
    -web)
        # 僅建置 fep-web WAR
        cd "$REPO_PATH/source/fep"
        mvn clean install -pl fep-web -Pwar -am $ASSEMBLY_PROPS -f pom.xml
        COLLECT_JAR=false
        COLLECT_WAR=true
        ;;
    -enclib)
        # 僅建置 enclib 模組（一般不需重新建，由 PG commit enclib.jar 即可）
        cd "$REPO_PATH/enclib/fep-enclib"
        mvn clean install -pl enclib -am -f pom.xml
        COLLECT_JAR=false
        ;;
    +web)
        # 建置完整專案，再補 WAR（先全 build 再 install WAR，避免 clean 刪除 WAR）
        cd "$REPO_PATH/source/fep"
        mvn clean install $ASSEMBLY_PROPS -f pom.xml
        mvn install -pl fep-web -Pwar -am $ASSEMBLY_PROPS -f pom.xml
        COLLECT_WAR=true
        ;;
    -safeaa)
        # 僅建置 safeaa 模組
        cd "$REPO_PATH/safeaa"
        mvn clean install -f pom.xml
        COLLECT_JAR=false
        ;;
    "")
        # 預設：完整建置 fep 專案（僅 JAR）
        cd "$REPO_PATH/source/fep"
        mvn clean install $ASSEMBLY_PROPS -f pom.xml
        ;;
    *)
        echo "錯誤：未知建置模式 '$BUILD_MODE'"
        echo "可用模式：-Pwar | -web | -enclib | +web | -safeaa | (空白=完整建置)"
        exit 1
        ;;
esac
fi  # end BUILD_MODULES / BUILD_MODE

# --- Batch-task JAR 收集（保底：從 fep-assembly-batch-task 明確複製）---
if [ "$COLLECT_JAR" = "true" ]; then
    BATCH_TASK_DIR="$REPO_PATH/source/fep-assembly-batch-task"
    if [ -d "$BATCH_TASK_DIR" ]; then
        JAR_COUNT=$(find "$BATCH_TASK_DIR" -maxdepth 1 -name "fep-batch-task*.jar" | wc -l)
        if [ "$JAR_COUNT" -gt 0 ]; then
            echo "[Output] 收集 fep-batch-task JAR（$JAR_COUNT 個）..."
            find "$BATCH_TASK_DIR" -maxdepth 1 -name "fep-batch-task*.jar" \
                -exec cp -v {} "$CONTAINER_OUTPUT_PATH/" \;
        fi
    fi
fi

# --- WAR 收集 ---
if [ "$COLLECT_WAR" = "true" ]; then
    WAR_FILE="$REPO_PATH/source/fep-war/fep-web.war"
    if [ -f "$WAR_FILE" ]; then
        cp -v "$WAR_FILE" "$CONTAINER_OUTPUT_PATH/"
    else
        echo "警告：找不到 $WAR_FILE"
    fi
fi

echo ""
echo "================================================"
echo " 建置完成！產出物列表："
ls -lh "$CONTAINER_OUTPUT_PATH/"
echo " Host 路徑：${HOST_OUTPUT_PATH}"
echo "================================================"
