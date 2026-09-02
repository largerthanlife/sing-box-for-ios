#!/usr/bin/env bash
# expand-entitlements.sh 测试样例
#   bash scripts/test-expand-entitlements.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=expand-entitlements.sh
source "$SCRIPT_DIR/expand-entitlements.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

check() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1 (got '$2', want '$3')"
    FAIL=$((FAIL + 1))
  fi
}

# 模拟上游 68ba9ce 之后的 entitlements（含宏）
cat >"$WORK/SFI.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.$(BASE_PACKAGE_IDENTIFIER)</string>
	</array>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>$(APP_GROUP_IDENTIFIER)</string>
	</array>
</dict>
</plist>
EOF

# rc.1 时代：已是字面量，展开后应保持可用
cat >"$WORK/legacy.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.io.nekohasekai.sfavt</string>
	</array>
</dict>
</plist>
EOF

export BASE_PACKAGE_IDENTIFIER=io.nekohasekai.sfavt

if expand_entitlements_file "$WORK/SFI.entitlements" "$WORK/out.entitlements"; then
  echo "PASS: expand modern entitlements"
  PASS=$((PASS + 1))
else
  echo "FAIL: expand modern entitlements"
  FAIL=$((FAIL + 1))
fi

check "modern: app group literal" \
  "$(grep -c 'group.io.nekohasekai.sfavt' "$WORK/out.entitlements" || true)" "1"
check "modern: no APP_GROUP macro" \
  "$(grep -c 'APP_GROUP_IDENTIFIER' "$WORK/out.entitlements" || true)" "0"
check "modern: iCloud expanded" \
  "$(grep -c 'iCloud.io.nekohasekai.sfavt' "$WORK/out.entitlements" || true)" "1"
check "modern: no leftover \$(" \
  "$(grep -c '\$(' "$WORK/out.entitlements" || true)" "0"

if expand_entitlements_file "$WORK/legacy.entitlements" "$WORK/legacy-out.entitlements"; then
  echo "PASS: expand legacy entitlements"
  PASS=$((PASS + 1))
else
  echo "FAIL: expand legacy entitlements"
  FAIL=$((FAIL + 1))
fi
check "legacy: keeps group" \
  "$(grep -c 'group.io.nekohasekai.sfavt' "$WORK/legacy-out.entitlements" || true)" "1"

# 未知宏必须拒绝
cat >"$WORK/bad.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>$(APP_GROUP_IDENTIFIER)</string>
	</array>
	<key>something</key>
	<string>$(UNKNOWN_MACRO)</string>
</dict>
</plist>
EOF
if expand_entitlements_file "$WORK/bad.entitlements" "$WORK/bad-out.entitlements" 2>/dev/null; then
  echo "FAIL: unknown macro should refuse"
  FAIL=$((FAIL + 1))
else
  echo "PASS: unknown macro refused"
  PASS=$((PASS + 1))
fi

# 最新 tipa 默认可追 testing；崩溃根因是 entitlements 宏未展开
WF="$SCRIPT_DIR/../.github/workflows/sing-box-for-ios.yml"
check "workflow default upstream_tag=testing" \
  "$(grep -A4 'upstream_tag:' "$WF" | grep "default:" | head -1 | tr -d " '" | sed 's/default://')" \
  "testing"

echo
echo "expand-entitlements: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
