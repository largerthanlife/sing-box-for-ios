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

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "all apple patch tests passed"
