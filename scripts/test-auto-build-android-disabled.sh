#!/usr/bin/env bash
# test-auto-build-android-disabled.sh — APK 自动产物暂时关闭时，断言无生效 schedule
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="$ROOT/.github/workflows/auto-build-android.yml"
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

[ -f "$WF" ] || { echo "missing $WF" >&2; exit 1; }

# 生效的 schedule 块：行首是 "schedule:"（非注释）
active_schedule=$(grep -cE '^[[:space:]]*schedule:' "$WF" || true)
# 注释掉的 cron（恢复指引）
commented_cron=$(grep -cE '^[[:space:]]*#[[:space:]]*- cron:' "$WF" || true)

check "no active schedule key" "$active_schedule" "0"
check "cron kept as comment for restore" "$commented_cron" "1"

# 仍保留手动触发入口
has_dispatch=$(grep -cE '^[[:space:]]*workflow_dispatch:' "$WF" || true)
check "workflow_dispatch retained" "$has_dispatch" "1"

if [ "$fail" -ne 0 ]; then
  echo "auto-build-android disable checks failed" >&2
  exit 1
fi
echo "all auto-build-android disable checks passed"
