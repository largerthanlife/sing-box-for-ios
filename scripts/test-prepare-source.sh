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
APPLE_DEV="$(git ls-remote https://github.com/SagerNet/sing-box-for-apple.git HEAD | cut -f1)"
APPLE_MAIN="$(git ls-remote https://github.com/SagerNet/sing-box-for-apple.git refs/heads/main | cut -f1)"

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

# 场景 2: overlay 发版 tag v1.14.0 + UPDATE_APPLE=true → apple 停在 Bump version 1.14.0，不是漂着的 main
env -i PATH="$PATH" HOME="$WORK/h2" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  MERGE_TAG=v1.14.0 UPDATE_APPLE=true OVERLAY_LIST="$SCRIPT_DIR/overlay-files.txt" \
  PREPARE_DIR="$WORK/s2" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1
case "$(git -C "$WORK/s2" describe --tags 2>/dev/null)" in
  v1.14.0*)
    echo "PASS: overlay+update tag: describe 基于 v1.14.0"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "FAIL: overlay+update tag: describe=$(git -C "$WORK/s2" describe --tags 2>&1)"
    FAIL=$((FAIL + 1))
    ;;
esac
check "overlay+update tag: apple 是 Bump version 1.14.0" \
  "$(git -C "$WORK/s2/clients/apple" log -1 --format=%s 2>/dev/null || true)" \
  "Bump version 1.14.0"
check "overlay+update tag: apple 不是 floating main" \
  "$( [ "$(git -C "$WORK/s2/clients/apple" rev-parse HEAD 2>/dev/null)" != "$APPLE_MAIN" ] && echo yes || echo no )" \
  "yes"
check "overlay+update tag: apple 不是 floating dev" \
  "$( [ "$(git -C "$WORK/s2/clients/apple" rev-parse HEAD 2>/dev/null)" != "$APPLE_DEV" ] && echo yes || echo no )" \
  "yes"
if [ -f "$WORK/s2/protocol/shadowsocks/method_chacha20.go" ]; then
  echo "PASS: overlay+update tag: 自有文件已叠上"
  PASS=$((PASS + 1))
else
  echo "FAIL: overlay+update tag: method_chacha20.go 缺失"
  FAIL=$((FAIL + 1))
fi
# 1.14.0 apple 已有 Taildrop，补丁应打上
check "overlay+update tag: Taildrop 发送区 v5 补丁" \
  "$(grep -c 'cursor-taildrop-send-tap-fix-v5' \
    "$WORK/s2/clients/apple/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" 2>/dev/null || echo 0)" \
  "1"
check "overlay+update tag: ShareView iOS15 补丁" \
  "$(grep -c 'cursor-taildrop-share-ios15-v2' \
    "$WORK/s2/clients/apple/ShareExtension/ShareView.swift" 2>/dev/null || echo 0)" \
  "1"

# 场景 2b: 可选「追官方 testing」—— overlay testing + apple 默认分支(dev)
# 手动 workflow 默认应走场景 2（发版 tag 底）；testing/dev 曾导致 tipa 秒退。
SAGERNET_TESTING="$(git ls-remote https://github.com/SagerNet/sing-box.git refs/heads/testing | awk '{print $1}')"
if env -i PATH="$PATH" HOME="$WORK/h2b" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  MERGE_TAG=testing UPDATE_APPLE=true OVERLAY_LIST="$SCRIPT_DIR/overlay-files.txt" \
  PREPARE_DIR="$WORK/s2b" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1; then
  echo "PASS: overlay+update testing: 成功"
  PASS=$((PASS + 1))
else
  echo "FAIL: overlay+update testing: prepare-source 失败"
  FAIL=$((FAIL + 1))
fi
check "overlay+update testing: apple == default/dev" \
  "$(git -C "$WORK/s2b/clients/apple" rev-parse HEAD 2>/dev/null || true)" "$APPLE_DEV"
check "overlay+update testing: apple 不是 main" \
  "$( [ "$(git -C "$WORK/s2b/clients/apple" rev-parse HEAD 2>/dev/null)" != "$APPLE_MAIN" ] && echo yes || echo no )" \
  "yes"
check "overlay+update testing: createAutoRedirect 存在" \
  "$(grep -R -l 'createAutoRedirect' "$WORK/s2b/clients/apple" --include='*.swift' >/dev/null 2>&1 && echo yes || echo no)" \
  "yes"
check "overlay+update testing: parent is SagerNet testing" \
  "$(git -C "$WORK/s2b" rev-parse HEAD^ 2>/dev/null || true)" "$SAGERNET_TESTING"
if [ -f "$WORK/s2b/protocol/shadowsocks/method_chacha20.go" ] && \
   [ -f "$WORK/s2b/protocol/shadowsocks/method_chacha20_test.go" ]; then
  echo "PASS: overlay+update testing: 自有 chacha20 文件已叠上"
  PASS=$((PASS + 1))
else
  echo "FAIL: overlay+update testing: chacha20 文件缺失"
  FAIL=$((FAIL + 1))
fi
check "overlay+update testing: Taildrop 发送区 v5 补丁" \
  "$(grep -c 'cursor-taildrop-send-tap-fix-v5' \
    "$WORK/s2b/clients/apple/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" 2>/dev/null || echo 0)" \
  "1"
check "overlay+update testing: DropView tap 手势已移除" \
  "$(grep -c 'cursor-taildrop-drop-tap-removed' \
    "$WORK/s2b/clients/apple/ApplicationLibrary/Views/Tools/TaildropSendManager.swift" 2>/dev/null || echo 0)" \
  "1"
check "overlay+update testing: ShareView iOS15 补丁" \
  "$(grep -c 'cursor-taildrop-share-ios15-v2' \
    "$WORK/s2b/clients/apple/ShareExtension/ShareView.swift" 2>/dev/null || echo 0)" \
  "1"
check "overlay+update testing: Share toolbar iOS15" \
  "$(grep -c 'cursor-taildrop-share-toolbar-ios15' \
    "$WORK/s2b/clients/apple/ShareExtension/ShareView.swift" 2>/dev/null || echo 0)" \
  "1"
check "overlay+update testing: Share/Action deployment 15.0 标记" \
  "$(grep -c 'cursor-taildrop-share-ios15-pbx' \
    "$WORK/s2b/clients/apple/sing-box.xcodeproj/project.pbxproj" 2>/dev/null || echo 0)" \
  "1"

# 场景 3: 上游大幅改动后的 overlay（真实回归 beta.14：merge 会拼出编不过的树；
# overlay 必须得到干净上游树 + 自有文件，且不含 fork 残留的已删文件）
if env -i PATH="$PATH" HOME="$WORK/h3" SB_REPO=largerthanlife/sing-box SB_REF=testing \
  MERGE_TAG=v1.14.0-beta.14 OVERLAY_LIST="$SCRIPT_DIR/overlay-files.txt" \
  PREPARE_DIR="$WORK/s3" bash "$SCRIPT_DIR/prepare-source.sh" >/dev/null 2>&1; then
  echo "PASS: overlay beta.14: 成功"
  PASS=$((PASS + 1))
else
  echo "FAIL: overlay beta.14: prepare-source 失败"
  FAIL=$((FAIL + 1))
fi
if [ -f "$WORK/s3/protocol/shadowsocks/method_chacha20.go" ] && \
   [ -f "$WORK/s3/protocol/shadowsocks/method_chacha20_test.go" ]; then
  echo "PASS: overlay beta.14: 自有文件保留"
  PASS=$((PASS + 1))
else
  echo "FAIL: overlay beta.14: chacha20 文件缺失"
  FAIL=$((FAIL + 1))
fi
if [ ! -e "$WORK/s3/common/process/searcher_android.go" ] && \
   [ ! -e "$WORK/s3/dns/transport/local/local_dhcp.go" ] && \
   [ ! -e "$WORK/s3/dns/transport/local/resolv.go" ]; then
  echo "PASS: overlay beta.14: 上游已删/旧残留文件未带回"
  PASS=$((PASS + 1))
else
  echo "FAIL: overlay beta.14: 仍有上游已删的残留文件"
  FAIL=$((FAIL + 1))
fi
case "$(git -C "$WORK/s3" describe --tags 2>/dev/null)" in
  v1.14.0-beta.14*)
    echo "PASS: overlay beta.14: describe 基于 v1.14.0-beta.14"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "FAIL: overlay beta.14: describe=$(git -C "$WORK/s3" describe --tags 2>&1)"
    FAIL=$((FAIL + 1))
    ;;
esac
if [ -z "$(git -C "$WORK/s3" status --porcelain)" ]; then
  echo "PASS: overlay beta.14: 工作树干净"
  PASS=$((PASS + 1))
else
  echo "FAIL: overlay beta.14: 工作树不干净"
  FAIL=$((FAIL + 1))
fi

echo "---- ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
