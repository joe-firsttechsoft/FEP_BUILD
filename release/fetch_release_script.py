import requests
import pandas as pd
import io
import os
import sys
import re

def validate_and_fix_script(content):
    """
    驗證並自動修正更新版號 script 格式。
    - {} 內的 " 自動移除（並給 warning）
    - 無法自動修正的問題才回報錯誤

    回傳 (fixed_content, warnings, errors)
    """
    warnings = []
    errors   = []

    # 無法自動修正：雙引號數量為奇數
    quote_count = content.count('"')
    if quote_count == 0:
        errors.append('找不到任何雙引號，內容格式不正確')
        return content, warnings, errors
    if quote_count % 2 != 0:
        errors.append(f'雙引號數量為奇數（共 {quote_count} 個），可能有未配對的引號')
        return content, warnings, errors

    # 逐區塊檢查，用 re.sub 搭配函式做原位修正
    block_index = [0]  # 用 list 讓 closure 可以修改

    def fix_block(match):
        i = block_index[0] = block_index[0] + 1
        block = match.group(1)

        # 無法自動修正：缺少 {}
        if '{' not in block or '}' not in block:
            errors.append(f'第 {i} 個區塊缺少 {{}}，無法解析：{block[:60]}')
            return match.group(0)

        brace_start   = block.index('{')
        brace_end     = block.rindex('}')
        brace_content = block[brace_start + 1:brace_end]

        # 自動修正：移除 {} 內的 "
        if '"' in brace_content:
            fixed_content = brace_content.replace('"', '')
            warnings.append(f'第 {i} 個區塊 {{}} 內含有雙引號，已自動移除\n'
                            f'  原始：{brace_content[:80]}\n'
                            f'  修正：{fixed_content[:80]}')
            fixed_block = block[:brace_start + 1] + fixed_content + block[brace_end:]
            return f'"{fixed_block}"'

        return match.group(0)

    fixed = re.sub(r'"(.*?)"', fix_block, content, flags=re.DOTALL)
    return fixed, warnings, errors

# =============================================
# 設定
# =============================================
SHARE_URL = "https://syscomo365-my.sharepoint.com/:x:/g/personal/824304_syscom_com_tw/IQAniQVtGImOSYhJ7EIBbKDSAXSZhyvoNhOxaDirzjT9JXk?rtime=IAjiXU9l3kg"
SHEET_NAME = "SIT UAT待過版"

# branch type → Excel 儲存格（0-indexed: V=21, row 24→23, row 36→35）
BRANCH_CELL = {
    "SIT": (23, 21),  # V24
    "UAT": (35, 21),  # V36
}

def fetch_excel():
    """從 SharePoint 下載 Excel"""
    download_url = SHARE_URL + "&download=1"
    response = requests.get(download_url)
    response.raise_for_status()
    return response.content

def read_script(file_bytes, branch_type):
    """讀取對應 branch 的更新版號 script"""
    row, col = BRANCH_CELL[branch_type]
    df = pd.read_excel(io.BytesIO(file_bytes), sheet_name=SHEET_NAME, header=None)
    value = df.iloc[row, col]
    return str(value).strip() if pd.notna(value) else ""

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("SIT", "UAT"):
        print("用法：python3 fetch_release_script.py SIT|UAT")
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
