#!/usr/bin/env bash
# fix-taildrop-send-tap.sh — 修复 iOS 应用内 Taildrop 发送区点击无反应
#
# 上游 iOS 只靠 TaildropDropArea（UIViewRepresentable）的 UITapGestureRecognizer，
# 塞进 Form/List 行的 .background/.overlay。前景 Text 吃掉命中，UIView 也常收成
# 0 尺寸 → 「看得到发送区，点了没反应」。
#
# 修复：iOS 与 macOS 一样用 SwiftUI Button 打开 fileImporter；DropArea 仍放在
# label 的 background，只负责跨 App 拖放。
#
# 用法：fix-taildrop-send-tap.sh <clients/apple 目录>
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

marker = "/* cursor-taildrop-send-tap-fix */"
if marker in text:
    print("taildrop tap fix: already applied")
    sys.exit(0)

# iOS 分支：#else … private var zone … TaildropDropArea … #endif
zone_pat = re.compile(
    r"[ \t]*#else\n[ \t]*private var zone: some View \{.*?\n[ \t]*#endif",
    re.DOTALL,
)

matches = [m for m in zone_pat.finditer(text) if "TaildropDropArea(" in m.group(0)]
if len(matches) != 1:
    sys.stderr.write(
        f"taildrop tap fix: expected 1 TaildropDropArea zone, got {len(matches)}\n"
    )
    sys.exit(1)

replacement = r"""        #else
            /* cursor-taildrop-send-tap-fix */
            private var zone: some View {
                Button {
                    importerPresented = true
                } label: {
                    label
                        .contentShape(Rectangle())
                        .background {
                            TaildropDropArea(
                                onTargeted: { targeted in
                                    dropTargeted = targeted
                                },
                                onTap: {
                                    importerPresented = true
                                },
                                onFiles: { files, firstError in
                                    if files.isEmpty, let firstError {
                                        alert = AlertState(action: "receive dropped files", error: firstError)
                                        return
                                    }
                                    send(files.map(\.url), temporaryDirectories: files.compactMap(\.temporaryDirectory))
                                }
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        #endif"""

m = matches[0]
new = text[: m.start()] + replacement + text[m.end() :]
path.write_text(new)
print(f"taildrop tap fix: patched {path}")
PY
