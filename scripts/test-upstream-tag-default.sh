#!/usr/bin/env bash
# test-upstream-tag-default.sh — 手动构建留空 upstream_tag 时不得回落到 testing
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="$ROOT/.github/workflows/sing-box-for-ios.yml"
fail=0

[ -f "$WF" ] || { echo "missing $WF" >&2; exit 1; }

block=$(awk '
  $0 ~ /^      upstream_tag:/ { in_block=1; next }
  in_block && $0 ~ /^      [A-Za-z0-9_-]+:/ { exit }
  in_block { print }
' "$WF")

if [ -z "$block" ]; then
  echo "FAIL: upstream_tag input not found" >&2
  exit 1
fi

default_line=$(printf '%s\n' "$block" | grep -E '^[[:space:]]*default:' || true)
case "$default_line" in
  "        default: ''" | '        default: ""')
    echo "ok: upstream_tag default is empty"
    ;;
  *)
    echo "FAIL: upstream_tag default must be an empty string (got '${default_line}')" >&2
    fail=1
    ;;
esac

if [ "$fail" -ne 0 ]; then
  echo "upstream_tag default checks failed" >&2
  exit 1
fi
echo "all upstream_tag default checks passed"
