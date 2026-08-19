#!/usr/bin/env bash
# fix-taildrop-send-tap.sh — 修复 iOS 应用内 Taildrop 发送区点击无反应
#
# v4：Button + UIKit UIDocumentPicker；DropArea.onTap 置空 + present 防重入，
#     避免一次点击弹出两个文件选择器。
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

marker_v4 = "/* cursor-taildrop-send-tap-fix-v4 */"
if marker_v4 in text and "isPresenting" in text:
    print("taildrop tap fix: already applied (v4)")
    sys.exit(0)

broken = re.compile(
    r"zone\n#if !os\(iOS\)\n"
    r"(                \.fileImporter\([\s\S]*?)"
    r"                    \}\n#endif\n"
    r"(                \}\n)",
    re.MULTILINE,
)
text2, n = broken.subn(r"zone\n\1                    }\n\2", text, count=1)
if n:
    text = text2
    print("taildrop tap fix: repaired broken v2 fileImporter wrap")

if "documentPickerBridge" not in text:
    state_anchor = "        @State private var alert: AlertState?\n"
    if state_anchor not in text:
        sys.stderr.write("taildrop tap fix: cannot find @State alert anchor\n")
        sys.exit(1)
    text = text.replace(
        state_anchor,
        state_anchor
        + "        #if os(iOS)\n"
        + "            @State private var documentPickerBridge = TaildropDocumentPickerBridge()\n"
        + "        #endif\n",
        1,
    )

zone_pat = re.compile(
    r"[ \t]*#else\n[ \t]*(?:/\* cursor-taildrop-send-tap-fix(?:-v[234])? \*/\n[ \t]*)?"
    r"(?:@State private var documentPickerBridge = TaildropDocumentPickerBridge\(\)\n[ \t]*)?"
    r"private var zone: some View \{.*?\n[ \t]*#endif",
    re.DOTALL,
)
matches = [m for m in zone_pat.finditer(text) if "TaildropDropArea(" in m.group(0)]
if len(matches) != 1:
    sys.stderr.write(
        f"taildrop tap fix: expected 1 TaildropDropArea zone, got {len(matches)}\n"
    )
    sys.exit(1)

zone_repl = f"""        #else
            {marker_v4}
            private var zone: some View {{
                Button {{
                    presentDocumentPicker()
                }} label: {{
                    label
                        .contentShape(Rectangle())
                        .background {{
                            TaildropDropArea(
                                onTargeted: {{ targeted in
                                    dropTargeted = targeted
                                }},
                                onTap: {{
                                    // Button 已处理点击；这里再 present 会弹两次选择器
                                }},
                                onFiles: {{ files, firstError in
                                    if files.isEmpty, let firstError {{
                                        alert = AlertState(action: "receive dropped files", error: firstError)
                                        return
                                    }}
                                    send(files.map(\\.url), temporaryDirectories: files.compactMap(\\.temporaryDirectory))
                                }}
                            )
                        }}
                }}
                .buttonStyle(.plain)
            }}

            private func presentDocumentPicker() {{
                documentPickerBridge.present(
                    onPick: {{ urls in send(urls) }},
                    onFailure: {{ error in
                        guard (error as? CocoaError)?.code != .userCancelled else {{ return }}
                        alert = AlertState(action: "select files", error: error)
                    }}
                )
            }}
        #endif"""
zone_repl = zone_repl.replace("\\\\.url", "\\.url").replace(
    "\\\\.temporaryDirectory", "\\.temporaryDirectory"
)

m = matches[0]
text = text[: m.start()] + zone_repl + text[m.end() :]

bridge = r'''
#if os(iOS)
    /// Form/List 内 SwiftUI `.fileImporter` 在部分环境下不弹出；改从 keyWindow present。
    final class TaildropDocumentPickerBridge: NSObject, UIDocumentPickerDelegate {
        private var onPick: (([URL]) -> Void)?
        private var onFailure: ((Error) -> Void)?
        private var isPresenting = false

        func present(onPick: @escaping ([URL]) -> Void, onFailure: @escaping (Error) -> Void) {
            if isPresenting {
                return
            }
            self.onPick = onPick
            self.onFailure = onFailure
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                onFailure(CocoaError(.fileNoSuchFile))
                return
            }
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene.windows.first?.rootViewController
            guard var top = root else {
                onFailure(CocoaError(.fileNoSuchFile))
                return
            }
            while let presented = top.presentedViewController {
                top = presented
            }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.allowsMultipleSelection = true
            picker.delegate = self
            isPresenting = true
            top.present(picker, animated: true)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            isPresenting = false
            onPick?(urls)
            onPick = nil
            onFailure = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresenting = false
            onFailure?(CocoaError(.userCancelled))
            onPick = nil
            onFailure = nil
        }
    }
#endif

'''

# 去掉旧 bridge（含/不含 isPresenting）
old_bridge = re.compile(
    r"\n#if os\(iOS\)\n"
    r"    /// Form/List 内 SwiftUI `\.fileImporter`[\s\S]*?"
    r"    final class TaildropDocumentPickerBridge: NSObject, UIDocumentPickerDelegate \{[\s\S]*?\n"
    r"    \}\n"
    r"#endif\n\n",
    re.MULTILINE,
)
text, _ = old_bridge.subn("\n", text, count=1)

anchor = "    #if os(iOS)\n        struct TaildropDroppedFile {"
if "final class TaildropDocumentPickerBridge" in text:
    sys.stderr.write("taildrop tap fix: stale bridge left behind\n")
    sys.exit(1)
if anchor not in text:
    sys.stderr.write("taildrop tap fix: cannot find insertion point for picker bridge\n")
    sys.exit(1)
text = text.replace(anchor, bridge + anchor, 1)

path.write_text(text)
print(f"taildrop tap fix: patched {path} (v4 single document picker)")
PY
