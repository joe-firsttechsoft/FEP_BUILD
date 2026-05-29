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

# 預設收集旗標
COLLECT_JAR=true
COLLECT_WAR=false

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

# --- Maven 建置 ---
echo ""

if [ -n "$BUILD_MODULES" ]; then
    # ── 部分建置：只 build release note 指定的模組 ──────────────────
    echo "[Maven] 部分建置，模組：$BUILD_MODULES"
    cd "$REPO_PATH/source/fep"
    mvn clean install -pl "$BUILD_MODULES" -am -f pom.xml

    # 若模組包含 fep-web，額外建 WAR
    if echo "$BUILD_MODULES" | grep -q "fep-web"; then
        mvn clean install -pl fep-web -Pwar -am -f pom.xml
        COLLECT_WAR=true
    fi
else
    # ── 全 build：依 BUILD_MODE 執行 ────────────────────────────────
    echo "[Maven] 開始建置，模式：${BUILD_MODE:-(default)}"
case "$BUILD_MODE" in
    -Pwar)
        # 建置 JAR + WAR（fep-war profile）
        cd "$REPO_PATH/source/fep"
        mvn clean install -Pwar -f pom.xml
        COLLECT_WAR=true
        ;;
    -web)
        # 僅建置 fep-web WAR
        cd "$REPO_PATH/source/fep"
        mvn clean install -pl fep-web -Pwar -am -f pom.xml
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
        # 建置 fep-web + 完整專案
        cd "$REPO_PATH/source/fep"
        mvn clean install -pl fep-web -Pwar -am -f pom.xml
        mvn clean install -f pom.xml
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
        mvn clean install -f pom.xml
        ;;
    *)
        echo "錯誤：未知建置模式 '$BUILD_MODE'"
        echo "可用模式：-Pwar | -web | -enclib | +web | -safeaa | (空白=完整建置)"
        exit 1
        ;;
esac
fi  # end BUILD_MODULES / BUILD_MODE

# --- 收集產出物至 $CONTAINER_OUTPUT_PATH ---
echo ""
echo "[Output] 收集產出物至 $CONTAINER_OUTPUT_PATH"
mkdir -p "$CONTAINER_OUTPUT_PATH"
rm -rf "$CONTAINER_OUTPUT_PATH"/* 2>/dev/null || true

if [ "$COLLECT_JAR" = "true" ]; then
    ASSEMBLY_DIR="$REPO_PATH/source/fep-assembly"

    if [ -n "$BUILD_MODULES" ]; then
        # 部分建置：依模組前綴篩選，只收集本次有重新 build 的模組對應 tar.gz
        echo "[Output] 部分建置模式，依模組前綴篩選 tar.gz"
        IFS=',' read -ra MODULE_LIST <<< "$BUILD_MODULES"
        for module in "${MODULE_LIST[@]}"; do
            module=$(echo "$module" | xargs)  # trim whitespace
            for search_dir in \
                "$ASSEMBLY_DIR" \
                "$REPO_PATH/source/fep-assembly-batch-task" \
                "$REPO_PATH/source/fep-assembly-library" \
                "$REPO_PATH/source/fep-assembly-mybaits"; do
                if [ -d "$search_dir" ]; then
                    find "$search_dir" -maxdepth 3 -name "${module}*bin*.tar.gz" \
                        -exec cp -v {} "$CONTAINER_OUTPUT_PATH/" \;
                fi
            done
        done
    else
        # 全 build：收集全部 tar.gz
        if [ -d "$ASSEMBLY_DIR" ]; then
            find "$ASSEMBLY_DIR" -maxdepth 3 -name "*bin*.tar.gz" \
                -exec cp -v {} "$CONTAINER_OUTPUT_PATH/" \;
        fi
        for extra_dir in fep-assembly-batch-task fep-assembly-library fep-assembly-mybaits; do
            EXTRA="$REPO_PATH/source/$extra_dir"
            if [ -d "$EXTRA" ]; then
                find "$EXTRA" -maxdepth 3 -name "*bin*.tar.gz" \
                    -exec cp -v {} "$CONTAINER_OUTPUT_PATH/" \;
            fi
        done
    fi
fi

# fep-batch-task JAR 收集（部分建置且模組含 fep-batch-task 時）
if [ -n "$BUILD_MODULES" ] && echo "$BUILD_MODULES" | grep -qE "(^|,)\s*fep-batch-task(\s*,|$)"; then
    BATCH_TASK_TARGET="$REPO_PATH/source/fep/fep-batch-task/target"
    if [ -d "$BATCH_TASK_TARGET" ]; then
        echo "[Output] 收集 fep-batch-task JAR..."
        find "$BATCH_TASK_TARGET" -maxdepth 1 -name "fep-batch-task*.jar" \
            -exec cp -v {} "$CONTAINER_OUTPUT_PATH/" \;
    else
        echo "警告：找不到 $BATCH_TASK_TARGET"
    fi
fi

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
