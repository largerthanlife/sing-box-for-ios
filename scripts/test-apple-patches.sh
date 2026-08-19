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
    #endif
SWIFT

bash "$FIX" "$WORK/broken"
TARGET="$WORK/broken/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
check "v3 marker" "$(grep -c 'cursor-taildrop-send-tap-fix-v3' "$TARGET")" "1"
check "UIKit bridge class" "$(grep -c 'final class TaildropDocumentPickerBridge' "$TARGET")" "1"
check "presentDocumentPicker" "$(grep -c 'presentDocumentPicker' "$TARGET")" "3"
check "fileImporter intact" "$(grep -c '\.fileImporter(' "$TARGET")" "1"
check "no broken ifndef wrap" "$(grep -c '#if !os(iOS)' "$TARGET")" "0"
check "ActionExtension signed in build" \
  "$(grep -c 'ActionExtension/ActionExtension.entitlements' "$SCRIPT_DIR/build-tipa.sh")" "1"

# braces around fileImporter trailing closure must close before .alert
python3 - "$TARGET" <<'PY'
import pathlib,sys
t=pathlib.Path(sys.argv[1]).read_text().splitlines()
# find fileImporter block: must not contain #endif inside
start=next(i for i,l in enumerate(t) if '.fileImporter(' in l)
chunk='\n'.join(t[start:start+20])
assert '#endif' not in chunk, chunk
assert ') { result in' in chunk
print('OK  fileImporter closure intact')
PY

out="$(bash "$FIX" "$WORK/broken")"
check "idempotent" "$out" "taildrop tap fix: already applied (v3)"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "all apple patch tests passed"
