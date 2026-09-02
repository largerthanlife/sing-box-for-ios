#!/usr/bin/env bash
# tipa-version.sh 测试样例
#   bash scripts/test-tipa-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tipa-version.sh
source "$SCRIPT_DIR/tipa-version.sh"
PASS=0
FAIL=0

check() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 (got '$2', want '$3')"
    FAIL=$((FAIL + 1))
  fi
}

check "marketing: 1.14.0" "$(sanitize_marketing_version 1.14.0)" "1.14.0"
check "marketing: v1.14.0" "$(sanitize_marketing_version v1.14.0)" "1.14.0"
check "marketing: strip -testing" "$(sanitize_marketing_version 1.14.0-testing)" "1.14.0"
check "marketing: strip -rc.5" "$(sanitize_marketing_version 1.14.0-rc.5)" "1.14.0"
check "marketing: beta.17 keeps numeric prefix" "$(sanitize_marketing_version 1.14.0-beta.17)" "1.14.0"
check "marketing: 1.14" "$(sanitize_marketing_version 1.14)" "1.14"
check "marketing: refuse empty" "$(sanitize_marketing_version '' || true)" ""
check "marketing: refuse garbage" "$(sanitize_marketing_version testing || true)" ""

check "project: pure tag" "$(derive_project_version 1.14.0)" "1140"
check "project: v-prefix" "$(derive_project_version v1.14.0)" "1140"
check "project: suffix uses stamp" "$(derive_project_version 1.14.0-testing 202609021530)" "202609021530"
check "project: rc uses stamp" "$(derive_project_version 1.14.0-rc.5 202608301200)" "202608301200"

# workflow upstream_tag 默认可为 testing（崩溃根因是 entitlements 宏，另有 expand 测试）
WF="$SCRIPT_DIR/../.github/workflows/sing-box-for-ios.yml"
check "workflow default upstream_tag is set" \
  "$(grep -A4 'upstream_tag:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://' | grep -E '.+' >/dev/null && echo yes || echo no)" \
  "yes"

echo
echo "tipa-version: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
