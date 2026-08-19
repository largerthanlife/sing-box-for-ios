#!/usr/bin/env bash
# test-apple-patches.sh — apple 客户端补丁脚本的接口/样例测试
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

# --- fixture: 与上游一致的缩进（#else/#endif 前 8 空格）---
mkdir -p "$WORK/broken/ApplicationLibrary/Views/Tools"
cat > "$WORK/broken/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" <<'SWIFT'
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
SWIFT

bash "$FIX" "$WORK/broken"
TARGET="$WORK/broken/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
check "patched has marker" \
  "$(grep -c 'cursor-taildrop-send-tap-fix' "$TARGET")" "1"
check "patched DropArea in background" \
  "$(awk '/TaildropDropArea\(/ { print prev } { prev=$0 }' "$TARGET" | tr -d '[:space:]')" \
  ".background{"
check "patched has Button" "$(grep -c 'Button {' "$TARGET")" "2"

out="$(bash "$FIX" "$WORK/broken")"
check "idempotent message" "$out" "taildrop tap fix: already applied"

# --- 上一版 .overlay 形态也应能升级 ---
mkdir -p "$WORK/overlay/ApplicationLibrary/Views/Tools"
cat > "$WORK/overlay/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" <<'SWIFT'
        #else
            private var zone: some View {
                label
                    .overlay {
                        TaildropDropArea(
                            onTap: {
                                importerPresented = true
                            }
                        )
                    }
            }
        #endif
SWIFT
bash "$FIX" "$WORK/overlay"
check "overlay upgraded to Button" \
  "$(grep -c 'cursor-taildrop-send-tap-fix' "$WORK/overlay/ApplicationLibrary/Views/Tools/TaildropSendManager.swift")" "1"

mkdir -p "$WORK/old"
out="$(bash "$FIX" "$WORK/old")"
check "missing file skip" "$out" "skip taildrop tap fix: TaildropSendManager.swift not present"

mkdir -p "$WORK/nodrop/ApplicationLibrary/Views/Tools"
echo 'struct Foo {}' > "$WORK/nodrop/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
out="$(bash "$FIX" "$WORK/nodrop")"
check "no DropArea skip" "$out" "skip taildrop tap fix: TaildropDropArea not present"

mkdir -p "$WORK/weird/ApplicationLibrary/Views/Tools"
cat > "$WORK/weird/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" <<'SWIFT'
TaildropDropArea(
    onTap: {}
)
SWIFT
if bash "$FIX" "$WORK/weird" 2>/dev/null; then
  echo "FAIL weird layout should exit non-zero" >&2
  fail=1
else
  echo "OK  weird layout rejected"
fi

BUILD="$SCRIPT_DIR/build-tipa.sh"
check "build signs ShareExtension" \
  "$(grep -c 'ShareExtension/ShareExtension.entitlements' "$BUILD")" "1"
check "build signs ActionExtension" \
  "$(grep -c 'ActionExtension/ActionExtension.entitlements' "$BUILD")" "1"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "all apple patch tests passed"
