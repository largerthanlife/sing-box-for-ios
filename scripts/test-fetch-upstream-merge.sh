#!/usr/bin/env bash
# fetch-upstream-merge.sh / prepare-source overlay-target 测试：
#   - 本地假仓库：tag、分支、缺失 ref、overlay 两个 chacha20 文件
#   - 联网：从 SagerNet/sing-box fetch v1.14.0 与 testing
#   bash scripts/test-fetch-upstream-merge.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fetch-upstream-merge.sh
source "$SCRIPT_DIR/fetch-upstream-merge.sh"
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

# 上游：v1.14.0 tag，然后 testing 再超前一个提交（模拟官方 testing 已越过发版 tag）
UP="$WORK/upstream"
git init -b main "$UP" >/dev/null
git_ident "$UP"
mkdir -p "$UP/protocol/shadowsocks"
echo base > "$UP/README.md"
git -C "$UP" add README.md
git -C "$UP" commit -m base >/dev/null
echo tag-tree > "$UP/from-tag.txt"
git -C "$UP" add from-tag.txt
git -C "$UP" commit -m 'tag tree' >/dev/null
git -C "$UP" tag -a v1.14.0 -m v1.14.0
git -C "$UP" checkout -b testing >/dev/null
echo branch-tree > "$UP/from-testing.txt"
git -C "$UP" add from-testing.txt
git -C "$UP" commit -m 'testing ahead of v1.14.0' >/dev/null
TAG_SHA="$(git -C "$UP" rev-parse v1.14.0^{commit})"
TESTING_SHA="$(git -C "$UP" rev-parse testing)"

# fork：从 v1.14.0 拉出 testing，只加两份 chacha20 + 一个不应被 overlay 的文件
FORK="$WORK/fork"
git clone "$UP" "$FORK" >/dev/null
git_ident "$FORK"
git -C "$FORK" checkout -B testing v1.14.0 >/dev/null
mkdir -p "$FORK/protocol/shadowsocks"
echo chacha-impl > "$FORK/protocol/shadowsocks/method_chacha20.go"
echo chacha-test > "$FORK/protocol/shadowsocks/method_chacha20_test.go"
echo fork-only > "$FORK/fork-only.txt"
git -C "$FORK" add protocol/shadowsocks/method_chacha20.go \
  protocol/shadowsocks/method_chacha20_test.go fork-only.txt
git -C "$FORK" commit -m 'fork overlay files' >/dev/null
FORK_TESTING="$(git -C "$FORK" rev-parse testing)"

# 1) helper：tag
HELPER="$WORK/helper-tag"
git clone -b testing "$FORK" "$HELPER" >/dev/null
git_ident "$HELPER"
git -C "$HELPER" remote add upstream "$UP"
BEFORE="$(git -C "$HELPER" rev-parse HEAD)"
( cd "$HELPER" && fetch_upstream_merge_and_reset v1.14.0 >"$WORK/out-tag.log" )
check "helper tag: HEAD is v1.14.0 commit" "$(git -C "$HELPER" rev-parse HEAD)" "$TAG_SHA"
check "helper tag: BEFORE stayed on fork testing" "$BEFORE" "$FORK_TESTING"
check "helper tag: logged tag fetch" \
  "$(grep -c 'fetched upstream tag v1.14.0' "$WORK/out-tag.log" || true)" "1"

# 2) helper：分支。clone 本地已叫 testing，reset 不得停在 fork 自己的 testing
HELPERB="$WORK/helper-branch"
git clone -b testing "$FORK" "$HELPERB" >/dev/null
git_ident "$HELPERB"
git -C "$HELPERB" remote add upstream "$UP"
( cd "$HELPERB" && fetch_upstream_merge_and_reset testing >"$WORK/out-branch.log" )
check "helper branch: HEAD is upstream testing" "$(git -C "$HELPERB" rev-parse HEAD)" "$TESTING_SHA"
check "helper branch: logged branch fetch" \
  "$(grep -c 'fetched upstream branch testing' "$WORK/out-branch.log" || true)" "1"
check "helper branch: left fork testing" \
  "$( [ "$(git -C "$HELPERB" rev-parse HEAD)" != "$FORK_TESTING" ] && echo yes || echo no )" \
  "yes"

# 3) helper：不存在的 ref
HELPERM="$WORK/helper-missing"
git clone -b testing "$FORK" "$HELPERM" >/dev/null
git_ident "$HELPERM"
git -C "$HELPERM" remote add upstream "$UP"
if (
  cd "$HELPERM"
  fetch_upstream_merge_and_reset definitely-missing-ref-xyz
) >/dev/null 2>&1; then
  echo "FAIL: helper missing: expected non-zero"
  FAIL=$((FAIL + 1))
else
  echo "PASS: helper missing: 非 tag 非分支时报错"
  PASS=$((PASS + 1))
fi

# 4b) MERGE_TAG=1.14.0（无 v）也应打到同一 tag
HELPERV="$WORK/helper-nov"
git clone -b testing "$FORK" "$HELPERV" >/dev/null
git_ident "$HELPERV"
git -C "$HELPERV" remote add upstream "$UP"
( cd "$HELPERV" && fetch_upstream_merge_and_reset 1.14.0 >"$WORK/out-nov.log" )
check "helper 1.14.0: HEAD is v1.14.0 commit" "$(git -C "$HELPERV" rev-parse HEAD)" "$TAG_SHA"
check "helper 1.14.0: logged v-prefixed tag fetch" \
  "$(grep -c 'fetched upstream tag v1.14.0' "$WORK/out-nov.log" || true)" "1"

# 4) prepare-source.sh overlay 到 tag v1.14.0
if env -i PATH="$PATH" HOME="$WORK/h-tag" \
  SB_REPO=fake/sing-box SB_REF=testing \
  SB_CLONE_URL="$FORK" UPSTREAM_CLONE_URL="$UP" \
  MERGE_TAG=v1.14.0 OVERLAY_LIST="$SCRIPT_DIR/overlay-files.txt" \
  PREPARE_DIR="$WORK/prep-tag" \
  bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1; then
  echo "PASS: prepare tag: prepare-source 成功"
  PASS=$((PASS + 1))
else
  echo "FAIL: prepare tag: prepare-source 失败"
  FAIL=$((FAIL + 1))
fi
check "prepare tag: method_chacha20.go" \
  "$(test -f "$WORK/prep-tag/protocol/shadowsocks/method_chacha20.go" && echo yes || echo no)" "yes"
check "prepare tag: method_chacha20_test.go" \
  "$(test -f "$WORK/prep-tag/protocol/shadowsocks/method_chacha20_test.go" && echo yes || echo no)" "yes"
check "prepare tag: 不含 fork-only.txt" \
  "$(test -e "$WORK/prep-tag/fork-only.txt" && echo yes || echo no)" "no"
check "prepare tag: 含 from-tag.txt" \
  "$(test -f "$WORK/prep-tag/from-tag.txt" && echo yes || echo no)" "yes"
check "prepare tag: 不含 testing 独有文件" \
  "$(test -e "$WORK/prep-tag/from-testing.txt" && echo yes || echo no)" "no"
check "prepare tag: parent is v1.14.0" \
  "$(git -C "$WORK/prep-tag" rev-parse HEAD^ 2>/dev/null || true)" "$TAG_SHA"

# 5) prepare-source.sh overlay 到分支 testing
if env -i PATH="$PATH" HOME="$WORK/h-branch" \
  SB_REPO=fake/sing-box SB_REF=testing \
  SB_CLONE_URL="$FORK" UPSTREAM_CLONE_URL="$UP" \
  MERGE_TAG=testing OVERLAY_LIST="$SCRIPT_DIR/overlay-files.txt" \
  PREPARE_DIR="$WORK/prep-branch" \
  bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1; then
  echo "PASS: prepare branch: prepare-source 成功"
  PASS=$((PASS + 1))
else
  echo "FAIL: prepare branch: prepare-source 失败"
  FAIL=$((FAIL + 1))
fi
check "prepare branch: method_chacha20.go" \
  "$(test -f "$WORK/prep-branch/protocol/shadowsocks/method_chacha20.go" && echo yes || echo no)" "yes"
check "prepare branch: method_chacha20_test.go" \
  "$(test -f "$WORK/prep-branch/protocol/shadowsocks/method_chacha20_test.go" && echo yes || echo no)" "yes"
check "prepare branch: 不含 fork-only.txt" \
  "$(test -e "$WORK/prep-branch/fork-only.txt" && echo yes || echo no)" "no"
check "prepare branch: 含 testing 独有文件" \
  "$(test -f "$WORK/prep-branch/from-testing.txt" && echo yes || echo no)" "yes"
check "prepare branch: parent is upstream testing" \
  "$(git -C "$WORK/prep-branch" rev-parse HEAD^ 2>/dev/null || true)" "$TESTING_SHA"

# --- 联网：SagerNet tag + testing 分支都能 fetch 并 reset ---
SAGERNET=https://github.com/SagerNet/sing-box.git
LIVE_TAG="$(git ls-remote "$SAGERNET" 'refs/tags/v1.14.0^{}' | awk '{print $1}')"
if [ -z "$LIVE_TAG" ]; then
  LIVE_TAG="$(git ls-remote "$SAGERNET" 'refs/tags/v1.14.0' | awk '{print $1}')"
fi
LIVE_TESTING="$(git ls-remote "$SAGERNET" 'refs/heads/testing' | awk '{print $1}')"
check "ls-remote: SagerNet v1.14.0 exists" "$( [ -n "$LIVE_TAG" ] && echo yes || echo no )" "yes"
check "ls-remote: SagerNet testing exists" "$( [ -n "$LIVE_TESTING" ] && echo yes || echo no )" "yes"

if [ -n "$LIVE_TAG" ] && [ -n "$LIVE_TESTING" ]; then
  LIVE="$WORK/live"
  git init -b main "$LIVE" >/dev/null
  git_ident "$LIVE"
  echo seed > "$LIVE/seed"
  git -C "$LIVE" add seed
  git -C "$LIVE" commit -m seed >/dev/null
  git -C "$LIVE" remote add upstream "$SAGERNET"
  if ( cd "$LIVE" && fetch_upstream_merge_and_reset v1.14.0 ); then
    check "live: reset --hard v1.14.0" "$(git -C "$LIVE" rev-parse HEAD)" "$LIVE_TAG"
  else
    echo "FAIL: live: fetch v1.14.0"
    FAIL=$((FAIL + 1))
  fi
  if ( cd "$LIVE" && fetch_upstream_merge_and_reset testing ); then
    check "live: reset --hard testing" "$(git -C "$LIVE" rev-parse HEAD)" "$LIVE_TESTING"
  else
    echo "FAIL: live: fetch testing"
    FAIL=$((FAIL + 1))
  fi
fi

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
