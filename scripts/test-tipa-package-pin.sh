#!/usr/bin/env bash
# test-tipa-package-pin.sh — tipa 构建必须锁住 Package.resolved，避免 Swift 包浮动把 xcodebuild 打崩
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/build-tipa.sh"
WF="$ROOT/.github/workflows/sing-box-for-ios.yml"
fail=0

check() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "ok: $name"
  else
    echo "FAIL: $name (got='$got' want='$want')" >&2
    fail=1
  fi
}

[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }
[ -f "$WF" ] || { echo "missing $WF" >&2; exit 1; }

pin=$(grep -c -- '-onlyUsePackageVersionsFromResolvedFile' "$SCRIPT" || true)
check "xcodebuild locks Package.resolved" "$pin" "1"

# 浮动 checkout 不能从 Actions cache 恢复后再被 -clonedSourcePackagesDirPath 沿用
cached_spm=$(grep -c 'sing-box-source-packages' "$WF" || true)
check "workflow does not cache swift package checkouts" "$cached_spm" "0"

if [ "$fail" -ne 0 ]; then
  echo "tipa package pin checks failed" >&2
  exit 1
fi
echo "all tipa package pin checks passed"
