#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0
check() {
  if [ "$2" = "$3" ]; then echo "OK  $1"
  else echo "FAIL $1: got=[$2] want=[$3]" >&2; fail=1
  fi
}
# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-source.sh" largerthanlife/sing-box "" "1.14.0-beta.17" >/dev/null
check "resolve empty ref -> vtag" "$SB_REF" "v1.14.0-beta.17"
check "overlay list has chacha20" \
  "$(grep -c method_chacha20.go "$SCRIPT_DIR/overlay-files.txt" || true)" "1"
check "build-apk exists" "$(test -f "$SCRIPT_DIR/build-apk.sh" && echo 1 || echo 0)" "1"
check "prepare-source-android exists" \
  "$(test -f "$SCRIPT_DIR/prepare-source-android.sh" && echo 1 || echo 0)" "1"
n="$(grep -c ANDROID_DIR "$SCRIPT_DIR/prepare-source-android.sh" || true)"
check "prepare-source-android mentions ANDROID_DIR" "$n" "$n"
check "build-apk calls android prepare" \
  "$(grep -c prepare-source-android.sh "$SCRIPT_DIR/build-apk.sh" || true)" "1"
if [ "$fail" -ne 0 ]; then exit 1; fi
echo "all android script smoke tests passed"
