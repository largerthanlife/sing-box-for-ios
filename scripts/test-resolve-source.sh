#!/usr/bin/env bash
# resolve-source.sh 的测试样例，本地或 CI 中运行：
#   bash scripts/test-resolve-source.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-source.sh"
PASS=0
FAIL=0

# expect_ok <用例名> <期望的 SB_REF> <repo> <ref> <tag_name>
expect_ok() {
  local name="$1" want_ref="$2"; shift 2
  local got_ref rc
  got_ref=$(bash -c 'source "$0" "$@" >/dev/null; echo "$SB_REF"' "$SCRIPT" "$@")
  rc=$?
  if [ $rc -eq 0 ] && [ "$got_ref" = "$want_ref" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (rc=$rc, got '$got_ref', want '$want_ref')"
    FAIL=$((FAIL + 1))
  fi
}

# expect_err <用例名> <repo> <ref> <tag_name>
expect_err() {
  local name="$1"; shift
  if bash -c 'source "$0" "$@" >/dev/null' "$SCRIPT" "$@" 2>/dev/null; then
    echo "FAIL: $name (expected non-zero exit)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $name"
    PASS=$((PASS + 1))
  fi
}

expect_ok  "默认: 上游仓库 + ref 留空回退到 v<tag_name>"  "v1.13.16"                 "SagerNet/sing-box"       ""                        "1.13.16"
expect_ok  "自定义 fork + 分支名"                          "testing"                  "largerthanlife/sing-box" "testing"                 "1.14.0-beta.8-custom.1"
expect_ok  "自定义 fork + 显式 tag"                        "v1.14.0-beta.8-custom.1"   "largerthanlife/sing-box" "v1.14.0-beta.8-custom.1" ""
expect_ok  "repo 留空回退上游"                             "v1.12.0"                  ""                        ""                        "1.12.0"
expect_err "ref 与 tag_name 同时为空时报错"                "SagerNet/sing-box"        ""                        ""
expect_err "repo 不是 owner/repo 格式时报错"               "https://example.com/x"    ""                        "1.0.0"

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
