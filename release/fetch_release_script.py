import requests
import pandas as pd
import io
import os
import sys
import re

def remove_quotes_in_braces(content):
    """
    掃描全文，移除 {...} 內的雙引號。
    {} 內的 " 會讓 regex 切割區塊斷裂，需在解析前先移除。
    回傳 (fixed_content, removed_count)
    """
    result = []
    brace_depth = 0
    removed = 0
    for c in content:
        if c == '{':
            brace_depth += 1
            result.append(c)
        elif c == '}':
            if brace_depth > 0:
                brace_depth -= 1
            result.append(c)
        elif c == '"' and brace_depth > 0:
            removed += 1  # {} 內的 " 直接略過
        else:
            result.append(c)
    return ''.join(result), removed


def validate_and_fix_script(content):
    """
    驗證並自動修正更新版號 script 格式。
    - {} 內的 " 自動移除（並給 warning）
    - 無法自動修正的問題才回報錯誤

    回傳 (fixed_content, warnings, errors)
    """
    warnings = []
    errors   = []

    # 前置處理：移除 {} 內的 "（避免 regex 把區塊切斷）
    content, removed_count = remove_quotes_in_braces(content)
    if removed_count > 0:
        warnings.append(f'內容中偵測到 {removed_count} 個在 {{}} 內的雙引號，已自動移除')

    # 無法自動修正：雙引號數量為奇數
    quote_count = content.count('"')
    if quote_count == 0:
        errors.append('找不到任何雙引號，內容格式不正確')
        return content, warnings, errors
    if quote_count % 2 != 0:
        errors.append(f'雙引號數量為奇數（共 {quote_count} 個），可能有未配對的引號')
        return content, warnings, errors

    # 逐區塊檢查
    block_index = [0]

    def fix_block(match):
        i = block_index[0] = block_index[0] + 1
        block = match.group(1)

        if '{' not in block or '}' not in block:
            errors.append(f'第 {i} 個區塊缺少 {{}}，無法解析：{block[:60]}')

        return match.group(0)

    fixed = re.sub(r'"(.*?)"', fix_block, content, flags=re.DOTALL)
    return fixed, warnings, errors

# =============================================
# 設定
# =============================================
SHARE_URL = "https://syscomo365-my.sharepoint.com/:x:/g/personal/824304_syscom_com_tw/IQAniQVtGImOSYhJ7EIBbKDSAXSZhyvoNhOxaDirzjT9JXk?rtime=IAjiXU9l3kg"
SHEET_NAME = "SIT UAT待過版"

# branch type → A 欄搜尋關鍵字
BRANCH_KEYWORD = {
    "1-3_SIT": "P1-3 SIT",
}
COL_V = 21  # V 欄（0-indexed）

def fetch_excel():
    """從 SharePoint 下載 Excel"""
    download_url = SHARE_URL + "&download=1"
    response = requests.get(download_url)
    response.raise_for_status()
    return response.content

def read_script(file_bytes, branch_type):
    """搜尋 A 欄找到對應 branch 的列，讀取 V 欄文字"""
    keyword = BRANCH_KEYWORD[branch_type]
    df = pd.read_excel(io.BytesIO(file_bytes), sheet_name=SHEET_NAME, header=None)

    col_a = df.iloc[:, 0].astype(str).str.strip()
    matched = col_a[col_a == keyword]

    if matched.empty:
        print(f"❌ 在 A 欄找不到「{keyword}」")
        return ""

    row = matched.index[0]
    print(f"    找到「{keyword}」於第 {row + 1} 列")
    value = df.iloc[row, COL_V]
    return str(value).strip() if pd.notna(value) else ""

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("1-3_SIT",):
        print("用法：python3 fetch_release_script.py 1-3_SIT")
        sys.exit(1)

    branch_type = sys.argv[1]
    output_file = os.environ.get("RELEASE_NOTE_INPUT", "ReleaseNoteUpdateData.txt")

    print(f"    下載 Excel...")
    file_bytes = fetch_excel()

    print(f"    讀取 {branch_type} 更新版號 script...")
    script = read_script(file_bytes, branch_type)

    if not script:
        print(f"❌ 錯誤：{branch_type} 欄位內容為空")
        sys.exit(1)

    # 格式驗證與自動修正
    script, warnings, errors = validate_and_fix_script(script)

    if warnings:
        print("\n🔧 已自動修正以下問題：")
        for w in warnings:
            print(f"  ⚠️  {w}")

    if errors:
        print("\n❌ 以下問題無法自動修正，請修正 Excel 後重新執行：")
        for err in errors:
            print(f"  {err}")
        sys.exit(1)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(script)

    print(f"✅ 已寫入 {output_file}：")
    print(script)

if __name__ == "__main__":
    main()
