#!/usr/bin/env bash
# fix-taildrop-share-ios15.sh — 让 Taildrop 系统分享 / Action 扩展可在 iOS 15 加载
#
# 上游 ShareExtension / ActionExtension 的 IPHONEOS_DEPLOYMENT_TARGET=16.0，
# 且 ShareView 使用 NavigationStack（iOS 16+）。iOS 15.x 上扩展不会出现或点开即挂。
#
# 本补丁：
#   1) 把 Share/Action 的 deployment target 降到 15.0
#   2) ShareView 改用 NavigationView（分享 UI 不需要 NavigationPath）
#
# 用法：fix-taildrop-share-ios15.sh <clients/apple 目录>
set -euo pipefail

APPLE_DIR="${1:?usage: $0 <clients/apple>}"
VIEW="${APPLE_DIR}/ShareExtension/ShareView.swift"
PBX="${APPLE_DIR}/sing-box.xcodeproj/project.pbxproj"
MARKER="/* cursor-taildrop-share-ios15-v1 */"

python3 - "$VIEW" "$PBX" "$MARKER" <<'PY'
import pathlib, re, sys

view_path = pathlib.Path(sys.argv[1])
pbx_path = pathlib.Path(sys.argv[2])
marker = sys.argv[3]

if not view_path.is_file():
    print("skip taildrop share ios15: ShareView.swift not present")
    sys.exit(0)
if not pbx_path.is_file():
    print("skip taildrop share ios15: project.pbxproj not present")
    sys.exit(0)

view = view_path.read_text()
pbx = pbx_path.read_text()

def share_action_target(text: str, plist: str, ver: str) -> bool:
    return bool(
        re.search(
            rf"INFOPLIST_FILE = {re.escape(plist)};(?:[^\n]*\n){{0,4}}"
            rf"\t+IPHONEOS_DEPLOYMENT_TARGET = {re.escape(ver)};",
            text,
        )
    )

view_done = marker in view and "NavigationView {" in view
pbx_done = (
    "cursor-taildrop-share-ios15-pbx" in pbx
    and share_action_target(pbx, "ShareExtension/Info.plist", "15.0")
    and share_action_target(pbx, "ActionExtension/Info.plist", "15.0")
)

if view_done and pbx_done:
    print("taildrop share ios15: already applied (v1)")
    sys.exit(0)

changed = []

if not view_done:
    if marker in view and "NavigationView {" in view:
        pass
    elif "NavigationStack {" in view:
        view2, n = re.subn(
            r"(\s*)NavigationStack \{",
            rf"\1{marker}\n\1NavigationView {{",
            view,
            count=1,
        )
        if n != 1:
            sys.stderr.write("taildrop share ios15: failed to replace NavigationStack\n")
            sys.exit(1)
        view = view2
        if ".navigationViewStyle(.stack)" not in view:
            view2, n = re.subn(
                r"(                \.alert\(\$viewModel\.alert\)\n        \}\n)"
                r"(        #if os\(macOS\)\n)",
                r"\1"
                r"        #if os(iOS)\n"
                r"        .navigationViewStyle(.stack)\n"
                r"        #endif\n"
                r"\2",
                view,
                count=1,
            )
            if n != 1:
                # no macOS frame branch — still add style after NavigationView close
                view2, n = re.subn(
                    r"(                \.alert\(\$viewModel\.alert\)\n        \}\n)",
                    r"\1"
                    r"        #if os(iOS)\n"
                    r"        .navigationViewStyle(.stack)\n"
                    r"        #endif\n",
                    view,
                    count=1,
                )
            if n != 1:
                sys.stderr.write(
                    "taildrop share ios15: cannot insert navigationViewStyle\n"
                )
                sys.exit(1)
            view = view2
    else:
        sys.stderr.write("taildrop share ios15: unexpected ShareView navigation root\n")
        sys.exit(1)
    view_path.write_text(view)
    changed.append("ShareView")

if not pbx_done:
    def lower_target(text: str, plist: str) -> tuple[str, int]:
        pat = re.compile(
            rf"(INFOPLIST_FILE = {re.escape(plist)};\n"
            rf"(?:[^\n]*\n){{0,3}}"
            rf"\t+)IPHONEOS_DEPLOYMENT_TARGET = 16\.0;",
        )
        return pat.subn(r"\1IPHONEOS_DEPLOYMENT_TARGET = 15.0;", text)

    pbx2, n1 = lower_target(pbx, "ShareExtension/Info.plist")
    pbx3, n2 = lower_target(pbx2, "ActionExtension/Info.plist")
    if not (
        share_action_target(pbx3, "ShareExtension/Info.plist", "15.0")
        and share_action_target(pbx3, "ActionExtension/Info.plist", "15.0")
    ):
        sys.stderr.write(
            f"taildrop share ios15: Share/Action not at 15.0 (share_repl={n1} action_repl={n2})\n"
        )
        sys.exit(1)
    if "cursor-taildrop-share-ios15-pbx" not in pbx3:
        pbx3 = pbx3.replace(
            "INFOPLIST_FILE = ShareExtension/Info.plist;",
            "INFOPLIST_FILE = ShareExtension/Info.plist; /* cursor-taildrop-share-ios15-pbx */",
            1,
        )
    pbx_path.write_text(pbx3)
    changed.append(f"pbxproj(share={n1},action={n2})")

print(
    "taildrop share ios15: patched "
    + (", ".join(changed) if changed else "noop")
    + " (v1)"
)
PY
