#!/usr/bin/env bash
# fix-taildrop-send-tap.sh — 修复 iOS Taildrop 发送区点击无反应
#
# 上游 TaildropSendZone 在 iOS 把带 UITapGestureRecognizer 的 UIView 放在
# SwiftUI `.background` 里；Form/List 里前景的 Text/Image 会吃掉命中测试，
# 导致「能看见发送区/分享图标，点了没反应」。改成 `.overlay` 让 UIView 在
# 最上层同时接收点击与跨 App 拖放。
#
# 用法：fix-taildrop-send-tap.sh <clients/apple 目录>
# 退出码：0 已修补/已是正确形态/无此文件（旧客户端）；1 形态异常
set -euo pipefail

APPLE_DIR="${1:?usage: $0 <clients/apple>}"
TARGET="${APPLE_DIR}/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"

python3 - "$TARGET" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
if not path.is_file():
    print("skip taildrop tap fix: TaildropSendManager.swift not present")
    sys.exit(0)

text = path.read_text()
if "TaildropDropArea(" not in text:
    print("skip taildrop tap fix: TaildropDropArea not present")
    sys.exit(0)

overlay = re.compile(
    r"(label\s*\n\s*)\.overlay(\s*\{\s*\n\s*TaildropDropArea\()",
    re.MULTILINE,
)
background = re.compile(
    r"(label\s*\n\s*)\.background(\s*\{\s*\n\s*TaildropDropArea\()",
    re.MULTILINE,
)

if overlay.search(text):
    print("taildrop tap fix: already using .overlay")
    sys.exit(0)

if not background.search(text):
    sys.stderr.write(
        "taildrop tap fix: unexpected layout around TaildropDropArea\n"
    )
    sys.exit(1)

new, n = background.subn(r"\1.overlay\2", text, count=1)
if n != 1:
    sys.stderr.write(f"taildrop tap fix: expected 1 replacement, got {n}\n")
    sys.exit(1)

path.write_text(new)
print(f"taildrop tap fix: patched {path}")
PY
