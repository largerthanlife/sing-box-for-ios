#!/usr/bin/env bash
# build-tipa.sh — 在 macOS runner 上从指定 sing-box 源码构建 iOS .tipa
#
# 通过环境变量驱动：
#   SB_REPO        (必需) sing-box 源码仓库 (owner/repo)
#   SB_REF         (必需) 要 clone 的分支或 tag
#   TAG_NAME       (必需) 版本号，用于 tipa 文件名
#   MERGE_TAG      (可选) clone 后额外合入的上游 tag，例 v1.14.0-beta.9
#   UPSTREAM_REPO  (可选) MERGE_TAG 的来源仓库，默认 SagerNet/sing-box
#   UPDATE_APPLE   (可选) "true" 时重新拉取最新 sing-box-for-apple
#   DISPLAY_SUFFIX (可选) CFBundleDisplayName 后缀
#   BUNDLE_ID      (可选) 旁加载 Bundle 前缀，默认 io.nekohasekai.sfavt
#                      只通过 BASE_PACKAGE_IDENTIFIER 注入；切勿全局设
#                      PRODUCT_BUNDLE_IDENTIFIER，否则所有 appex 会撞成同一个 ID 导致闪退
#   BASE_PACKAGE_IDENTIFIER (可选) 覆盖全家桶 Bundle 前缀；不设则跟 BUNDLE_ID
#   MARKETING_VERSION (可选) CFBundleShortVersionString，默认用 TAG_NAME
#   CURRENT_PROJECT_VERSION (可选) CFBundleVersion；默认用 TAG_NAME 数字化，避免一直为 1
#   OUTPUT_NAME    (可选) 产物文件名，默认 sing-box-${TAG_NAME}.tipa
#
# 产物写入 ${GITHUB_WORKSPACE}，兼容 macOS 自带 bash 3.2。
set -euo pipefail

: "${SB_REPO:?missing SB_REPO}" "${SB_REF:?missing SB_REF}" "${TAG_NAME:?missing TAG_NAME}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
APPLICATION_NAME=sing-box
OUTPUT_NAME="${OUTPUT_NAME:-${APPLICATION_NAME}-${TAG_NAME}.tipa}"
# 旁加载更新依赖同一 Bundle 前缀；上游 apple 客户端偶发改前缀会导致“装了新包却打开旧 App”
DEFAULT_BUNDLE_ID="io.nekohasekai.sfavt"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
BASE_PACKAGE_IDENTIFIER="${BASE_PACKAGE_IDENTIFIER:-$BUNDLE_ID}"
MARKETING_VERSION="${MARKETING_VERSION:-$TAG_NAME}"
# CFBundleVersion 需单调变化，TrollStore/系统才愿意覆盖安装
if [ -z "${CURRENT_PROJECT_VERSION:-}" ]; then
  CURRENT_PROJECT_VERSION="$(printf '%s' "$TAG_NAME" | tr -cd '0-9')"
  [ -n "$CURRENT_PROJECT_VERSION" ] || CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)"
fi

echo "${BUILD_LABEL:-sing-box}-v${TAG_NAME}" >> "$SUMMARY"
echo "sing-box source: ${SB_REPO}@${SB_REF}" >> "$SUMMARY"
echo "bundle id: ${BUNDLE_ID} (base ${BASE_PACKAGE_IDENTIFIER})" >> "$SUMMARY"
echo "marketing version: ${MARKETING_VERSION} / build ${CURRENT_PROJECT_VERSION}" >> "$SUMMARY"

bash "$(dirname "$0")/prepare-source.sh"
cd "${PREPARE_DIR:-$HOME/sing-box}"
[ -z "${MERGE_TAG:-}" ] || echo "overlaid own files onto upstream ${MERGE_TAG}" >> "$SUMMARY"
echo "embedded version: $(git describe --tags)" >> "$SUMMARY"

make lib_install
export PATH="$PATH:$(go env GOPATH)/bin"
go run ./cmd/internal/build_libbox -target apple -platform ios
mv Libbox.xcframework clients/apple

cd clients/apple

# 上游 entitlements / pbxproj 可能写死 sfamt；旁加载要统一改成目标前缀。
# 不能向 xcodebuild 传入全局 PRODUCT_BUNDLE_IDENTIFIER，否则主 App 与所有
# Extension 会共用同一个 ID，安装后一点就闪退。
rewrite_apple_package_prefix() {
  local want="$1"
  local f
  # shellcheck disable=SC2044
  for f in $(find . \( -name '*.entitlements' -o -name '*.plist' -o -name 'project.pbxproj' \) \
      ! -path './DerivedData/*' ! -path './.git/*'); do
    [ -f "$f" ] || continue
    if grep -q 'io\.nekohasekai\.sfa' "$f" 2>/dev/null; then
      sed -e "s/io\\.nekohasekai\\.sfamt/${want}/g" \
          -e "s/io\\.nekohasekai\\.sfavt/${want}/g" "$f" > "$f.tmp"
      mv "$f.tmp" "$f"
    fi
  done
}

rewrite_apple_package_prefix "$BASE_PACKAGE_IDENTIFIER"
echo "rewrote apple package prefix -> ${BASE_PACKAGE_IDENTIFIER}" >> "$SUMMARY"

XCODE_EXTRA=()
if [ -n "${DISPLAY_SUFFIX:-}" ]; then
  XCODE_EXTRA[${#XCODE_EXTRA[@]}]="INFOPLIST_KEY_CFBundleDisplayName=${APPLICATION_NAME}${DISPLAY_SUFFIX}"
fi
XCODE_EXTRA[${#XCODE_EXTRA[@]}]="BASE_PACKAGE_IDENTIFIER=${BASE_PACKAGE_IDENTIFIER}"
XCODE_EXTRA[${#XCODE_EXTRA[@]}]="MARKETING_VERSION=${MARKETING_VERSION}"
XCODE_EXTRA[${#XCODE_EXTRA[@]}]="CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}"

xcodebuild \
  -project sing-box.xcodeproj \
  -scheme SFI \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath DerivedData \
  -clonedSourcePackagesDirPath "$HOME/Library/Caches/sing-box-source-packages" \
  build \
  STRIP_INSTALLED_PRODUCT=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  ${XCODE_EXTRA[@]+"${XCODE_EXTRA[@]}"}

APP_PATH="DerivedData/Build/Products/Release-iphoneos/${APPLICATION_NAME}.app"

# 构建后校验：扩展 Bundle ID 必须与主 App 不同
MAIN_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Info.plist" 2>/dev/null || true)
EXT_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/PlugIns/Extension.appex/Info.plist" 2>/dev/null || true)
if [ -z "$MAIN_ID" ] || [ -z "$EXT_ID" ]; then
  echo "failed to read bundle ids from built app (main=[$MAIN_ID] ext=[$EXT_ID])" >&2
  exit 1
fi
if [ "$MAIN_ID" = "$EXT_ID" ]; then
  echo "refusing to package tipa: Extension Bundle ID equals app ID ($MAIN_ID); this crashes on launch" >&2
  exit 1
fi
case "$EXT_ID" in
  "$MAIN_ID".*) ;;
  *)
    echo "warning: Extension ID [$EXT_ID] is not under app ID [$MAIN_ID]" >> "$SUMMARY"
    ;;
esac
echo "bundle ids ok: app=${MAIN_ID} extension=${EXT_ID}" >> "$SUMMARY"
ldid -SSFI/SFI.entitlements "${APP_PATH}/${APPLICATION_NAME}"
ldid -SExtension/Extension.entitlements "${APP_PATH}/PlugIns/Extension.appex/Extension"
ldid -SIntentsExtension/IntentsExtension.entitlements "${APP_PATH}/Extensions/IntentsExtension.appex/IntentsExtension"

# Taildrop / 分享相关扩展：不签的话会出现在系统分享菜单里，但点开无反应或秒退
sign_appex() {
  local entitlements="$1" binary="$2"
  if [ -f "$binary" ]; then
    ldid -S"$entitlements" "$binary"
    echo "ldid signed: $binary"
  else
    echo "skip ldid (missing): $binary"
  fi
}
sign_appex ShareExtension/ShareExtension.entitlements \
  "${APP_PATH}/PlugIns/ShareExtension.appex/ShareExtension"
sign_appex ActionExtension/ActionExtension.entitlements \
  "${APP_PATH}/PlugIns/ActionExtension.appex/ActionExtension"
sign_appex FileProviderExtension/FileProviderExtension.entitlements \
  "${APP_PATH}/PlugIns/FileProviderExtension.appex/FileProviderExtension"
sign_appex WidgetExtension/WidgetExtension.entitlements \
  "${APP_PATH}/PlugIns/WidgetExtension.appex/WidgetExtension"

mkdir -p packages/Payload
cp -rp "${APP_PATH}" packages/Payload
cd packages
zip -qr "${APPLICATION_NAME}.tipa" Payload
mv "${APPLICATION_NAME}.tipa" "${GITHUB_WORKSPACE}/${OUTPUT_NAME}"
cd "${GITHUB_WORKSPACE}"
echo -e "SHA256 Checksum: \n$(sha256sum "${OUTPUT_NAME}")" >> "$SUMMARY"

rm -rf "$HOME/sing-box"
