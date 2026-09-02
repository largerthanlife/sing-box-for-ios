#!/usr/bin/env bash
# tipa-version.sh — tipa 的 CFBundleShortVersionString / CFBundleVersion 规范化
#
# iOS 要求 MARKETING_VERSION 形如 X / X.Y / X.Y.Z（纯数字段）。把 tag_name
# 直接塞进去（例 1.14.0-testing）会让部分旁加载器/系统在启动时秒退。
#
#   sanitize_marketing_version <tag_or_version>
#   derive_project_version <tag_or_version> [fallback_timestamp]
#
# 可被 source；也可 `bash tipa-version.sh <cmd> ...` 单测。

sanitize_marketing_version() {
  local raw="${1:-}"
  local cleaned
  # 去掉可选的前导 v，再取开头连续的数字.数字 段
  cleaned="$(printf '%s' "$raw" | sed -E 's/^[vV]//; s/^([0-9]+(\.[0-9]+){0,2}).*/\1/')"
  case "$cleaned" in
    '' | *[!0-9.]* | .* | *. | *..*)
      printf ''
      return 1
      ;;
  esac
  printf '%s\n' "$cleaned"
}

derive_project_version() {
  local raw="${1:-}"
  local stamp="${2:-}"
  local digits
  digits="$(printf '%s' "$raw" | tr -cd '0-9')"
  # 纯 X.Y.Z → 用去掉点的数字，便于和发版号对应；带后缀的 tag 必须换单调
  # 构建号，否则覆盖安装时 CFBundleVersion 与旧包相同，旁加载可能装不干净。
  if printf '%s' "$raw" | grep -Eq '^[vV]?[0-9]+(\.[0-9]+){0,2}$'; then
    if [ -n "$digits" ]; then
      printf '%s\n' "$digits"
      return 0
    fi
  fi
  if [ -z "$stamp" ]; then
    stamp="$(date +%Y%m%d%H%M)"
  fi
  printf '%s\n' "$stamp"
}

if [ "${BASH_SOURCE[0]-}" = "$0" ]; then
  set -euo pipefail
  cmd="${1:-}"
  shift || true
  case "$cmd" in
    sanitize_marketing_version | derive_project_version)
      "$cmd" "$@"
      ;;
    *)
      echo "usage: $0 sanitize_marketing_version|derive_project_version <args...>" >&2
      exit 2
      ;;
  esac
fi
