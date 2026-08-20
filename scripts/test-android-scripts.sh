#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0
check() {
  if [ "$2" = "$3" ]; then echo "OK  $1"
  else echo "FAIL $1: got=[$2] want=[$3]" >&2; fail=1
  fi
}
source "$SCRIPT_DIR/resolve-source.sh" largerthanlife/sing-box "" "1.14.0-beta.17" >/dev/null
check "resolve empty ref -> vtag" "$SB_REF" "v1.14.0-beta.17"
check "overlay list has chacha20" \
  "$(grep -c method_chacha20.go "$SCRIPT_DIR/overlay-files.txt" || true)" "1"
check "build-apk exists" "$(test -f "$SCRIPT_DIR/build-apk.sh" && echo 1 || echo 0)" "1"
check "prepare-source-android exists" \
  "$(test -f "$SCRIPT_DIR/prepare-source-android.sh" && echo 1 || echo 0)" "1"
# mkdir libs must appear before build_libbox
awk '
  /mkdir -p "\$ANDROID_DIR\/app\/libs"/ { m=NR }
  /build_libbox -target android/ { b=NR }
  END { print (m && b && m < b) ? 1 : 0 }
' "$SCRIPT_DIR/build-apk.sh" > /tmp/order.txt
check "mkdir libs before build_libbox" "$(cat /tmp/order.txt)" "1"
check "fallback copy libbox.aar" \
  "$(grep -c 'copied \$aar into android app/libs' "$SCRIPT_DIR/build-apk.sh" || true)" "1"
# 默认给手机 + Chromebook：arm64 + x86_64，不默认传 universal / legacy
check "default abi list phone+chromebook" \
  "$(grep -c 'APK_ABIS:-arm64-v8a,x86_64' "$SCRIPT_DIR/build-apk.sh" || true)" "1"
check "legacy off by default" \
  "$(grep -c 'APK_INCLUDE_LEGACY:-false' "$SCRIPT_DIR/build-apk.sh" || true)" "1"
check "universal off by default" \
  "$(grep -c 'APK_INCLUDE_UNIVERSAL:-false' "$SCRIPT_DIR/build-apk.sh" || true)" "1"
check "no duplicate universal glob" \
  "$(grep -c '\*universal\*\.apk' "$SCRIPT_DIR/build-apk.sh" || true)" "0"

# 单元：按 ABI 收集时只拿 arm64 / x86_64
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/apk" "$TMP/out"
for name in \
  SFA-1.14.0-beta.17-arm64-v8a-debug.apk \
  SFA-1.14.0-beta.17-x86_64-debug.apk \
  SFA-1.14.0-beta.17-armeabi-v7a-debug.apk \
  SFA-1.14.0-beta.17-x86-debug.apk \
  SFA-1.14.0-beta.17-universal-debug.apk
do
  : > "$TMP/apk/$name"
done
bash -c '
set -euo pipefail
APK_ABIS="arm64-v8a,x86_64"
APK_INCLUDE_UNIVERSAL=false
DEST_DIR="'"$TMP"'/out"
TAG_NAME=1.14.0-beta.17
OUTPUT_PREFIX=sing-box
SUMMARY=/dev/null
idx=0
dir="'"$TMP"'/apk"
label=other
apks=()
want_abis=()
IFS="," read -r -a want_abis <<< "$APK_ABIS"
for abi in "${want_abis[@]}"; do
  abi="$(echo "$abi" | tr -d "[:space:]")"
  [ -n "$abi" ] || continue
  for f in "$dir"/*-"${abi}"-*.apk; do
    [ -f "$f" ] || continue
    apks+=("$f")
  done
done
if [ "$APK_INCLUDE_UNIVERSAL" = "true" ]; then
  for f in "$dir"/*-universal-*.apk; do
    [ -f "$f" ] || continue
    apks+=("$f")
  done
fi
echo "count=${#apks[@]}"
for f in "${apks[@]}"; do basename "$f"; done
test "${#apks[@]}" -eq 2
' > "$TMP/collect.out"
check "collect only arm64+x86_64" "$(grep -c 'count=2' "$TMP/collect.out" || true)" "1"
check "collect has arm64" \
  "$(grep -c 'arm64-v8a-debug.apk' "$TMP/collect.out" || true)" "1"
check "collect has x86_64" \
  "$(grep -c 'x86_64-debug.apk' "$TMP/collect.out" || true)" "1"
check "collect skips universal" \
  "$(grep -c universal "$TMP/collect.out" || true)" "0"

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "all android script smoke tests passed"
