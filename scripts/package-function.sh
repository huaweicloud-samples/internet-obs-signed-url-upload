#!/usr/bin/env bash
# 把函数代码与运行时依赖打成 FunctionGraph 可直接使用的 zip。
# 产物：build/issue-upload-url.zip（Terraform 以 func_code 读取）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUNC_DIR="$ROOT/src/functions/issue-upload-url"
BUILD_DIR="$ROOT/build"
ZIP_FILE="$BUILD_DIR/issue-upload-url.zip"

command -v npm >/dev/null 2>&1 || { echo "npm not found" >&2; exit 1; }
command -v python >/dev/null 2>&1 || { echo "python not found" >&2; exit 1; }

echo "[1/3] 安装运行时依赖到函数目录"
(cd "$FUNC_DIR" && npm install --omit=dev --no-audit --no-fund --loglevel=error)

echo "[2/3] 打包 index.js / package.json / node_modules"
mkdir -p "$BUILD_DIR"
python - "$FUNC_DIR" "$ZIP_FILE" <<'PY'
import os
import sys
import zipfile

func_dir, zip_path = sys.argv[1], sys.argv[2]
skip_dirs = {'.git', '__pycache__', '.terraform'}
if os.path.exists(zip_path):
    os.remove(zip_path)

count = 0
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for base, dirs, files in os.walk(func_dir):
        dirs[:] = sorted(d for d in dirs if d not in skip_dirs)
        for name in sorted(files):
            full = os.path.join(base, name)
            if name.endswith(('.log', '.tmp', '.zip')):
                continue
            arc = os.path.relpath(full, func_dir).replace(os.sep, '/')
            zf.write(full, arc)
            count += 1
print('  files=%d' % count)
PY

echo "[3/3] 完成"
ls -lh "$ZIP_FILE"
echo "ZIP=$ZIP_FILE"
