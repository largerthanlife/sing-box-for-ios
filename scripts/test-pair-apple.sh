#!/usr/bin/env bash
# pair-apple.sh 测试：分支→默认分支(dev)，发版 tag→Bump version（不漂在 dev/main 上）
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

# sing_box_ref 仍默认 testing。upstream_tag 留空表示直接用该 ref，不合入。
# 秒退根因是 ldid 未展开 app group 宏（另测）。
WF="$SCRIPT_DIR/../.github/workflows/sing-box-for-ios.yml"
check "workflow default sing_box_ref=testing" \
  "$(grep -A4 'sing_box_ref:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://')" \
  "testing"
check "workflow default upstream_tag is empty" \
  "$(grep -A4 'upstream_tag:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://')" \
  ""
check "workflow default update_apple=true" \
  "$(grep -A4 'update_apple:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://')" \
  "true"
check "version: v1.14.0" "$(apple_version_from_ref v1.14.0)" "1.14.0"
check "version: 1.14.0" "$(apple_version_from_ref 1.14.0)" "1.14.0"
check "version: v1.14.0-beta.8" "$(apple_version_from_ref v1.14.0-beta.8)" "1.14.0-beta.8"
check "version: testing is empty" "$(apple_version_from_ref testing)" ""
check "version: main is empty" "$(apple_version_from_ref main)" ""
check "pair: reality branch one commit after alpha.6" \
  "$(choose_apple_pair cursor/reality-mlkem-alpha6-5e10 "" "" v1.15.0-alpha.6 1)" \
  "v1.15.0-alpha.6|tag"
check "pair: testing stays on branch even near a tag" \
  "$(choose_apple_pair testing "" "" v1.15.0-alpha.6 1)" \
  "testing|"
check "pair: explicit merge tag wins" \
  "$(choose_apple_pair testing v1.15.0-alpha.6 tag v1.14.0 1)" \
  "v1.15.0-alpha.6|tag"
check "pair: far-ahead custom branch does not snap to old tag" \
  "$(choose_apple_pair cursor/some-branch "" "" v1.15.0-alpha.6 40)" \
  "cursor/some-branch|"

# fork 只有旧 tag 时，要从上游把 v1.15.0-alpha.6 取回来
UPSTREAM="$WORK/upstream-sing"
git init -b main "$UPSTREAM" >/dev/null
git_ident "$UPSTREAM"
echo base > "$UPSTREAM/f"
git -C "$UPSTREAM" add f
git -C "$UPSTREAM" commit -m base >/dev/null
git -C "$UPSTREAM" tag v1.9.7
i=0
while [ "$i" -lt 25 ]; do
  echo "$i" >> "$UPSTREAM/f"
  git -C "$UPSTREAM" commit -am "gap $i" >/dev/null
  i=$((i + 1))
done
echo alpha > "$UPSTREAM/f"
git -C "$UPSTREAM" commit -am 'alpha.6' >/dev/null
git -C "$UPSTREAM" tag v1.15.0-alpha.6
echo fix > "$UPSTREAM/f"
git -C "$UPSTREAM" commit -am 'reality' >/dev/null
FORK="$WORK/fork-sing"
git clone --no-tags "$UPSTREAM" "$FORK" >/dev/null
git_ident "$FORK"
git -C "$FORK" tag v1.9.7 "$(git -C "$UPSTREAM" rev-parse v1.9.7)"
check "nearest tag: fork only has v1.9.7 until upstream fetch" \
  "$(git -C "$FORK" describe --tags --abbrev=0)" \
  "v1.9.7"
check "nearest tag: fetch upstream finds alpha.6" \
  "$(cd "$FORK" && UPSTREAM_CLONE_URL="$UPSTREAM" nearest_version_tag)" \
  "v1.15.0-alpha.6"

# 假 apple 仓库：default=dev（含 auto redirect stub），main 上有 Bump 1.14.0 后再超前
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
git -C "$APPLE" checkout -b dev >/dev/null
echo 'func createAutoRedirect()' > "$APPLE/ExtensionPlatformInterface.swift"
git -C "$APPLE" add ExtensionPlatformInterface.swift
git -C "$APPLE" commit -m 'Add stub for platform auto redirect' >/dev/null
DEV_HEAD="$(git -C "$APPLE" rev-parse HEAD)"
# clone 不传 -b 时用 HEAD / 默认分支
git -C "$APPLE" symbolic-ref HEAD refs/heads/dev

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
check "branch pair: HEAD is apple default (dev)" \
  "$(git -C "$WORK/out-branch" rev-parse HEAD 2>/dev/null || true)" "$DEV_HEAD"
check "branch pair: 含 auto redirect stub" \
  "$(test -f "$WORK/out-branch/ExtensionPlatformInterface.swift" && echo yes || echo no)" "yes"
check "branch pair: 不是 main 超前提交" \
  "$( [ "$(git -C "$WORK/out-branch" rev-parse HEAD 2>/dev/null)" != "$MAIN_HEAD" ] && echo yes || echo no )" \
  "yes"

if APPLE_CLONE_URL="$APPLE" clone_paired_apple "$WORK/out-missing" v9.9.9 tag >/dev/null 2>&1; then
  echo "FAIL: missing bump should error (not fall back to main)"
  FAIL=$((FAIL + 1))
else
  echo "PASS: missing bump refuses floating main"
  PASS=$((PASS + 1))
fi

# Bump 提交不在任何分支上时，按 SHA 取回，并核对提交说明
ORPHAN_SRC="$WORK/orphan-src"
git init -b main "$ORPHAN_SRC" >/dev/null
git_ident "$ORPHAN_SRC"
echo base > "$ORPHAN_SRC/version.txt"
git -C "$ORPHAN_SRC" add version.txt
git -C "$ORPHAN_SRC" commit -m base >/dev/null
echo 987 > "$ORPHAN_SRC/version.txt"
git -C "$ORPHAN_SRC" commit -am 'Bump version 9.8.7' >/dev/null
ORPHAN_SHA="$(git -C "$ORPHAN_SRC" rev-parse HEAD)"
git -C "$ORPHAN_SRC" reset --hard HEAD~1 >/dev/null
git -C "$ORPHAN_SRC" config uploadpack.allowAnySHA1InWant true
printf '9.8.7 %s\n' "$ORPHAN_SHA" > "$WORK/orphans.txt"
if APPLE_CLONE_URL="$ORPHAN_SRC" APPLE_BUMP_ORPHANS="$WORK/orphans.txt" \
    clone_paired_apple "$WORK/out-orphan" v9.8.7 tag >/dev/null; then
  echo "PASS: orphan bump fetched by SHA"
  PASS=$((PASS + 1))
else
  echo "FAIL: orphan bump fetched by SHA"
  FAIL=$((FAIL + 1))
fi
check "orphan bump: HEAD is the dangling commit" \
  "$(git -C "$WORK/out-orphan" rev-parse HEAD 2>/dev/null || true)" "$ORPHAN_SHA"
check "orphan bump: message" \
  "$(git -C "$WORK/out-orphan" log -1 --format=%s 2>/dev/null || true)" \
  "Bump version 9.8.7"

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

# 联网：官方 apple 的 v1.14.0 应对上 Bump version 1.14.0，且不是默认分支(dev)
APPLE_REMOTE=https://github.com/SagerNet/sing-box-for-apple.git
LIVE_DEV="$(git ls-remote "$APPLE_REMOTE" HEAD | awk '{print $1}')"
LIVE_MAIN="$(git ls-remote "$APPLE_REMOTE" refs/heads/main | awk '{print $1}')"
if clone_paired_apple "$WORK/live-114" v1.14.0 tag; then
  LIVE_MSG="$(git -C "$WORK/live-114" log -1 --format=%s)"
  check "live: v1.14.0 message is Bump version 1.14.0" "$LIVE_MSG" "Bump version 1.14.0"
  check "live: v1.14.0 is not floating default/dev" \
    "$( [ "$(git -C "$WORK/live-114" rev-parse HEAD)" != "$LIVE_DEV" ] && echo yes || echo no )" \
    "yes"
  check "live: v1.14.0 is not floating main" \
    "$( [ "$(git -C "$WORK/live-114" rev-parse HEAD)" != "$LIVE_MAIN" ] && echo yes || echo no )" \
    "yes"
else
  echo "FAIL: live clone_paired_apple v1.14.0"
  FAIL=$((FAIL + 1))
fi

# 1.15.0-alpha.6 的 Bump 已被 rebase 出全部分支，只能按记录的 SHA 取回
if clone_paired_apple "$WORK/live-a6" v1.15.0-alpha.6 tag; then
  check "live: alpha.6 message is Bump version 1.15.0-alpha.6" \
    "$(git -C "$WORK/live-a6" log -1 --format=%s)" "Bump version 1.15.0-alpha.6"
  check "live: alpha.6 sha" \
    "$(git -C "$WORK/live-a6" rev-parse HEAD)" "511571f13cec0989b68c7ec72f31310b87dc0e89"
  A6_RESOLVED="$WORK/live-a6/sing-box.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  check "live: alpha.6 pins ghostty 1.5.20260906" \
    "$(grep -c '733ae3b29d447b6707cbfc00879027a076dfd0eb' "$A6_RESOLVED")" "1"
  check "live: alpha.6 pins MSDisplayLink 2.2.0" \
    "$(grep -c '87eb0af130744c8cbe2e31b6e1a5bcd659f1c220' "$A6_RESOLVED")" "1"
  check "live: alpha.6 does not pin DisplayLink 3" \
    "$(grep -c 'github.com/Lakr233/DisplayLink.git' "$A6_RESOLVED")" "0"
  check "live: alpha.6 has createAutoRedirect" \
    "$(grep -R -l 'createAutoRedirect' "$WORK/live-a6" --include='*.swift' >/dev/null && echo yes || echo no)" \
    "yes"
else
  echo "FAIL: live clone_paired_apple v1.15.0-alpha.6"
  FAIL=$((FAIL + 1))
fi

if clone_paired_apple "$WORK/live-dev" testing branch; then
  check "live: testing pairs apple default/dev" \
    "$(git -C "$WORK/live-dev" rev-parse HEAD)" "$LIVE_DEV"
  check "live: default branch has createAutoRedirect" \
    "$(grep -R -l 'createAutoRedirect' "$WORK/live-dev" --include='*.swift' >/dev/null && echo yes || echo no)" \
    "yes"
else
  echo "FAIL: live clone_paired_apple testing -> default branch"
  FAIL=$((FAIL + 1))
fi

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
