#!/usr/bin/env bash
# expand-entitlements.sh — 把 Xcode 宏展开成旁加载可用的字面量
#
# 上游 apple 自 68ba9ce（Update bundle id）起，*.entitlements 里写的是
# $(APP_GROUP_IDENTIFIER) / $(BASE_PACKAGE_IDENTIFIER)。正式 Xcode 签名会展开；
# 我们 tipa 走 ldid -S<source.entitlements>，不展开就会把字面量 $(...) 写进二进制。
# App 启动时 FilePath.sharedDirectory 按 Info.plist 的 group.io... 去要容器，
# entitlements 对不上 → containerURL 为 nil → 强制解包秒退。
#
#   expand_entitlements_file <src.entitlements> <dest.entitlements>
#   APP_GROUP 固定为 group.<BASE_PACKAGE_IDENTIFIER>（与 iOS pbxproj 一致）

expand_entitlements_file() {
  local src="${1:?}" dest="${2:?}"
  local base="${BASE_PACKAGE_IDENTIFIER:?missing BASE_PACKAGE_IDENTIFIER}"
  local group="group.${base}"

  if [ ! -f "$src" ]; then
    echo "entitlements not found: $src" >&2
    return 1
  fi

  # TeamIdentifierPrefix 在旁加载/TrollStore 下为空；先清掉再展开其余宏
  sed -e 's/\$([Tt]eamIdentifierPrefix)//g' \
    -e "s/\$(BASE_PACKAGE_IDENTIFIER)/${base}/g" \
    -e "s/\$(APP_GROUP_IDENTIFIER)/${group}/g" \
    "$src" >"$dest"

  if grep -E '\$\([A-Za-z0-9_]+\)' "$dest" >/dev/null; then
    echo "refusing: unexpanded macros remain in expanded entitlements ($src → $dest):" >&2
    grep -E '\$\([A-Za-z0-9_]+\)' "$dest" >&2 || true
    return 1
  fi
  if ! grep -F "$group" "$dest" >/dev/null; then
    echo "refusing: expanded entitlements missing app group ${group} ($src)" >&2
    return 1
  fi
}

if [ "${BASH_SOURCE[0]-}" = "$0" ]; then
  set -euo pipefail
  : "${BASE_PACKAGE_IDENTIFIER:?}"
  expand_entitlements_file "$@"
fi
