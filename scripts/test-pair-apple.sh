#!/usr/bin/env bash
# pair-apple.sh 测试：分支→main，发版 tag→Bump version（不漂在更新的 main 上）
#   bash scripts/test-pair-apple.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=pair-apple.sh
source "$SCRIPT_DIR/pair-apple.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

git_ident() {
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
}

check() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 (got '$2', want '$3')"
    FAIL=$((FAIL + 1))
  fi
}

# 手动 workflow 默认：不填专家参数也能 overlay 官方 testing + 配对 apple
WF="$SCRIPT_DIR/../.github/workflows/sing-box-for-ios.yml"
check "workflow default sing_box_ref=testing" \
  "$(grep -A4 'sing_box_ref:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://')" \
  "testing"
check "workflow default upstream_tag=testing" \
  "$(grep -A4 'upstream_tag:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://')" \
  "testing"
check "workflow default update_apple=true" \
  "$(grep -A4 'update_apple:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://')" \
  "true"
check "version: 1.14.0" "$(apple_version_from_ref 1.14.0)" "1.14.0"
check "version: v1.14.0-beta.8" "$(apple_version_from_ref v1.14.0-beta.8)" "1.14.0-beta.8"
check "version: testing is empty" "$(apple_version_from_ref testing)" ""
check "version: main is empty" "$(apple_version_from_ref main)" ""

# 假 apple 仓库：1.14.0 bump 之后 main 又超前一笔（模拟「main 对 frozen tag 过新」）
APPLE="$WORK/apple"
git init -b main "$APPLE" >/dev/null
git_ident "$APPLE"
echo v113 > "$APPLE/version.txt"
git -C "$APPLE" add version.txt
git -C "$APPLE" commit -m 'Bump version 1.13.0' >/dev/null
echo v114 > "$APPLE/version.txt"
git -C "$APPLE" add version.txt
git -C "$APPLE" commit -m 'Bump version 1.14.0' >/dev/null
BUMP114="$(git -C "$APPLE" rev-parse HEAD)"
echo too-new > "$APPLE/from-main.txt"
git -C "$APPLE" add from-main.txt
git -C "$APPLE" commit -m 'Record platform network path in power report' >/dev/null
MAIN_HEAD="$(git -C "$APPLE" rev-parse HEAD)"

if APPLE_CLONE_URL="$APPLE" clone_paired_apple "$WORK/out-tag" v1.14.0 tag >/dev/null; then
  echo "PASS: clone tag v1.14.0"
  PASS=$((PASS + 1))
else
  echo "FAIL: clone tag v1.14.0"
  FAIL=$((FAIL + 1))
fi
check "tag pair: HEAD is Bump version 1.14.0" \
  "$(git -C "$WORK/out-tag" rev-parse HEAD 2>/dev/null || true)" "$BUMP114"
check "tag pair: 不含 main 超前文件" \
  "$(test -e "$WORK/out-tag/from-main.txt" && echo yes || echo no)" "no"
check "tag pair: version.txt is 1.14.0" \
  "$(cat "$WORK/out-tag/version.txt" 2>/dev/null || true)" "v114"

if APPLE_CLONE_URL="$APPLE" clone_paired_apple "$WORK/out-tag-nov" 1.14.0 tag >/dev/null; then
  echo "PASS: clone tag 1.14.0 (no v)"
  PASS=$((PASS + 1))
else
  echo "FAIL: clone tag 1.14.0 (no v)"
  FAIL=$((FAIL + 1))
fi
check "tag 1.14.0: HEAD is bump" \
  "$(git -C "$WORK/out-tag-nov" rev-parse HEAD 2>/dev/null || true)" "$BUMP114"

if APPLE_CLONE_URL="$APPLE" clone_paired_apple "$WORK/out-branch" testing branch >/dev/null; then
  echo "PASS: clone branch testing"
  PASS=$((PASS + 1))
else
  echo "FAIL: clone branch testing"
  FAIL=$((FAIL + 1))
fi
check "branch pair: HEAD is apple main" \
  "$(git -C "$WORK/out-branch" rev-parse HEAD 2>/dev/null || true)" "$MAIN_HEAD"
check "branch pair: 含 main 超前文件" \
  "$(test -f "$WORK/out-branch/from-main.txt" && echo yes || echo no)" "yes"

if APPLE_CLONE_URL="$APPLE" clone_paired_apple "$WORK/out-missing" v9.9.9 tag >/dev/null 2>&1; then
  echo "FAIL: missing bump should error (not fall back to main)"
  FAIL=$((FAIL + 1))
else
  echo "PASS: missing bump refuses floating main"
  PASS=$((PASS + 1))
fi

# TAG_NAME fallback（reF1nd 的 SB_REF=v1.14.0-reF1nd）
if TAG_NAME=1.14.0 APPLE_CLONE_URL="$APPLE" \
    clone_paired_apple "$WORK/out-fallback" v1.14.0-reF1nd tag >/dev/null; then
  echo "PASS: TAG_NAME fallback for reF1nd-style ref"
  PASS=$((PASS + 1))
else
  echo "FAIL: TAG_NAME fallback for reF1nd-style ref"
  FAIL=$((FAIL + 1))
fi
check "fallback: HEAD is bump 1.14.0" \
  "$(git -C "$WORK/out-fallback" rev-parse HEAD 2>/dev/null || true)" "$BUMP114"

# 联网：官方 apple 的 v1.14.0 应对上 Bump version 1.14.0，且不是当前 main
APPLE_REMOTE=https://github.com/SagerNet/sing-box-for-apple.git
LIVE_MAIN="$(git ls-remote "$APPLE_REMOTE" refs/heads/main | awk '{print $1}')"
if clone_paired_apple "$WORK/live-114" v1.14.0 tag; then
  LIVE_MSG="$(git -C "$WORK/live-114" log -1 --format=%s)"
  check "live: v1.14.0 message is Bump version 1.14.0" "$LIVE_MSG" "Bump version 1.14.0"
  check "live: v1.14.0 is not floating main" \
    "$( [ "$(git -C "$WORK/live-114" rev-parse HEAD)" != "$LIVE_MAIN" ] && echo yes || echo no )" \
    "yes"
else
  echo "FAIL: live clone_paired_apple v1.14.0"
  FAIL=$((FAIL + 1))
fi

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
