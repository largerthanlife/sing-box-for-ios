#!/usr/bin/env bash
# prepare-source.sh 的集成测试样例（真实克隆公开仓库，需网络）：
#   bash scripts/test-prepare-source.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

APPLE_GITLINK="6a74d3b29bcc1dfb92379c3bdf748ad8e8783524"  # sing-box v1.14.0-beta.8 记录的 clients/apple 指针
APPLE_HEAD="$(git ls-remote https://github.com/SagerNet/sing-box-for-apple.git HEAD | cut -f1)"

check() { # <用例名> <实际> <期望>
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 (got '$2', want '$3')"
    FAIL=$((FAIL + 1))
  fi
}

# 场景 1: 纯 clone fork@testing —— describe 应为 tag 本身，apple 子模块为 gitlink 版本
env -i PATH="$PATH" HOME="$WORK/h1" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  PREPARE_DIR="$WORK/s1" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1
check "纯 clone: describe == v1.14.0-beta.8" "$(git -C "$WORK/s1" describe --tags)" "v1.14.0-beta.8"
check "纯 clone: clients/apple == gitlink" "$(git -C "$WORK/s1/clients/apple" rev-parse HEAD)" "$APPLE_GITLINK"

# 场景 2: clone + merge tag + UPDATE_APPLE=true
# 关键回归点：UPDATE_APPLE 必须发生在 merge 的 submodule update 之后，
# 否则 clients/apple 会被重置回旧 gitlink（本次构建失败的真实原因）
env -i PATH="$PATH" HOME="$WORK/h2" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  MERGE_TAG=v1.14.0-beta.8 UPDATE_APPLE=true \
  PREPARE_DIR="$WORK/s2" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1
check "merge+update: describe == v1.14.0-beta.8" "$(git -C "$WORK/s2" describe --tags)" "v1.14.0-beta.8"
check "merge+update: clients/apple == 最新 main" "$(git -C "$WORK/s2/clients/apple" rev-parse HEAD)" "$APPLE_HEAD"

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
