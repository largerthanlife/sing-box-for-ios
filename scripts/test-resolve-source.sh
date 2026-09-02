#!/usr/bin/env bash
# resolve-source.sh 的测试样例，本地或 CI 中运行：
#   bash scripts/test-resolve-source.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-source.sh"
PASS=0
FAIL=0

# expect_ok <用例名> <期望 SB_REF> <期望 MERGE_TAG> <repo> <ref> <tag_name> [merge_tag]
expect_ok() {
  local name="$1" want_ref="$2" want_merge="$3"; shift 3
  local got rc
  got=$(bash -c 'source "$0" "$@" >/dev/null; echo "${SB_REF}|${MERGE_TAG}"' "$SCRIPT" "$@")
  rc=$?
  if [ $rc -eq 0 ] && [ "$got" = "${want_ref}|${want_merge}" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (rc=$rc, got '$got', want '${want_ref}|${want_merge}')"
    FAIL=$((FAIL + 1))
  fi
}

# expect_err <用例名> <repo> <ref> <tag_name> [merge_tag]
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

expect_ok  "默认: fork 仓库 + ref 留空回退到 v<tag_name>"  "v1.13.16"               ""                  "SagerNet/sing-box"       ""                        "1.13.16"
expect_ok  "自定义 fork + 分支名"                          "testing"                ""                  "largerthanlife/sing-box" "testing"                 "1.14.0-beta.8-custom.1"
expect_ok  "自定义 fork + 显式 tag"                        "v1.14.0-beta.8-custom.1" ""                  "largerthanlife/sing-box" "v1.14.0-beta.8-custom.1" ""
expect_ok  "repo 留空回退到 fork 默认"                     "v1.12.0"                ""                  ""                        ""                        "1.12.0"
expect_ok  "分支 + 合入上游 tag"                           "testing"                "v1.14.0-beta.9"    "largerthanlife/sing-box" "testing"                 "1.14.0-beta.9"           "v1.14.0-beta.9"
expect_ok  "分支 + 合入上游分支 testing"                    "testing"                "testing"           "largerthanlife/sing-box" "testing"                 "1.14.0-testing"          "testing"
expect_err "ref 与 tag_name 同时为空时报错"                "SagerNet/sing-box"       ""                  ""
expect_err "repo 不是 owner/repo 格式时报错"               "https://example.com/x"   ""                  "1.0.0"
expect_err "merge tag 含非法字符时报错"                    "largerthanlife/sing-box" "testing"           "1.0.0"                   "v1.0; rm -rf /"

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
