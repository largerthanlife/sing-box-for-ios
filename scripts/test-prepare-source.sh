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

# 场景 1: 纯 clone fork@testing —— describe 应基于 v1.14.0-beta.8，apple 子模块为 gitlink 版本
env -i PATH="$PATH" HOME="$WORK/h1" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  PREPARE_DIR="$WORK/s1" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1
case "$(git -C "$WORK/s1" describe --tags 2>/dev/null)" in
  v1.14.0-beta.8*)
    echo "PASS: 纯 clone: describe 基于 v1.14.0-beta.8"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "FAIL: 纯 clone: describe=$(git -C "$WORK/s1" describe --tags 2>&1)"
    FAIL=$((FAIL + 1))
    ;;
esac
check "纯 clone: clients/apple == gitlink" "$(git -C "$WORK/s1/clients/apple" rev-parse HEAD)" "$APPLE_GITLINK"

# 场景 2: clone + merge tag + UPDATE_APPLE=true
# 关键回归点：UPDATE_APPLE 必须发生在 merge 的 submodule update 之后，
# 否则 clients/apple 会被重置回旧 gitlink（本次构建失败的真实原因）
env -i PATH="$PATH" HOME="$WORK/h2" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  MERGE_TAG=v1.14.0-beta.8 UPDATE_APPLE=true \
  PREPARE_DIR="$WORK/s2" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1
case "$(git -C "$WORK/s2" describe --tags 2>/dev/null)" in
  v1.14.0-beta.8*)
    echo "PASS: merge+update: describe 基于 v1.14.0-beta.8"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "FAIL: merge+update: describe=$(git -C "$WORK/s2" describe --tags 2>&1)"
    FAIL=$((FAIL + 1))
    ;;
esac
check "merge+update: clients/apple == 最新 main" "$(git -C "$WORK/s2/clients/apple" rev-parse HEAD)" "$APPLE_HEAD"

# 场景 3: 上游改写历史 + modify/delete（真实回归：beta.13 删了
# common/process/searcher_android.go，-X theirs 盖不住这类冲突，必须额外
# git rm；同时仍须保留自有新增文件）
if env -i PATH="$PATH" HOME="$WORK/h3" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  MERGE_TAG=v1.14.0-beta.13 \
  PREPARE_DIR="$WORK/s3" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1; then
  echo "PASS: 历史分叉+删改冲突合并: merge v1.14.0-beta.13 成功"
  PASS=$((PASS + 1))
else
  echo "FAIL: 历史分叉+删改冲突合并: merge v1.14.0-beta.13 失败"
  FAIL=$((FAIL + 1))
fi
if [ -f "$WORK/s3/protocol/shadowsocks/method_chacha20.go" ]; then
  echo "PASS: 历史分叉+删改冲突合并: 自有新增文件保留"
  PASS=$((PASS + 1))
else
  echo "FAIL: 历史分叉+删改冲突合并: method_chacha20.go 丢失"
  FAIL=$((FAIL + 1))
fi
if [ ! -e "$WORK/s3/common/process/searcher_android.go" ]; then
  echo "PASS: 历史分叉+删改冲突合并: 上游已删文件已移除"
  PASS=$((PASS + 1))
else
  echo "FAIL: 历史分叉+删改冲突合并: searcher_android.go 仍残留"
  FAIL=$((FAIL + 1))
fi
case "$(git -C "$WORK/s3" describe --tags 2>/dev/null)" in
  v1.14.0-beta.13*)
    echo "PASS: 历史分叉+删改冲突合并: describe 基于 v1.14.0-beta.13"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "FAIL: 历史分叉+删改冲突合并: describe=$(git -C "$WORK/s3" describe --tags 2>&1)"
    FAIL=$((FAIL + 1))
    ;;
esac
if [ -z "$(git -C "$WORK/s3" status --porcelain)" ]; then
  echo "PASS: 历史分叉+删改冲突合并: 无冲突残留"
  PASS=$((PASS + 1))
else
  echo "FAIL: 历史分叉+删改冲突合并: 存在未解决冲突"
  FAIL=$((FAIL + 1))
fi

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
