#!/usr/bin/env bash
# test-apple-patches.sh — apple 客户端补丁 + tipa 签署检查
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIX="$SCRIPT_DIR/apple-patches/fix-taildrop-send-tap.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
check() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "OK  $name"
  else
    echo "FAIL $name: got=[$got] want=[$want]" >&2
    fail=1
  fi
}

mkdir -p "$WORK/broken/ApplicationLibrary/Views/Tools"
cat > "$WORK/broken/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" <<'SWIFT'
        @State private var alert: AlertState?

        public var body: some View {
            zone
                .fileImporter(
                    isPresented: $importerPresented,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case let .success(urls):
                        send(urls)
                    case let .failure(error):
                        guard (error as? CocoaError)?.code != .userCancelled else { return }
                        alert = AlertState(action: "select files", error: error)
                    }
                }
                .alert($alert)
        }

        #if os(macOS)
            private var zone: some View {
                Button {
                    importerPresented = true
                } label: {
                    label
                }
            }
        #else
            private var zone: some View {
                label
                    .background {
                        TaildropDropArea(
                            onTap: {
                                importerPresented = true
                            }
                        )
                    }
            }
        #endif

    #if os(iOS)
        struct TaildropDroppedFile {
            let url: URL
        }

        private struct TaildropDropArea: UIViewRepresentable {
            let onTap: () -> Void
            func makeUIView(context _: Context) -> TaildropDropView { TaildropDropView() }
            func updateUIView(_ view: TaildropDropView, context _: Context) {}
        }

        final class TaildropDropView: UIView, UIDropInteractionDelegate {
            var onTap: (() -> Void)?

            override init(frame: CGRect) {
                super.init(frame: frame)
                backgroundColor = .clear
                addInteraction(UIDropInteraction(delegate: self))
                addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            @objc private func handleTap() {
                onTap?()
            }
        }
    #endif
SWIFT

bash "$FIX" "$WORK/broken"
TARGET="$WORK/broken/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
check "v5 marker" "$(grep -c 'cursor-taildrop-send-tap-fix-v5' "$TARGET")" "1"
check "isPresenting guard" "$(grep -c 'isPresenting' "$TARGET")" "5"
check "DropView tap gesture removed" \
  "$(grep -c 'cursor-taildrop-drop-tap-removed' "$TARGET")" "1"
check "no UITapGestureRecognizer left" \
  "$(grep -c 'UITapGestureRecognizer' "$TARGET")" "0"
check "presentDocumentPicker once in Button only" \
  "$(grep -c 'presentDocumentPicker()' "$TARGET")" "2"
check "fileImporter intact" "$(grep -c '\.fileImporter(' "$TARGET")" "1"
check "ActionExtension signed in build" \
  "$(grep -c 'ActionExtension/ActionExtension.entitlements' "$SCRIPT_DIR/build-tipa.sh")" "1"

out="$(bash "$FIX" "$WORK/broken")"
check "idempotent" "$out" "taildrop tap fix: already applied (v5)"

# upgrade from a v4-shaped file (gesture still present)
mkdir -p "$WORK/v4/ApplicationLibrary/Views/Tools"
cp "$TARGET" "$WORK/v4/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
python3 - "$WORK/v4/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
t = t.replace("cursor-taildrop-send-tap-fix-v5", "cursor-taildrop-send-tap-fix-v4")
t = t.replace(
    "                // cursor-taildrop-drop-tap-removed: tap 由外层 Button 处理，保留 drop\n",
    "                addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))\n",
)
p.write_text(t)
PY
out="$(bash "$FIX" "$WORK/v4")"
check "upgrades v4 to v5" "$(echo "$out" | grep -c 'v5 single document picker')" "1"
check "v4 upgrade removes gesture" \
  "$(grep -c 'UITapGestureRecognizer' "$WORK/v4/ApplicationLibrary/Views/Tools/TaildropSendManager.swift")" "0"

# real upstream fixture if available
UPSTREAM="/tmp/sing-box-for-apple/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
if [ -f "$UPSTREAM" ]; then
  mkdir -p "$WORK/up/ApplicationLibrary/Views/Tools"
  cp "$UPSTREAM" "$WORK/up/ApplicationLibrary/Views/Tools/"
  bash "$FIX" "$WORK/up" >/dev/null
  U="$WORK/up/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
  check "upstream v5 marker" "$(grep -c 'cursor-taildrop-send-tap-fix-v5' "$U")" "1"
  check "upstream no tap gesture" "$(grep -c 'UITapGestureRecognizer' "$U")" "0"
  out="$(bash "$FIX" "$WORK/up")"
  check "upstream idempotent" "$out" "taildrop tap fix: already applied (v5)"
fi

# --- Share / Action iOS 15 ---
SHARE_FIX="$SCRIPT_DIR/apple-patches/fix-taildrop-share-ios15.sh"
mkdir -p "$WORK/share/ShareExtension" "$WORK/share/sing-box.xcodeproj"
cat > "$WORK/share/ShareExtension/ShareView.swift" <<'SWIFT'
struct ShareView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Taildrop")
                .toolbar {
                    if viewModel.isFinished {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                viewModel.onFinish?()
                            }
                        }
                    } else {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                viewModel.cancel()
                            }
                        }
                    }
                }
                .alert($viewModel.alert)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
SWIFT
# minimal pbx with Share+Action at 16.0 (Debug+Release each)
cat > "$WORK/share/sing-box.xcodeproj/project.pbxproj" <<'PBX'
		A /* Debug */ = {
			buildSettings = {
				INFOPLIST_FILE = ShareExtension/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "sing-box";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			};
		};
		B /* Release */ = {
			buildSettings = {
				INFOPLIST_FILE = ShareExtension/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "sing-box";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			};
		};
		C /* Debug */ = {
			buildSettings = {
				INFOPLIST_FILE = ActionExtension/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Send with Taildrop";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			};
		};
		D /* Release */ = {
			buildSettings = {
				INFOPLIST_FILE = ActionExtension/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Send with Taildrop";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			};
		};
		E /* Intents Debug */ = {
			buildSettings = {
				INFOPLIST_FILE = IntentsExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
			};
		};
PBX

bash "$SHARE_FIX" "$WORK/share"
SV="$WORK/share/ShareExtension/ShareView.swift"
PB="$WORK/share/sing-box.xcodeproj/project.pbxproj"
check "share ios15 marker" "$(grep -c 'cursor-taildrop-share-ios15-v2' "$SV")" "1"
check "share uses NavigationView" "$(grep -c 'NavigationView {' "$SV")" "1"
check "share no NavigationStack" "$(grep -c 'NavigationStack' "$SV")" "0"
check "share navigationViewStyle" "$(grep -c 'navigationViewStyle(.stack)' "$SV")" "1"
check "share toolbar ios15" "$(grep -c 'cursor-taildrop-share-toolbar-ios15' "$SV")" "1"
check "share no toolbar if/else root" \
  "$(grep -c 'if viewModel.isFinished {' "$SV")" "1"
check "share+action at 15.0" "$(grep -c 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;' "$PB")" "4"
check "intents stays 16.0" "$(grep -c 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;' "$PB")" "1"
out="$(bash "$SHARE_FIX" "$WORK/share")"
check "share ios15 idempotent" "$out" "taildrop share ios15: already applied (v2)"

# upgrade from v1-shaped file (NavigationView but old toolbar if/else)
mkdir -p "$WORK/sharev1/ShareExtension" "$WORK/sharev1/sing-box.xcodeproj"
cp "$SV" "$WORK/sharev1/ShareExtension/ShareView.swift"
cp "$PB" "$WORK/sharev1/sing-box.xcodeproj/project.pbxproj"
python3 - "$WORK/sharev1/ShareExtension/ShareView.swift" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
t = t.replace("cursor-taildrop-share-ios15-v2", "cursor-taildrop-share-ios15-v1")
t = t.replace(
    """                .toolbar {
                    /* cursor-taildrop-share-toolbar-ios15 */
                    ToolbarItem(placement: .confirmationAction) {
                        if viewModel.isFinished {
                            Button("Done") {
                                viewModel.onFinish?()
                            }
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        if !viewModel.isFinished {
                            Button("Cancel") {
                                viewModel.cancel()
                            }
                        }
                    }
                }""",
    """                .toolbar {
                    if viewModel.isFinished {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                viewModel.onFinish?()
                            }
                        }
                    } else {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                viewModel.cancel()
                            }
                        }
                    }
                }""",
)
p.write_text(t)
PY
out="$(bash "$SHARE_FIX" "$WORK/sharev1")"
check "upgrades v1 to v2" "$(echo "$out" | grep -c '(v2)')" "1"
check "v1 upgrade has toolbar fix" \
  "$(grep -c 'cursor-taildrop-share-toolbar-ios15' "$WORK/sharev1/ShareExtension/ShareView.swift")" "1"

# real upstream apple tree if available
if [ -d /tmp/sing-box-for-apple/ShareExtension ] && [ -f /tmp/sing-box-for-apple/sing-box.xcodeproj/project.pbxproj ]; then
  mkdir -p "$WORK/shareup/ShareExtension" "$WORK/shareup/sing-box.xcodeproj"
  cp /tmp/sing-box-for-apple/ShareExtension/ShareView.swift "$WORK/shareup/ShareExtension/"
  cp /tmp/sing-box-for-apple/sing-box.xcodeproj/project.pbxproj "$WORK/shareup/sing-box.xcodeproj/"
  bash "$SHARE_FIX" "$WORK/shareup" >/dev/null
  check "upstream share NavigationView" \
    "$(grep -c 'NavigationView {' "$WORK/shareup/ShareExtension/ShareView.swift")" "1"
  check "upstream share toolbar ios15" \
    "$(grep -c 'cursor-taildrop-share-toolbar-ios15' "$WORK/shareup/ShareExtension/ShareView.swift")" "1"
  cnt="$(python3 - "$WORK/shareup/sing-box.xcodeproj/project.pbxproj" <<'PY'
import re, sys
pb = open(sys.argv[1]).read()
n = 0
for plist in ("ShareExtension/Info.plist", "ActionExtension/Info.plist"):
    n += len(
        re.findall(
            rf"INFOPLIST_FILE = {re.escape(plist)};(?:[^\n]*\n){{0,4}}\t+IPHONEOS_DEPLOYMENT_TARGET = 15\.0;",
            pb,
        )
    )
print(n)
PY
)"
  check "upstream share+action configs at 15.0" "$cnt" "4"
  out="$(bash "$SHARE_FIX" "$WORK/shareup")"
  check "upstream share idempotent" "$out" "taildrop share ios15: already applied (v2)"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "all apple patch tests passed"
