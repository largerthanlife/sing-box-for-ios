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

# --- fixture: 上游 beta.17 形态（.background + TaildropDropArea）---
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
check "patched overlay count" "$(grep -c '\.overlay {' "$TARGET")" "1"
check "patched DropArea uses overlay" \
  "$(awk '/TaildropDropArea\(/ { print prev } { prev=$0 }' "$TARGET" | tr -d '[:space:]')" \
  ".overlay{"
check "macOS Button untouched" "$(grep -c 'Button {' "$TARGET")" "1"

# 幂等：再跑一次应保持 overlay
out="$(bash "$FIX" "$WORK/broken")"
check "idempotent message" "$out" "taildrop tap fix: already using .overlay"

# --- 无 Taildrop 文件：旧客户端，应 skip ---
mkdir -p "$WORK/old"
out="$(bash "$FIX" "$WORK/old")"
check "missing file skip" "$out" "skip taildrop tap fix: TaildropSendManager.swift not present"

# --- 有文件但无 DropArea ---
mkdir -p "$WORK/nodrop/ApplicationLibrary/Views/Tools"
echo 'struct Foo {}' > "$WORK/nodrop/ApplicationLibrary/Views/Tools/TaildropSendManager.swift"
out="$(bash "$FIX" "$WORK/nodrop")"
check "no DropArea skip" "$out" "skip taildrop tap fix: TaildropDropArea not present"

# --- 异常形态应失败 ---
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

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "all apple patch tests passed"
